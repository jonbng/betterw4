//
//  MailRepository.swift
//  BetterW4
//
//  The layer between `W4MailerParser` / `W4MailDetailParser` and the working transport
//  (plan Wave 5 item 5.3, features.md §1.4 and §2.4–2.5).
//
//  Everything a mail screen is allowed to know about fetching lives here:
//
//    1. **Demo never touches the network.** The context is resolved before anything else and a
//       demo session returns hard-coded mail. There is no code path from a demo session to
//       `URLSession`, which is the only way to be sure App Review's account stays offline.
//    2. **Cache first.** A list inside its 5-minute TTL is served from disk without a request;
//       a message body is served from disk *forever*, because W4 cannot change a sent email.
//       `cachedList` / `cachedMessage` exist so a view model can paint the screen before it
//       awaits anything at all.
//    3. **A failed refresh over a warm cache is not an error.** Offline with yesterday's inbox is
//       a working app; the freshness on the returned value says the copy is stale, and the UI
//       says so too.
//    4. **…except a dead session, which must never be swallowed.** `W4Error.sessionExpired`
//       propagates through the cache fallback so `AuthenticationViewModel` can log the student
//       out. `W4Error.forbidden` (403 without "Login Required") is emphatically *not* that: a
//       student opening a staff-only page falls back to cache like any other failure
//       (reviewer-notes §3). Cancellation propagates too — a cancelled task wants to end, not to
//       be handed a consolation prize.
//    5. **An unreadable page is never cached.** `.unrecognised` means W4's markup moved, not that
//       the mailbox is empty; storing it would replace a good inbox with a permanent empty one.
//
//  Storage is split deliberately (see `MessageCacheManager.swift` for the full argument):
//  list HTML → `W4PageCache` (two bounded keys per student), parsed lists and message bodies →
//  `MailFileCache`, attachment files → `AttachmentCache` (LRU).
//
//  NOT here, on purpose: compose and send. `mailer/send&type=freeform` is v1.5 (plan §1.4) and
//  belongs to a later wave; `MailDraft` already models the form fields for it.
//

import Foundation
import OSLog

private let mailRepositoryLog = Logger(subsystem: "dk.jonathanb.w4", category: "MailRepository")

// MARK: - Transport seam

/// The two things the mail repository asks of the network, and nothing else.
///
/// `W4HTTPClient` conforms below. Tests inject a recorder instead — which is why this exists at
/// all: the client's own methods are fine, they just cannot be stubbed without a protocol, and
/// the client itself must not grow test affordances.
protocol MailPageFetching: AnyObject {
    /// `GET index.php?r={route}&…`, decoded to HTML.
    func fetchMailPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (html: String, finalURL: URL)

    /// One attachment, verbatim bytes. The host gate applies: an off-W4 link throws.
    func fetchMailFile(
        url: URL,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> Data
}

extension W4HTTPClient: MailPageFetching {

    func fetchMailPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (html: String, finalURL: URL) {
        let response = try await get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return (decodeHTML(from: response.data), response.finalURL)
    }

    func fetchMailFile(
        url: URL,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> Data {
        let response = try await fetchWithCookies(
            url: url,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "mail attachment",
            priority: priority
        )
        return response.data
    }
}

// MARK: - Repository

actor MailRepository {

    static let shared = MailRepository()

    private let transport: MailPageFetching
    private let store: MailFileCache
    private let pageCache: W4PageCache
    private let attachments: AttachmentCache
    private let resolveContext: @Sendable () throws -> W4RequestContext
    private let now: @Sendable () -> Date

    init(
        transport: MailPageFetching = W4HTTPClient(),
        store: MailFileCache = .shared,
        pageCache: W4PageCache = .shared,
        attachments: AttachmentCache = .shared,
        resolveContext: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() },
        now: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        self.transport = transport
        self.store = store
        self.pageCache = pageCache
        self.attachments = attachments
        self.resolveContext = resolveContext
        self.now = now
    }

    // MARK: - Lists

    /// What is on disk right now, without touching the network. Nil when nothing is cached.
    ///
    /// This is the "paint the screen immediately" call: a view model reads it, publishes it, then
    /// awaits `list(folder:)` for the refresh (features.md §3 rule 2).
    func cachedList(folder: MailFolder) async -> W4Loaded<MailListPage>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(MailDemoData.list(folder: folder), freshness: .demo)
        }
        guard let hit = await cachedEntry(folder: folder, uwcId: context.uwcId) else { return nil }
        return W4Loaded(hit.page, freshness: .cached(fetchedAt: hit.fetchedAt, isStale: hit.isStale))
    }

    /// One page of a mailer grid, cache-first and TTL-bounded.
    ///
    /// - Parameter forceRefresh: skips the TTL check. Pull-to-refresh, and the post-write refresh
    ///   after anything that could change unread state.
    func list(
        folder: MailFolder,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<MailListPage> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(MailDemoData.list(folder: folder), freshness: .demo)
        }

        let surface = Self.surface(for: folder)
        let cached = await cachedEntry(folder: folder, uwcId: context.uwcId)

        if !forceRefresh, let cached, !cached.isStale {
            return W4Loaded(cached.page, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }

        do {
            let response = try await transport.fetchMailPage(
                route: folder.route,
                query: [:],
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            let fetchedAt = now()
            let page = W4MailerParser.parseList(response.html, folder: folder)

            if page.outcome == .unrecognised {
                // The markup moved. Hand back the honest empty-with-a-reason result so the UI can
                // say "we could not read W4's page", but leave the good cached copy alone.
                mailRepositoryLog.warning(
                    "mailer/\(folder.id, privacy: .public): unrecognised markup; cache left untouched"
                )
                return W4Loaded(page, freshness: .fresh)
            }

            await pageCache.store(
                html: response.html,
                surface: surface,
                key: Self.listKey(folder),
                uwcId: context.uwcId,
                finalURL: response.finalURL,
                contentType: "text/html",
                fetchedAt: fetchedAt
            )
            await store.storeList(MailListSnapshot(page: page, fetchedAt: fetchedAt), uwcId: context.uwcId)
            return W4Loaded(page, freshness: .fresh)
        } catch {
            try Self.rethrowIfUnrecoverable(error)
            guard let cached else { throw error }
            mailRepositoryLog.info(
                "mailer/\(folder.id, privacy: .public): refresh failed, serving cached copy"
            )
            return W4Loaded(cached.page, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: cached.isStale))
        }
    }

    func inbox(forceRefresh: Bool = false, priority: FetchPriority = .important) async throws -> W4Loaded<MailListPage> {
        try await list(folder: .inbox, forceRefresh: forceRefresh, priority: priority)
    }

    func archive(forceRefresh: Bool = false, priority: FetchPriority = .important) async throws -> W4Loaded<MailListPage> {
        try await list(folder: .archive, forceRefresh: forceRefresh, priority: priority)
    }

    /// Unread rows in the cached inbox. The value behind the tab badge.
    func unreadCount() async -> Int {
        guard let context = try? resolveContext() else { return 0 }
        if context.isDemo {
            return MailDemoData.list(folder: .inbox).messages.reduce(0) { $0 + ($1.isUnread ? 1 : 0) }
        }
        return await store.unreadInboxCount(uwcId: context.uwcId)
    }

    // MARK: - Message bodies

    /// The cached body, or nil. Never expires — a sent email cannot change.
    func cachedMessage(id: String) async -> W4Loaded<MailMessageDetail>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(MailDemoData.message(id: id), freshness: .demo)
        }
        guard let snapshot = await store.message(id: id, uwcId: context.uwcId) else { return nil }
        return W4Loaded(snapshot.detail, freshness: .cached(fetchedAt: snapshot.fetchedAt, isStale: false))
    }

    /// One read email (`mailer/view&id={id}`).
    ///
    /// A cached body short-circuits unconditionally: `CachePolicy.ttl(for: .mailMessage)` is
    /// `.infinity` and the only things that remove a body are "clear cache" and sign-out.
    func message(
        id: String,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<MailMessageDetail> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(MailDemoData.message(id: id), freshness: .demo)
        }

        let cached = await store.message(id: id, uwcId: context.uwcId)
        if !forceRefresh, let cached {
            return W4Loaded(cached.detail, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }

        do {
            let response = try await transport.fetchMailPage(
                route: W4Routes.R.mailerView,
                query: ["id": id],
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            let fetchedAt = now()
            let detail = W4MailDetailParser.parse(response.html, id: id)

            // An empty body means the detail page did not parse. Same rule as the list: do not let
            // an unreadable page become the permanent, never-expiring cached copy of this email.
            if detail.bodyHTML.isEmpty {
                mailRepositoryLog.warning("mailer/view id=\(id, privacy: .public): empty body; not cached")
                if let cached {
                    return W4Loaded(cached.detail, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
                }
                return W4Loaded(detail, freshness: .fresh)
            }

            await store.storeMessage(MailMessageSnapshot(detail: detail, fetchedAt: fetchedAt), uwcId: context.uwcId)
            return W4Loaded(detail, freshness: .fresh)
        } catch {
            try Self.rethrowIfUnrecoverable(error)
            guard let cached else { throw error }
            return W4Loaded(cached.detail, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }
    }

    // MARK: - Attachments

    /// A local file URL for one attachment, downloading it once and caching it LRU.
    ///
    /// The href is resolved against `https://w4.uwcrcn.no` — W4 emits `/index.php?r=…` — and the
    /// client's host gate rejects anything that resolves off-host rather than sending a session
    /// cookie to a stranger.
    func attachmentFile(
        for attachment: MailAttachment,
        priority: FetchPriority = .important
    ) async throws -> URL {
        let context = try resolveContext()
        if context.isDemo {
            // Written into the same cache a real download lands in, so the preview path is
            // exercised end to end without a request.
            return try await cacheOrStore(
                key: "demo://attachment/\(attachment.id)",
                name: attachment.name
            ) { MailDemoData.attachmentBody }
        }

        let target = W4Routes.resolve(attachment.url)
        return try await cacheOrStore(key: target.absoluteString, name: attachment.name) {
            try await self.transport.fetchMailFile(
                url: target,
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
        }
    }

    private func cacheOrStore(
        key: String,
        name: String,
        produce: () async throws -> Data
    ) async throws -> URL {
        if let cached = await attachments.file(for: key, name: name) { return cached }
        let data = try await produce()
        guard let url = await attachments.store(data, for: key, name: name) else {
            throw W4Error.parsingError("Could not save \(name)")
        }
        return url
    }

    // MARK: - Clearing

    /// Everything mail-shaped for the signed-in student: parsed lists, bodies, the two cached list
    /// pages, and every downloaded attachment.
    func clearCache() async {
        guard let context = try? resolveContext() else { return }
        for folder in MailFolder.all {
            await pageCache.remove(
                surface: Self.surface(for: folder),
                key: Self.listKey(folder),
                uwcId: context.uwcId
            )
        }
        await store.clear(uwcId: context.uwcId)
        await attachments.clear()
    }

    // MARK: - Cache plumbing

    private struct CachedList {
        let page: MailListPage
        let fetchedAt: Date
        let isStale: Bool
    }

    /// The parsed snapshot when there is one, else the cached HTML re-parsed. The second rung
    /// matters after a JSON write failure and after a schema change: the page cache still holds a
    /// perfectly good grid, and re-parsing it beats showing an empty mailbox.
    private func cachedEntry(folder: MailFolder, uwcId: String) async -> CachedList? {
        let surface = Self.surface(for: folder)

        if let snapshot = await store.list(folderID: folder.id, uwcId: uwcId) {
            return CachedList(
                page: snapshot.page(folder: folder),
                fetchedAt: snapshot.fetchedAt,
                isStale: !CachePolicy.isFresh(snapshot.fetchedAt, for: surface, now: now())
            )
        }

        guard let cachedPage = await pageCache.page(
            surface: surface,
            key: Self.listKey(folder),
            uwcId: uwcId
        ) else { return nil }

        let page = W4MailerParser.parseList(cachedPage.html, folder: folder)
        guard page.outcome != .unrecognised else { return nil }
        return CachedList(
            page: page,
            fetchedAt: cachedPage.fetchedAt,
            isStale: !CachePolicy.isFresh(cachedPage.fetchedAt, for: surface, now: now())
        )
    }

    /// Errors that must reach the caller even when a usable cached copy exists.
    ///
    /// `.sessionExpired` is the app's only logout signal — swallowing it strands the student on a
    /// screen full of yesterday's mail that will never refresh. Cancellation is honoured because a
    /// cancelled task has no caller left to serve. Everything else — `.forbidden`, HTTP 500,
    /// offline — falls through to the cached copy.
    private static func rethrowIfUnrecoverable(_ error: Error) throws {
        if let w4 = error as? W4Error, case .sessionExpired = w4 { throw w4 }
        if error is CancellationError { throw error }
        if let urlError = error as? URLError, urlError.code == .cancelled { throw urlError }
    }

    static func surface(for folder: MailFolder) -> W4Surface {
        folder.id == MailFolder.archive.id ? .mailArchive : .mailInbox
    }

    /// The page-cache key. The folder id alone: one grid per folder per student, overwritten on
    /// every refresh, so the page cache never grows a mail tail.
    static func listKey(_ folder: MailFolder) -> String { folder.id }
}

// MARK: - Demo mail

/// Offline mail for the App Review account. `DemoDataProvider` still models Lectio threads and is
/// owned by another item, so W4's two grids are shaped here instead.
enum MailDemoData {

    static func list(folder: MailFolder) -> MailListPage {
        let messages = folder.id == MailFolder.archive.id ? archiveMessages() : inboxMessages()
        return MailListPage(
            folder: folder,
            messages: messages,
            pagination: nil,
            outcome: .parsed,
            columns: folder.id == MailFolder.archive.id
                ? MailColumnLayout(headers: ["send date", "subject", "attachment"], received: 0, subject: 1, attachment: 2)
                : MailColumnLayout(headers: ["received", "from", "subject"], received: 0, from: 1, subject: 2)
        )
    }

    static func message(id: String) -> MailMessageDetail {
        let known = (inboxMessages() + archiveMessages()).first { $0.id == id }
        return MailMessageDetail(
            id: id,
            subject: known?.subject ?? "Demo message",
            from: known?.from ?? "Demo Student",
            recipients: ["Demo Student"],
            sentAt: known?.receivedAt ?? TimeProvider.now,
            bodyHTML: """
            <p>Hi Demo Student,</p>
            <p>This is offline demo mail. Nothing on this screen came from a server, and the demo \
            account never makes a request.</p>
            <p>— UWC Red Cross Nordic</p>
            """,
            attachments: id == "demo-mail-1" ? [demoAttachment] : []
        )
    }

    static let demoAttachment = MailAttachment(
        id: "demo-attachment-1",
        name: "demo-note.txt",
        url: "demo://attachment/1"
    )

    /// Contents of the one demo attachment. Deliberately plain text with a `.txt` name so the
    /// preview shows something real rather than a corrupt PDF.
    static let attachmentBody = Data(
        "This is a demo attachment. The demo account never downloads anything.\n".utf8
    )

    private static func inboxMessages() -> [MailMessage] {
        let now = TimeProvider.now
        return [
            MailMessage(
                id: "demo-mail-1",
                folderID: MailFolder.inbox.id,
                subject: "Welcome to term 1",
                from: "House Leader",
                receivedAt: now.addingTimeInterval(-60 * 45),
                isUnread: true,
                hasAttachment: true,
                href: nil
            ),
            MailMessage(
                id: "demo-mail-2",
                folderID: MailFolder.inbox.id,
                subject: "Kayaking trip — kit list",
                from: "Outdoor Department",
                receivedAt: now.addingTimeInterval(-60 * 60 * 6),
                isUnread: false,
                hasAttachment: false,
                href: nil
            ),
            MailMessage(
                id: "demo-mail-3",
                folderID: MailFolder.inbox.id,
                subject: "Library books due Friday",
                from: "Library",
                receivedAt: now.addingTimeInterval(-60 * 60 * 30),
                isUnread: false,
                hasAttachment: false,
                href: nil
            )
        ]
    }

    private static func archiveMessages() -> [MailMessage] {
        let now = TimeProvider.now
        return [
            MailMessage(
                id: "demo-mail-sent-1",
                folderID: MailFolder.archive.id,
                subject: "Re: Welcome to term 1",
                from: nil,
                receivedAt: now.addingTimeInterval(-60 * 60 * 20),
                isUnread: false,
                hasAttachment: false,
                href: nil
            ),
            MailMessage(
                id: "demo-mail-sent-2",
                folderID: MailFolder.archive.id,
                subject: "Question about the CAS deadline",
                from: nil,
                receivedAt: now.addingTimeInterval(-60 * 60 * 72),
                isUnread: false,
                hasAttachment: false,
                href: nil
            )
        ]
    }
}
