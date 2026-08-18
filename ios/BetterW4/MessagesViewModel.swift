//
//  MessagesViewModel.swift
//  BetterW4
//
//  State for the Mail tab (plan Wave 6 item 6.2, `docs/spec/ui.md` §4.2).
//
//  W4's mailer is a FLAT LIST. There are no threads, no replies, no reactions, no message
//  editing and no BBCode — every one of those was Lectio's and died with `MessageModels.swift`
//  (plan §1.4 kill list). What is left is two grids, `mailer/inbox` and `mailer/archive`, and a
//  detail page per message.
//
//  Everything network-shaped lives in `MailRepository`; this type never touches a parser, a
//  cookie or a URL. What it owns is the four behaviours from `features.md` §3 that made the old
//  app feel good, and they are the reason this file is not just `messages = try await …`:
//
//    1. **Generation + folder guard.** Every load takes a ticket. A response is applied only if
//       its ticket is still the newest *and* the folder it was asked for is still the selected
//       one. Switching Inbox → Sent → Inbox fast can therefore never paint Sent's rows into the
//       Inbox, which is the classic stale-overwrite bug.
//    2. **Cache first, then refresh.** `cachedList` paints the screen before anything is awaited
//       over the network; `list` then refreshes in the background.
//    3. **A spinner only when there is nothing to show.** If a cached grid rendered, a refresh is
//       silent — pull-to-refresh gets the system's own indicator.
//    4. **A transient failure never wipes the list.** An offline refresh over a warm cache leaves
//       the rows alone and sets no error at all; an error is surfaced only when the screen would
//       otherwise be blank. `W4Error.sessionExpired` is the single exception that logs the
//       student out (via `notifyIfSessionExpired`); `W4Error.forbidden` explicitly does not.
//
//  The unread badge is not published from here. `MailFileCache` posts
//  `.unreadMessageCountDidChange` whenever the inbox grid is written, so the tab badge updates
//  from a prefetch, a pull-to-refresh or this screen appearing, without any of them knowing
//  about the tab bar.
//

import Combine
import Foundation

@MainActor
final class MessagesViewModel: ObservableObject {

    // MARK: - Published state

    /// Which grid is on screen. Changing it is what drives a reload (the view `.task(id:)`s on it).
    @Published var selectedFolder: MailFolder = .inbox

    /// Live `.searchable` text. Filtering is local to the loaded page — W4's grid search is a
    /// server-side Yii filter that has never been captured, so we do not pretend to offer it.
    @Published var searchQuery: String = ""

    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var outcome: MailListOutcome?
    @Published private(set) var unreadCount = 0

    /// True when W4 answered with a grid this app could not read while a cached grid is still on
    /// screen. The rows below are the older, good ones — the UI says so rather than quietly
    /// showing yesterday's mail as if it were live.
    @Published private(set) var markupWarning = false

    /// W4 paginates the mailer. We render page one and say so rather than implying it is
    /// everything (`MailPagination` is unverified — plan OQ-4).
    @Published private(set) var hasMorePages = false

    let folders: [MailFolder] = MailFolder.all

    // MARK: - Dependencies

    private let repository: MailRepository

    /// Load ticket. See behaviour 1 in the file comment.
    private var generation = 0
    /// The folder whose rows `messages` currently holds, so a folder switch can blank the list
    /// instead of showing the wrong mailbox for one frame.
    private var loadedFolderID: String?

    init(repository: MailRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Derived

    /// Case- and diacritic-insensitive match on subject and sender.
    var visibleMessages: [MailMessage] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return messages }
        return messages.filter { message in
            message.subject.localizedCaseInsensitiveContains(query)
                || (message.from?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// W4 itself said the mailbox is empty — as opposed to "we could not read the page".
    var isEmptyState: Bool {
        messages.isEmpty && outcome == .emptyState
    }

    /// The page did not parse and there is nothing cached to fall back on.
    var isUnreadableState: Bool {
        messages.isEmpty && outcome == .unrecognised
    }

    /// "Updated 12:04" / "Offline — showing saved mail" material for the list header.
    var cachedAt: Date? { freshness?.fetchedAt }

    var isShowingCachedCopy: Bool { freshness?.isFromCache ?? false }

    // MARK: - Loading

    /// Cache-first load of the selected folder.
    ///
    /// - Parameter forceRefresh: skips the 5-minute TTL. Pull-to-refresh and "caches cleared".
    func load(forceRefresh: Bool = false) async {
        generation += 1
        let ticket = generation
        let target = selectedFolder

        errorMessage = nil
        markupWarning = false

        // A folder switch must not show the previous mailbox's rows under the new heading.
        if loadedFolderID != target.id {
            messages = []
            freshness = nil
            outcome = nil
            hasMorePages = false
        }

        // 1. Paint whatever is on disk before awaiting the network at all.
        if let cached = await repository.cachedList(folder: target) {
            guard isCurrent(ticket, target) else { return }
            apply(cached, folder: target)
        }

        // 2. Spinner only if the screen would otherwise be blank.
        isLoading = messages.isEmpty

        // 3. Refresh.
        do {
            let loaded = try await repository.list(folder: target, forceRefresh: forceRefresh)
            guard isCurrent(ticket, target) else { return }

            if loaded.value.outcome == .unrecognised && !messages.isEmpty {
                // The markup moved. The repository already refused to cache it; keep the good
                // rows and tell the truth about them.
                markupWarning = true
            } else {
                apply(loaded, folder: target)
            }
        } catch {
            guard isCurrent(ticket, target) else { return }
            handle(error)
        }

        guard isCurrent(ticket, target) else { return }
        isLoading = false
        await refreshUnreadCount()
    }

    /// Pull-to-refresh.
    func refresh() async {
        await load(forceRefresh: true)
    }

    /// Re-reads the badge value from the cached inbox. Cheap: no request.
    func refreshUnreadCount() async {
        unreadCount = await repository.unreadCount()
    }

    // MARK: - Row state

    /// Flips a row to read the moment it is opened, so the list matches what the student just did
    /// without waiting for a round trip. The authoritative value still comes from W4 on the next
    /// inbox refresh, which `MailMessageViewModel` schedules after a message is fetched.
    func markReadLocally(id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }), messages[index].isUnread else {
            return
        }
        let row = messages[index]
        messages[index] = MailMessage(
            id: row.id,
            folderID: row.folderID,
            subject: row.subject,
            from: row.from,
            receivedAt: row.receivedAt,
            isUnread: false,
            hasAttachment: row.hasAttachment,
            href: row.href
        )
        unreadCount = max(0, unreadCount - 1)
    }

    // MARK: - Plumbing

    private func isCurrent(_ ticket: Int, _ folder: MailFolder) -> Bool {
        ticket == generation && folder.id == selectedFolder.id
    }

    private func apply(_ loaded: W4Loaded<MailListPage>, folder: MailFolder) {
        let page = loaded.value
        messages = page.messages
        outcome = page.outcome
        hasMorePages = page.hasMorePages
        freshness = loaded.freshness
        loadedFolderID = folder.id
        if !page.messages.isEmpty || page.outcome != .unrecognised {
            markupWarning = false
        }
        // Anything we could render is not an error, whatever happened on the way here.
        if !page.messages.isEmpty { errorMessage = nil }
    }

    /// Errors reach the screen only when the screen would otherwise be blank (`features.md` §3).
    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }

        if let w4 = error as? W4Error {
            // Only `.sessionExpired` posts the logout notification. `.forbidden` — a student
            // opening a staff-only page — must never kick anyone back to the login screen.
            w4.notifyIfSessionExpired()
            if messages.isEmpty { errorMessage = w4.errorDescription }
            return
        }

        if messages.isEmpty { errorMessage = error.localizedDescription }
    }
}
