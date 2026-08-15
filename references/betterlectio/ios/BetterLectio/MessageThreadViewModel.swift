//
//  MessageThreadViewModel.swift
//  BetterLectio
//

import Combine
import Foundation
import ImageIO
import PhotosUI
import SwiftSoup
import SwiftUI

@MainActor
class MessageThreadViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var threadDetail: MessageThreadDetail?
    @Published var avatarURLs: [String: URL?] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var replyErrorMessage: String?
    @Published var isSendingReply = false
    @Published var replyText = ""
    @Published var replyTitle = ""
    @Published var replyAttachments: [OutgoingMessageAttachment] = []
    @Published var sendSuccess = false
    @Published var isAtScrollBottom = false
    @Published var formattedMessages: [String: AttributedString] = [:]
    @Published var reactionPendingTarget: MessageLocator?
    @Published var reactionErrorMessage: String?
    @Published var reactionSuccessToken = 0
    @Published var editDraft: MessageEditDraft?
    @Published var editTitle = ""
    @Published var editBody = ""
    @Published var isLoadingEdit = false
    @Published var isSavingEdit = false
    @Published var editErrorMessage: String?

    // MARK: - Services

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared

    private var currentStudent: Student?
    private var currentCredentials: LectioCredentials?

    private var processingTask: Task<Void, Never>?
    private var avatarTask: Task<Void, Never>?
    private var activeLoadID: UUID?

    func cancelActiveTasks() {
        activeLoadID = nil
        processingTask?.cancel()
        avatarTask?.cancel()
    }

    func discardReplyAttachments() {
        guard !isSendingReply else { return }
        cleanupReplyAttachments()
    }

    // MARK: - Load Thread Detail

    /// Folder the thread was opened from. Needed so the fetch POSTs the correct
    /// `ListGridSelectionTree$folders` value — otherwise Lectio returns the
    /// list page of its last-active folder instead of the requested thread.
    private var currentFolder: MessageFolder = .newest

    func loadThreadDetail(threadId: String, folder: MessageFolder = .newest, for student: Student) async {
        let loadID = UUID()
        activeLoadID = loadID
        errorMessage = nil
        currentFolder = folder

        if student.isDemo {
            loadDemoThreadDetail(threadId: threadId)
            return
        }

        // 1. Load from cache immediately
        let cachedDetail = await MessageCacheManager.loadThreadDetail(
            threadId: threadId,
            studentId: student.studentId,
            gymId: student.gymId
        )
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        if let cached = cachedDetail {
            threadDetail = cached
            preProcessMessages(cached)
            resolveAvatarURLs(for: cached.messages, gymId: student.gymId, studentId: student.studentId)
            // Pre-populate reply title from cache
            if !cached.title.hasPrefix("Re: ") {
                replyTitle = "Re: \(cached.title)"
            } else {
                replyTitle = cached.title
            }
        } else {
            threadDetail = nil
        }

        // 2. Only show loading spinner if we have nothing cached
        if threadDetail == nil {
            isLoading = true
        }

        // 3. Fetch fresh data from network
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                errorMessage = "Ingen loginoplysninger fundet"
                isLoading = false
                return
            }

            currentStudent = student
            currentCredentials = credentials

            let html = try await httpClient.fetchMessageThread(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: threadId,
                folder: folder
            )
            try Task.checkCancellation()

            let detail = try await Task.detached(priority: .userInitiated) {
                try MessageParser.parseMessageThreadDetail(from: html, threadId: threadId)
            }.value
            guard activeLoadID == loadID else { return }
            threadDetail = detail
            preProcessMessages(detail)
            resolveAvatarURLs(for: detail.messages, gymId: student.gymId, studentId: student.studentId)

            // 4. Save to cache
            await MessageCacheManager.saveThreadDetail(detail, studentId: student.studentId, gymId: student.gymId)

            // Pre-populate reply title
            if !detail.title.hasPrefix("Re: ") {
                replyTitle = "Re: \(detail.title)"
            } else {
                replyTitle = detail.title
            }

            // Opening a thread marks it read server-side — refresh the Ulæst cache
            // so the tab badge matches reality.
            MessageListPrefetcher.refreshUnreadFolder(for: student)

            print("💬 Loaded thread with \(detail.messages.count) messages")

        } catch let error as LectioError {
            guard activeLoadID == loadID else { return }
            error.notifyIfSessionExpired()
            // Only show error if we have no cached data to display
            if threadDetail == nil {
                errorMessage = error.errorDescription
            }
        } catch {
            guard activeLoadID == loadID, !(error is CancellationError) else { return }
            if threadDetail == nil {
                errorMessage = error.localizedDescription
            }
        }

        if activeLoadID == loadID {
            isLoading = false
        }
    }

    // MARK: - Send Reply

    func addReplyFiles(_ urls: [URL]) async {
        OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        do {
            let uniqueURLs = urls.reduce(into: [URL]()) { result, url in
                guard !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
                result.append(url)
            }
            try ensureReplyAttachmentCapacity(for: uniqueURLs.count)
            for url in uniqueURLs {
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try OutgoingMessageAttachment.copyFromFileImporter(url)
                }.value
                appendReplyAttachmentIfUnique(attachment)
            }
        } catch {
            replyErrorMessage = error.localizedDescription
        }
    }

    func addReplyPhotos(_ items: [PhotosPickerItem]) async {
        OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        do {
            try ensureReplyAttachmentCapacity(for: items.count)
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw OutgoingAttachmentSelectionError.unreadablePhoto
                }
                let type = item.supportedContentTypes.first
                let assetIdentifier = item.itemIdentifier
                let suffix = type?.preferredFilenameExtension ?? "jpg"
                let fileName = OutgoingMessageAttachment.originalPhotoFileName(
                    assetIdentifier: assetIdentifier,
                    fallback: "Foto-\(replyAttachments.count + 1).\(suffix)"
                )
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try OutgoingMessageAttachment.createFromPhotoData(
                        data,
                        fileName: fileName,
                        type: type,
                        assetIdentifier: assetIdentifier
                    )
                }.value
                appendReplyAttachmentIfUnique(attachment)
            }
        } catch {
            replyErrorMessage = error.localizedDescription
        }
    }

    func removeReplyAttachment(id: UUID) {
        guard let index = replyAttachments.firstIndex(where: { $0.id == id }) else { return }
        replyAttachments[index].removeTemporaryFile()
        replyAttachments.remove(at: index)
    }

    func sendReply(to threadId: String, for student: Student) async -> Bool {
        guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            replyErrorMessage = "Besked kan ikke være tom"
            return false
        }

        isSendingReply = true
        replyErrorMessage = nil
        resetReplyAttachmentStatesForRetry()

        if student.isDemo {
            let reply = DemoDataProvider.synthesizedReply(
                for: threadId,
                replyTitle: replyTitle,
                replyText: replyText
            )
            if let current = threadDetail {
                threadDetail = MessageThreadDetail(
                    threadId: current.threadId,
                    title: current.title,
                    recipients: current.recipients,
                    recipientIDs: current.recipientIDs,
                    messages: current.messages + [reply],
                    canReply: current.canReply
                )
                preProcessMessages(threadDetail!)
            }
            replyText = ""
            cleanupReplyAttachments()
            isSendingReply = false
            sendSuccess = true
            return true
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                replyErrorMessage = "Ingen loginoplysninger fundet"
                isSendingReply = false
                return false
            }

            let content = MessageSignature.appendToReplyIfNeeded(
                to: replyText,
                participantIDs: threadDetail?.recipientIDs ?? [],
                enabled: SettingsStore.shared.messageSignatureEnabled
            )

            try await httpClient.sendMessageReply(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: threadId,
                folder: currentFolder,
                title: replyTitle,
                content: content,
                attachments: replyAttachments,
                attachmentStateChanged: { [weak self] id, state in
                    await self?.setReplyAttachmentState(id: id, state: state)
                }
            )

            // Clear reply and temporarily drop loader flag if needed early
            replyText = ""
            cleanupReplyAttachments()
            isSendingReply = false

            // Reload to show the new message
            await loadThreadDetail(threadId: threadId, folder: currentFolder, for: student)

            // Trigger view update and scroll *after* new data is loaded
            sendSuccess = true
            ReviewPromptCoordinator.shared.maybePrompt(.messageSent)

            return true

        } catch is CancellationError {
            resetReplyAttachmentStatesForRetry()
            isSendingReply = false
            return false
        } catch let error as URLError where error.code == .cancelled {
            resetReplyAttachmentStatesForRetry()
            isSendingReply = false
            return false
        } catch let error as OutgoingAttachmentUploadError {
            markCompletedReplyAttachmentsPending()
            ReviewPromptCoordinator.shared.reportRecentError()
            replyErrorMessage = "\(error.localizedDescription) Tryk Send for at prøve igen, eller fjern filen."
            isSendingReply = false
            return false
        } catch let error as LectioError {
            resetReplyAttachmentStatesForRetry()
            ReviewPromptCoordinator.shared.reportRecentError()
            error.notifyIfSessionExpired()
            replyErrorMessage = error.errorDescription
            isSendingReply = false
            return false
        } catch {
            resetReplyAttachmentStatesForRetry()
            ReviewPromptCoordinator.shared.reportRecentError()
            replyErrorMessage = error.localizedDescription
            isSendingReply = false
            return false
        }
    }

    func react(to message: Message, with selectedEmoji: MessageReactionEmoji, for student: Student) async {
        guard let target = message.locator,
              reactionPendingTarget == nil,
              !isSendingReply,
              let current = threadDetail else { return }
        let nextEmoji = message.ownReaction == selectedEmoji ? nil : selectedEmoji
        let snapshot = current
        reactionPendingTarget = target
        reactionErrorMessage = nil
        threadDetail = current.withMessages(
            current.messages.map { item in
                item.id == message.id ? optimisticReaction(item, emoji: nextEmoji) : item
            }
        )

        if student.isDemo {
            reactionPendingTarget = nil
            reactionSuccessToken += 1
            return
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                throw LectioError.parsingError("Ingen loginoplysninger fundet")
            }
            let showSignature = MessageSignature.shouldShowSignature(
                participantIDs: current.recipientIDs,
                enabled: SettingsStore.shared.messageSignatureEnabled
            )
            let confirmed = try await httpClient.setMessageReaction(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: current.threadId,
                folder: currentFolder,
                target: target,
                emoji: nextEmoji,
                showSignature: showSignature
            )
            threadDetail = confirmed
            preProcessMessages(confirmed)
            await MessageCacheManager.saveThreadDetail(
                confirmed,
                studentId: student.studentId,
                gymId: student.gymId
            )
            reactionPendingTarget = nil
            reactionSuccessToken += 1
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            threadDetail = snapshot
            preProcessMessages(snapshot)
            reactionPendingTarget = nil
            reactionErrorMessage = error.errorDescription ?? "Kunne ikke bekræfte reaktionen"
        } catch {
            threadDetail = snapshot
            preProcessMessages(snapshot)
            reactionPendingTarget = nil
            reactionErrorMessage = error.localizedDescription
        }
    }

    func beginEdit(_ message: Message, for student: Student) async {
        guard let locator = message.locator, !message.editPostbackTarget.isEmpty,
              !isLoadingEdit, !isSendingReply else { return }
        isLoadingEdit = true
        editErrorMessage = nil
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId),
                  let detail = threadDetail else {
                throw LectioError.parsingError("Ingen loginoplysninger fundet")
            }
            let draft = try await httpClient.beginMessageEdit(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: detail.threadId,
                folder: currentFolder,
                locator: locator
            )
            editDraft = draft
            editTitle = draft.title
            editBody = draft.body
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            editErrorMessage = error.errorDescription
        } catch {
            editErrorMessage = error.localizedDescription
        }
        isLoadingEdit = false
    }

    func cancelEdit() {
        guard !isSavingEdit else { return }
        editDraft = nil
        editTitle = ""
        editBody = ""
        editErrorMessage = nil
    }

    func saveEdit(for student: Student) async {
        guard let draft = editDraft, let detail = threadDetail, !isSavingEdit else { return }
        isSavingEdit = true
        editErrorMessage = nil
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                throw LectioError.parsingError("Ingen loginoplysninger fundet")
            }
            let confirmed = try await httpClient.saveMessageEdit(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: detail.threadId,
                draft: draft,
                title: editTitle,
                body: editBody
            )
            threadDetail = confirmed
            preProcessMessages(confirmed)
            await MessageCacheManager.saveThreadDetail(confirmed, studentId: student.studentId, gymId: student.gymId)
            isSavingEdit = false
            cancelEdit()
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            editErrorMessage = error.errorDescription
        } catch {
            editErrorMessage = error.localizedDescription
        }
        isSavingEdit = false
    }

    private func optimisticReaction(_ message: Message, emoji: MessageReactionEmoji?) -> Message {
        var groups = Dictionary(uniqueKeysWithValues: message.reactions.compactMap { group -> (MessageReactionEmoji, MessageReactionGroup)? in
            let reactors = group.reactors.filter { !$0.isOwn }
            guard !reactors.isEmpty else { return nil }
            return (group.emoji, MessageReactionGroup(emoji: group.emoji, reactors: reactors))
        })
        if let emoji {
            let existing = groups[emoji]?.reactors ?? []
            groups[emoji] = MessageReactionGroup(
                emoji: emoji,
                reactors: existing + [MessageReactionParticipant(key: "pending-own", name: "", isOwn: true)]
            )
        }
        return message.with(
            locator: message.locator,
            reactions: MessageReactionEmoji.allCases.compactMap { groups[$0] },
            ownReaction: emoji
        )
    }

    private func setReplyAttachmentState(id: UUID, state: OutgoingAttachmentUploadState) {
        guard let index = replyAttachments.firstIndex(where: { $0.id == id }) else { return }
        replyAttachments[index].uploadState = state
    }

    private func appendReplyAttachmentIfUnique(_ attachment: OutgoingMessageAttachment) {
        guard !replyAttachments.contains(where: { $0.selectionKey == attachment.selectionKey }) else {
            attachment.removeTemporaryFile()
            return
        }
        replyAttachments.append(attachment)
    }

    private func resetReplyAttachmentStatesForRetry() {
        for index in replyAttachments.indices { replyAttachments[index].uploadState = .pending }
    }

    private func markCompletedReplyAttachmentsPending() {
        for index in replyAttachments.indices {
            if case .attached = replyAttachments[index].uploadState {
                replyAttachments[index].uploadState = .pending
            }
        }
    }

    private func ensureReplyAttachmentCapacity(for count: Int) throws {
        guard replyAttachments.count + count <= OutgoingMessageAttachment.maximumCount else {
            throw OutgoingAttachmentSelectionError.maximumCount
        }
    }

    private func cleanupReplyAttachments() {
        replyAttachments.forEach { $0.removeTemporaryFile() }
        replyAttachments.removeAll()
    }

    // MARK: - Demo Mode

    private func loadDemoThreadDetail(threadId: String) {
        let candidates = DemoDataProvider.defaultFolders
            .flatMap { DemoDataProvider.messageThreads(for: $0) }
        guard let thread = candidates.first(where: { $0.id == threadId }) else {
            errorMessage = "Tråd ikke fundet"
            isLoading = false
            return
        }
        let detail = DemoDataProvider.messageThreadDetail(for: thread)
        threadDetail = detail
        isLoading = false
        errorMessage = nil
        avatarURLs = [:]
        replyTitle = detail.title.hasPrefix("Re: ") ? detail.title : "Re: \(detail.title)"
        preProcessMessages(detail)
    }

    // MARK: - Pre-processing

    private func preProcessMessages(_ detail: MessageThreadDetail) {
        let messages = detail.messages
        processingTask?.cancel()
        processingTask = Task.detached(priority: .utility) {
            await withTaskGroup(of: (String, AttributedString).self) { group in
                for message in messages {
                    let id = message.id
                    let content = message.content
                    group.addTask {
                        let formatted = MessageContentRenderer.render(content)
                        return (id, formatted)
                    }
                }
                var cache: [String: AttributedString] = [:]
                for await (id, text) in group {
                    cache[id] = text
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.formattedMessages = cache
                }
            }
        }
    }

    // MARK: - Avatar Resolution

    func refreshAvatarProfiles(gymId: Int, studentId: String) {
        guard let messages = threadDetail?.messages else { return }
        avatarURLs.removeAll()
        resolveAvatarURLs(for: messages, gymId: gymId, studentId: studentId, forceRefresh: true)
    }

    private func resolveAvatarURLs(
        for messages: [Message],
        gymId: Int,
        studentId: String,
        forceRefresh: Bool = false
    ) {
        let names = messages.map { $0.senderName }
        avatarTask?.cancel()
        avatarTask = Task {
            guard !Task.isCancelled else { return }
            let directory = DirectoryStore.shared
            let lookup = await directory.batchAvatarLookup(forNames: names, gymId: gymId)
            guard !Task.isCancelled else { return }
            var studentEntities: [String: DirectoryEntity] = [:]
            for name in names {
                if let entity = directory.resolvePersonByName(name, gymId: gymId), entity.kind == .student {
                    studentEntities[name] = entity
                }
            }
            let profiles = await SupabaseStudentProfileService.shared.profiles(
                studentIDs: studentEntities.values.map(\.numericID),
                viewerStudentID: studentId,
                gymID: gymId,
                forceRefresh: forceRefresh
            )
            for (name, entity) in studentEntities {
                guard !Task.isCancelled else { return }
                if let url = profiles[entity.numericID]?.pictureURL(fallback: nil) { avatarURLs[name] = url }
            }
            for (name, url) in lookup.resolved {
                if avatarURLs[name] == nil { avatarURLs[name] = url }
            }
            for (name, entity) in lookup.needsFetch {
                guard !Task.isCancelled else { return }
                if avatarURLs[name] != nil { continue }
                await DirectoryStore.shared.fetchPictureIDIfNeeded(for: entity, authenticatedStudentID: studentId)
                if let url = DirectoryStore.shared.pictureURL(for: entity) {
                    avatarURLs[name] = url
                }
            }
        }
    }

    // MARK: - Attachment Fetch

    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 20
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    func fetchImage(relativePath: String) async -> UIImage? {
        let cacheKey = relativePath as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        guard let student = currentStudent,
              let credentials = currentCredentials,
              let data = try? await httpClient.fetchAttachmentData(
                  relativePath: relativePath,
                  credentials: credentials,
                  studentId: student.studentId
              )
        else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsampleImage(data: data, maxPixelSize: 4_096)
        }.value
        guard let image else { return nil }
        imageCache.setObject(image, forKey: cacheKey, cost: data.count)
        return image
    }

    private nonisolated static func downsampleImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

}
