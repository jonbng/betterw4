//
//  MailMessageViewModel.swift
//  BetterW4
//
//  One read email (plan Wave 6 item 6.2, `docs/spec/ui.md` §4.3). Replaces Lectio's
//  `MessageThreadViewModel`, which modelled a *thread* with replies, reactions and edit audit —
//  none of which exist on W4's `mailer/view&id={n}` page (plan §1.4 kill list).
//
//  The same four behaviours as the list (`features.md` §3), with one simplification that comes
//  straight from the domain: **a sent email cannot change**, so `CachePolicy.ttl(for: .mailMessage)`
//  is infinite and a cached body is served without a request, forever. `forceRefresh` exists only
//  for the pull-to-refresh gesture.
//
//  Attachments are downloaded through `MailRepository.attachmentFile(for:)`, which resolves the
//  href against `https://w4.uwcrcn.no`, refuses anything that lands off-host, and parks the bytes
//  in the shared LRU `AttachmentCache`. The local URL handed back belongs to that cache: it is
//  previewed, never moved and never deleted here.
//

import Combine
import Foundation

/// Where one attachment is in its download.
enum MailAttachmentDownloadState: Equatable, Sendable {
    case idle
    case downloading
    case failed(String)
}

/// A downloaded attachment ready for QuickLook. `id` is the attachment id so re-tapping the same
/// row re-presents the same sheet rather than stacking new ones.
struct MailAttachmentPreview: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
}

@MainActor
final class MailMessageViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var detail: MailMessageDetail?
    /// The body, already rendered to drawable blocks. W4 mail bodies are TinyMCE **HTML** — never
    /// markdown, never BBCode — and go through the one shared renderer.
    @Published private(set) var blocks: [ContentBlock] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var freshness: W4Freshness?

    @Published private(set) var attachmentStates: [String: MailAttachmentDownloadState] = [:]
    @Published var preview: MailAttachmentPreview?

    // MARK: - Dependencies

    private let repository: MailRepository
    /// Warms the inbox after a message is read, so the tab badge catches up. Injected so a test
    /// never reaches the shared repository — and through it the Keychain and the network — as a
    /// side effect of opening a message.
    private let scheduleInboxRefresh: (Student) -> Void
    private var generation = 0
    private var loadedMessageID: String?

    init(
        repository: MailRepository = .shared,
        scheduleInboxRefresh: @escaping (Student) -> Void = { MessageListPrefetcher.refreshUnreadFolder(for: $0) }
    ) {
        self.repository = repository
        self.scheduleInboxRefresh = scheduleInboxRefresh
    }

    // MARK: - Derived

    /// True when W4 answered but the page held no readable body. Distinct from "the message is
    /// empty" — we do not know that, and saying so would be an invention.
    var hasEmptyBody: Bool {
        guard let detail else { return false }
        return blocks.isEmpty && detail.bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var attachments: [MailAttachment] { detail?.attachments ?? [] }

    func state(for attachment: MailAttachment) -> MailAttachmentDownloadState {
        attachmentStates[attachment.id] ?? .idle
    }

    // MARK: - Loading

    /// Cache-first load of one message body.
    ///
    /// - Parameters:
    ///   - message: the list row that was tapped. Its subject / sender / date paint the header
    ///     immediately, so the screen is never blank while the body is fetched.
    ///   - student: used only to warm the inbox afterwards, so the unread badge catches up with
    ///     the fact that this message has now been read.
    func load(message: MailMessage, student: Student, forceRefresh: Bool = false) async {
        generation += 1
        let ticket = generation
        let id = message.id

        errorMessage = nil

        if loadedMessageID != id {
            detail = nil
            blocks = []
            freshness = nil
            attachmentStates = [:]
        }

        // 1. Whatever is on disk, before anything is awaited over the network.
        if let cached = await repository.cachedMessage(id: id) {
            guard ticket == generation else { return }
            apply(cached, id: id)
        }

        // 2. Spinner only when there is nothing to show.
        isLoading = (detail == nil)

        // 3. Fetch.
        do {
            let loaded = try await repository.message(id: id, forceRefresh: forceRefresh)
            guard ticket == generation else { return }
            apply(loaded, id: id)

            // A body that came off the wire means W4 has just seen this message opened; refresh
            // the inbox so the badge and the unread flag catch up. `.opportunistic` and
            // coalesced — it never competes with the screen the student is looking at.
            if case .fresh = loaded.freshness {
                scheduleInboxRefresh(student)
            }
        } catch {
            guard ticket == generation else { return }
            handle(error)
        }

        guard ticket == generation else { return }
        isLoading = false
    }

    func refresh(message: MailMessage, student: Student) async {
        await load(message: message, student: student, forceRefresh: true)
    }

    // MARK: - Attachments

    /// Downloads one attachment (or reuses the cached file) and presents it.
    func openAttachment(_ attachment: MailAttachment) async {
        guard state(for: attachment) != .downloading else { return }
        attachmentStates[attachment.id] = .downloading
        do {
            let url = try await repository.attachmentFile(for: attachment)
            attachmentStates[attachment.id] = .idle
            preview = MailAttachmentPreview(id: attachment.id, name: attachment.name, url: url)
        } catch {
            if error is CancellationError {
                attachmentStates[attachment.id] = .idle
                return
            }
            if let w4 = error as? W4Error {
                w4.notifyIfSessionExpired()
                attachmentStates[attachment.id] = .failed(w4.errorDescription ?? "Could not open the file")
            } else {
                attachmentStates[attachment.id] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Plumbing

    private func apply(_ loaded: W4Loaded<MailMessageDetail>, id: String) {
        detail = loaded.value
        freshness = loaded.freshness
        loadedMessageID = id
        blocks = W4MailDetailParser.blocks(of: loaded.value, baseURL: W4Routes.originURL)
        errorMessage = nil
    }

    /// Same rule as the list: an error reaches the screen only when the screen would otherwise be
    /// blank. `.sessionExpired` is the one error that logs the student out; `.forbidden` is not.
    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }

        if let w4 = error as? W4Error {
            w4.notifyIfSessionExpired()
            if detail == nil { errorMessage = w4.errorDescription }
            return
        }

        if detail == nil { errorMessage = error.localizedDescription }
    }
}
