//
//  ComposeMessageViewModel.swift
//  BetterW4
//
//  Draft state for a new W4 mail (plan Wave 6 item 6.2, `docs/spec/ui.md` §4.4).
//
//  ── WHY THIS CANNOT SEND YET, AND WHY THAT IS THE HONEST ANSWER ──────────────────────────────
//
//  W4's compose endpoint is `POST index.php?r=mailer/send&type=freeform`, multipart, with fields
//  `MailerForm[subject]`, `MailerForm[message]` (TinyMCE HTML), `MailerForm[attachment][]`
//  (≤ 5 × 2 MB), `MailerForm[sendCC]` and `MailerForm[attachmentSource]=upload`. Those names come
//  from README §5.2 — **prose, not a capture**. No `mailer/*` page has ever been captured at all
//  (plan OQ-4, capture wishlist item 3), so nobody has seen the real form, its hidden fields, its
//  recipient token format (`mailer/extra&type=freeform`) or its success response.
//
//  `MailRepository` therefore exposes no send, deliberately (see its header). Inventing a
//  transport here would mean POSTing guessed field names at a live school server on behalf of a
//  student and then telling them "sent" when W4 may have silently dropped it. The assessments
//  vertical hit the same wall and answered it with `AssessmentFeatureFlags.writesEnabled`; mail
//  answers it the same way, with `MailFeatureFlags.composeEnabled`.
//
//  So: the draft is real, the attachment staging is real and enforces W4's limits, and pressing
//  Send produces a clear, honest "not enabled yet" — never a fake success. When capture C-4 lands,
//  flip the flag, add `send(_:)` to `MailRepository`, and `send(for:)` below becomes a call to it.
//

import Combine
import Foundation
import PhotosUI
import SwiftUI

// MARK: - Feature gate

/// Mail features whose wire format is not verified yet.
///
/// Same shape and same reasoning as `AssessmentFeatureFlags` (AssessmentModels.swift): the plan
/// calls for one shared `W4Feature` namespace eventually, but no wave owns that type, so each
/// vertical keeps its own flag and they fold together later without changing meaning.
enum MailFeatureFlags {
    /// Flip to `true` only when a real `mailer/send&type=freeform` round trip has been captured
    /// **and** `MailRepository` has a send path to call.
    static let composeEnabled = false
}

// MARK: - View model

@MainActor
final class ComposeMessageViewModel: ObservableObject {

    // MARK: Draft

    @Published var subject = ""
    /// Plain text as typed. It becomes `MailerForm[message]` HTML at send time — W4's field is a
    /// TinyMCE editor, so the wire value is HTML even though the student types prose.
    @Published var messageBody = ""
    @Published var sendCopyToMe = false
    @Published private(set) var recipients: [MailRecipient] = []
    @Published private(set) var attachments: [OutgoingMessageAttachment] = []

    // MARK: Feedback

    /// Attachment-picking problems: too big, too many, unreadable.
    @Published var errorMessage: String?
    /// Why the last Send attempt did not go anywhere. Never cleared by a fake success.
    @Published private(set) var sendFailure: String?

    // MARK: - State

    var isComposeEnabled: Bool { MailFeatureFlags.composeEnabled }

    var canSend: Bool {
        isComposeEnabled
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasDraft: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    var canAttachMore: Bool {
        attachments.count < OutgoingMessageAttachment.maximumCount
    }

    /// The `mailer/send` body this draft would produce, minus the multipart file parts.
    /// Nothing posts it yet; it exists so the shape is written down in one place and is ready the
    /// day the flag flips.
    var draft: MailDraft {
        MailDraft(
            subject: subject,
            bodyHTML: Self.html(fromPlainText: messageBody),
            recipients: recipients,
            attachments: attachments,
            sendCopyToMe: sendCopyToMe
        )
    }

    // MARK: - Recipients

    /// Seeds the recipient chips, e.g. when compose is opened from someone's profile.
    /// Only ever called with tokens W4 itself handed out — never with an invented id.
    func setInitialRecipients(_ initial: [MailRecipient]) {
        guard recipients.isEmpty, !initial.isEmpty else { return }
        recipients = initial
    }

    func removeRecipient(id: String) {
        recipients.removeAll { $0.id == id }
    }

    // MARK: - Attachments

    func addFiles(_ urls: [URL]) async {
        OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        do {
            let unique = urls.reduce(into: [URL]()) { result, url in
                guard !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
                result.append(url)
            }
            try ensureCapacity(for: unique.count)
            for url in unique {
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try OutgoingMessageAttachment.copyFromFileImporter(url)
                }.value
                appendIfUnique(attachment)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhotos(_ items: [PhotosPickerItem]) async {
        OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        do {
            try ensureCapacity(for: items.count)
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw OutgoingAttachmentSelectionError.unreadablePhoto
                }
                let type = item.supportedContentTypes.first
                let assetIdentifier = item.itemIdentifier
                let suffix = type?.preferredFilenameExtension ?? "jpg"
                let fileName = OutgoingMessageAttachment.originalPhotoFileName(
                    assetIdentifier: assetIdentifier,
                    fallback: "Photo-\(attachments.count + 1).\(suffix)"
                )
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try OutgoingMessageAttachment.createFromPhotoData(
                        data,
                        fileName: fileName,
                        type: type,
                        assetIdentifier: assetIdentifier
                    )
                }.value
                appendIfUnique(attachment)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAttachment(id: UUID) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[index].removeTemporaryFile()
        attachments.remove(at: index)
    }

    /// Deletes every staged file. Called when the sheet is discarded, so nothing is left in `tmp/`.
    func discardDraft() {
        attachments.forEach { $0.removeTemporaryFile() }
        attachments.removeAll()
    }

    // MARK: - Sending

    /// Returns `true` only when a message really reached W4.
    ///
    /// While `MailFeatureFlags.composeEnabled` is off there is no transport to call and this
    /// always returns `false` with a message that says exactly why. It never dismisses the sheet
    /// and it never discards the draft: whatever the student typed is still there afterwards.
    @discardableResult
    func send(for student: Student) async -> Bool {
        sendFailure = nil

        guard isComposeEnabled else {
            sendFailure = Self.notEnabledMessage
            return false
        }

        // Unreachable while the flag is off. When it flips, this is the single line that changes:
        // `try await MailRepository.shared.send(draft, for: student)`.
        sendFailure = Self.notEnabledMessage
        return false
    }

    static let notEnabledMessage = """
        Sending mail from the app is not enabled yet. W4's send form has not been verified, and \
        BetterW4 will not tell you a message was delivered when it cannot check. Open W4 in Safari \
        to send this one.
        """

    // MARK: - Private

    private func ensureCapacity(for count: Int) throws {
        guard attachments.count + count <= OutgoingMessageAttachment.maximumCount else {
            throw OutgoingAttachmentSelectionError.maximumCount
        }
    }

    private func appendIfUnique(_ attachment: OutgoingMessageAttachment) {
        guard !attachments.contains(where: { $0.selectionKey == attachment.selectionKey }) else {
            attachment.removeTemporaryFile()
            return
        }
        attachments.append(attachment)
    }

    /// Wraps typed prose in the paragraphs W4's TinyMCE field expects, escaping first so a `<`
    /// in someone's message cannot become markup.
    static func html(fromPlainText text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let paragraphs = escaped
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: "<br>") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !paragraphs.isEmpty else { return "" }
        return paragraphs.map { "<p>\($0)</p>" }.joined()
    }
}
