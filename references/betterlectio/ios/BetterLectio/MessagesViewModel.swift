//
//  MessagesViewModel.swift
//  BetterLectio
//

import Combine
import Foundation
import SwiftUI

@MainActor
class MessagesViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var threads: [MessageThread] = [] {
        didSet { scheduleThreadFilter() }
    }
    @Published var searchQuery = "" {
        didSet { scheduleThreadFilter() }
    }
    @Published private(set) var visibleThreads: [MessageThread] = []
    @Published var avatarURLs: [String: URL?] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFolder: MessageFolder = .newest
    @Published var availableFolders: [MessageFolder] = MessageFolder.defaults
    @Published var selectedThread: MessageThread?
    @Published var showThreadDetail = false

    // MARK: - Services

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared
    private var activeLoadID: UUID?
    private var avatarTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    // MARK: - Thread Selection

    func selectThread(_ thread: MessageThread) {
        selectedThread = thread
        showThreadDetail = true

        // Mark as read locally
        if let index = threads.firstIndex(where: { $0.id == thread.id }), !threads[index].isRead {
            threads[index] = MessageThread(
                id: thread.id,
                title: thread.title,
                senderName: thread.senderName,
                firstSenderName: thread.firstSenderName,
                recipients: thread.recipients,
                date: thread.date,
                isRead: true,
                isFlagged: thread.isFlagged,
                hasAttachment: thread.hasAttachment,
                senderType: thread.senderType
            )
        }
    }

    // MARK: - Load Messages

    func loadMessages(for student: Student) async {
        let loadID = UUID()
        activeLoadID = loadID
        let requestedFolder = selectedFolder
        errorMessage = nil

        if student.isDemo {
            loadDemoMessages()
            return
        }

        // 1. Load from cache immediately
        let cachedThreads = await MessageCacheManager.loadThreads(studentId: student.studentId, folder: requestedFolder)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        if let cached = cachedThreads {
            threads = cached
            resolveAvatarURLs(for: cached, student: student)
        } else {
            threads = []
            avatarURLs = [:]
        }

        // 2. Only show loading spinner if we have nothing cached
        if threads.isEmpty {
            isLoading = true
        }

        // 3. Fetch fresh data from network
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                errorMessage = "Ingen loginoplysninger fundet"
                isLoading = false
                return
            }

            let html = try await httpClient.fetchMessages(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                folder: requestedFolder
            )
            try Task.checkCancellation()

            let (parsedThreads, parsedFolders) = try await Task.detached(priority: .userInitiated) {
                let threads = try MessageParser.parseMessageThreads(from: html)
                let folders = MessageParser.parseMessageFolders(from: html)
                return (threads, folders)
            }.value
            guard !Task.isCancelled, activeLoadID == loadID, selectedFolder.id == requestedFolder.id else { return }
            threads = parsedThreads
            if !parsedFolders.isEmpty {
                availableFolders = parsedFolders
                // Snap selection back to newest if Lectio no longer advertises the current folder.
                if !parsedFolders.contains(where: { $0.id == requestedFolder.id }) {
                    selectedFolder = parsedFolders.first ?? .newest
                }
            }
            resolveAvatarURLs(for: parsedThreads, student: student)

            // 4. Save to cache
            await MessageCacheManager.saveThreads(parsedThreads, studentId: student.studentId, folder: requestedFolder)

            print("📨 Loaded \(threads.count) messages (folders: \(availableFolders.count))")

        } catch let error as LectioError {
            guard activeLoadID == loadID else { return }
            error.notifyIfSessionExpired()
            // Only show error if we have no cached data to display
            if threads.isEmpty {
                errorMessage = error.errorDescription
            }
        } catch {
            guard activeLoadID == loadID, !(error is CancellationError) else { return }
            if threads.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        if activeLoadID == loadID {
            isLoading = false
        }
    }

    // MARK: - Mark as Read

    func markAsRead(threadId: String, for student: Student) async {
        if student.isDemo {
            mutateThread(id: threadId) { $0.markedRead() }
            return
        }
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                return
            }

            try await httpClient.markMessageAsRead(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: threadId,
                folder: selectedFolder
            )

            // Update local state
            if let index = threads.firstIndex(where: { $0.id == threadId }) {
                let thread = threads[index]
                threads[index] = MessageThread(
                    id: thread.id,
                    title: thread.title,
                    senderName: thread.senderName,
                    firstSenderName: thread.firstSenderName,
                    recipients: thread.recipients,
                    date: thread.date,
                    isRead: true,
                    isFlagged: thread.isFlagged,
                    hasAttachment: thread.hasAttachment,
                    senderType: thread.senderType
                )
            }
            MessageListPrefetcher.refreshUnreadFolder(for: student)
        } catch {
            print("⚠️ Failed to mark message as read: \(error)")
        }
    }

    // MARK: - Swipe Actions

    func toggleFlag(threadId: String, for student: Student) async {
        if student.isDemo {
            mutateThread(id: threadId) { $0.toggledFlag() }
            return
        }
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else { return }

            try await httpClient.toggleMessageFlag(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: threadId
            )

            if let index = threads.firstIndex(where: { $0.id == threadId }) {
                let thread = threads[index]
                threads[index] = MessageThread(
                    id: thread.id,
                    title: thread.title,
                    senderName: thread.senderName,
                    firstSenderName: thread.firstSenderName,
                    recipients: thread.recipients,
                    date: thread.date,
                    isRead: thread.isRead,
                    isFlagged: !thread.isFlagged,
                    hasAttachment: thread.hasAttachment,
                    senderType: thread.senderType
                )
            }
        } catch {
            print("⚠️ Failed to toggle flag: \(error)")
        }
    }

    func toggleReadStatus(threadId: String, for student: Student) async {
        if student.isDemo {
            mutateThread(id: threadId) { $0.toggledRead() }
            return
        }
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else { return }

            try await httpClient.toggleMessageReadStatus(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: threadId,
                folder: selectedFolder
            )

            if let index = threads.firstIndex(where: { $0.id == threadId }) {
                let thread = threads[index]
                threads[index] = MessageThread(
                    id: thread.id,
                    title: thread.title,
                    senderName: thread.senderName,
                    firstSenderName: thread.firstSenderName,
                    recipients: thread.recipients,
                    date: thread.date,
                    isRead: !thread.isRead,
                    isFlagged: thread.isFlagged,
                    hasAttachment: thread.hasAttachment,
                    senderType: thread.senderType
                )
            }
            MessageListPrefetcher.refreshUnreadFolder(for: student)
        } catch {
            print("⚠️ Failed to toggle read status: \(error)")
        }
    }

    func deleteMessage(threadId: String, for student: Student) async {
        if student.isDemo {
            threads.removeAll { $0.id == threadId }
            return
        }
        print("🗑️ [MessageDelete] deleteMessage started threadId=\(threadId) studentId=\(student.studentId) gymId=\(student.gymId)")
        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                print("🗑️ [MessageDelete] aborted: no keychain credentials for studentId=\(student.studentId)")
                return
            }

            print("🗑️ [MessageDelete] calling HTTP delete… threadCount=\(threads.count)")
            try await httpClient.deleteMessage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                threadId: threadId,
                folder: selectedFolder
            )

            let before = threads.count
            threads.removeAll { $0.id == threadId }
            print("🗑️ [MessageDelete] local list updated removed=\(before - threads.count) threadCount=\(threads.count)")
            MessageListPrefetcher.refreshUnreadFolder(for: student)
        } catch {
            print("🗑️ [MessageDelete] delete failed: \(String(describing: error)) localized=\(error.localizedDescription)")
        }
    }

    // MARK: - Refresh

    func refresh(for student: Student) async {
        await loadMessages(for: student)
    }

    // MARK: - Demo Mode

    private func loadDemoMessages() {
        if availableFolders.isEmpty {
            availableFolders = DemoDataProvider.defaultFolders
        }
        threads = DemoDataProvider.messageThreads(for: selectedFolder)
        avatarURLs = [:]
        isLoading = false
        errorMessage = nil
    }

    private func mutateThread(id: String, _ transform: (MessageThread) -> MessageThread) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[idx] = transform(threads[idx])
    }

    private func scheduleThreadFilter() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = threads
        guard !query.isEmpty else {
            visibleThreads = snapshot
            return
        }
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return
            }
            let filtered = await Task.detached(priority: .userInitiated) {
                snapshot.filter { thread in
                    thread.senderName.localizedCaseInsensitiveContains(query)
                        || thread.title.localizedCaseInsensitiveContains(query)
                }
            }.value
            guard !Task.isCancelled, self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                return
            }
            self?.visibleThreads = filtered
        }
    }

    // MARK: - Avatar Resolution

    func refreshAvatarProfiles(for student: Student) {
        avatarURLs.removeAll()
        resolveAvatarURLs(for: threads, student: student, forceRefresh: true)
    }

    private func resolveAvatarURLs(
        for threads: [MessageThread],
        student: Student,
        forceRefresh: Bool = false
    ) {
        if student.isDemo { return }
        let names = threads.map { $0.senderName }
        avatarTask?.cancel()
        avatarTask = Task { [weak self] in
            guard let self else { return }
            let directory = DirectoryStore.shared
            let lookup = await directory.batchAvatarLookup(forNames: names, gymId: student.gymId)
            guard !Task.isCancelled else { return }
            var studentEntities: [String: DirectoryEntity] = [:]
            for name in names {
                if let entity = directory.resolvePersonByName(name, gymId: student.gymId), entity.kind == .student {
                    studentEntities[name] = entity
                }
            }
            let profiles = await SupabaseStudentProfileService.shared.profiles(
                studentIDs: studentEntities.values.map(\.numericID),
                viewerStudentID: student.studentId,
                gymID: student.gymId,
                forceRefresh: forceRefresh
            )
            for (name, entity) in studentEntities {
                if let url = profiles[entity.numericID]?.pictureURL(fallback: nil) { avatarURLs[name] = url }
            }
            for (name, url) in lookup.resolved {
                if avatarURLs[name] == nil { avatarURLs[name] = url }
            }
            for (name, entity) in lookup.needsFetch {
                guard !Task.isCancelled else { return }
                if avatarURLs[name] != nil { continue }
                await DirectoryStore.shared.fetchPictureIDIfNeeded(for: entity, authenticatedStudentID: student.studentId)
                if let url = DirectoryStore.shared.pictureURL(for: entity) {
                    avatarURLs[name] = url
                }
            }
        }
    }
}
