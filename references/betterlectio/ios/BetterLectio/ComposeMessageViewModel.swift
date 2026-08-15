import Foundation
import Combine
import PhotosUI
import SwiftUI

@MainActor
final class ComposeMessageViewModel: ObservableObject {
    @Published var recipients: [MessageRecipient] = []
    @Published var subject = ""
    @Published var messageBody = ""
    @Published var attachments: [OutgoingMessageAttachment] = []
    @Published var isSending = false
    @Published var errorMessage: String?

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared

    var canSend: Bool {
        !recipients.isEmpty &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasDraft: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !attachments.isEmpty
    }

    func addFiles(_ urls: [URL]) async {
        OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        do {
            let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
                guard !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
                result.append(url)
            }
            try ensureCapacity(for: uniqueURLs.count)
            for url in uniqueURLs {
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
                    fallback: "Foto-\(attachments.count + 1).\(suffix)"
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

    func discardAttachments() {
        cleanupAttachments()
    }

    func send(for student: Student) async -> String? {
        guard canSend, !isSending else { return nil }
        isSending = true
        errorMessage = nil
        resetAttachmentStatesForRetry()

        if student.isDemo {
            isSending = false
            cleanupAttachments()
            return "demo-sent-\(UUID().uuidString.prefix(8))"
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                throw LectioError.parsingError("Ingen login-oplysninger fundet")
            }
            let content = MessageSignature.appendIfNeeded(
                to: messageBody,
                recipientIDs: recipients.map(\.id),
                enabled: SettingsStore.shared.messageSignatureEnabled
            )
            let threadID = try await httpClient.sendNewMessage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                recipients: recipients,
                title: subject,
                content: content,
                attachments: attachments,
                attachmentStateChanged: { [weak self] id, state in
                    await self?.setAttachmentState(id: id, state: state)
                }
            )
            isSending = false
            cleanupAttachments()
            ReviewPromptCoordinator.shared.maybePrompt(.messageSent)
            return threadID
        } catch is CancellationError {
            resetAttachmentStatesForRetry()
        } catch let error as URLError where error.code == .cancelled {
            resetAttachmentStatesForRetry()
        } catch let error as OutgoingAttachmentUploadError {
            markCompletedAttachmentsPending()
            ReviewPromptCoordinator.shared.reportRecentError()
            errorMessage = "\(error.localizedDescription) Tryk Send for at prøve igen, eller fjern filen."
        } catch let error as LectioError {
            resetAttachmentStatesForRetry()
            ReviewPromptCoordinator.shared.reportRecentError()
            error.notifyIfSessionExpired()
            errorMessage = error.errorDescription
        } catch {
            resetAttachmentStatesForRetry()
            ReviewPromptCoordinator.shared.reportRecentError()
            errorMessage = error.localizedDescription
        }
        isSending = false
        return nil
    }

    private func setAttachmentState(id: UUID, state: OutgoingAttachmentUploadState) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[index].uploadState = state
    }

    private func appendIfUnique(_ attachment: OutgoingMessageAttachment) {
        guard !attachments.contains(where: { $0.selectionKey == attachment.selectionKey }) else {
            attachment.removeTemporaryFile()
            return
        }
        attachments.append(attachment)
    }

    private func resetAttachmentStatesForRetry() {
        for index in attachments.indices { attachments[index].uploadState = .pending }
    }

    private func markCompletedAttachmentsPending() {
        for index in attachments.indices {
            if case .attached = attachments[index].uploadState {
                attachments[index].uploadState = .pending
            }
        }
    }

    private func ensureCapacity(for count: Int) throws {
        guard attachments.count + count <= OutgoingMessageAttachment.maximumCount else {
            throw OutgoingAttachmentSelectionError.maximumCount
        }
    }

    private func cleanupAttachments() {
        attachments.forEach { $0.removeTemporaryFile() }
        attachments.removeAll()
    }
}
