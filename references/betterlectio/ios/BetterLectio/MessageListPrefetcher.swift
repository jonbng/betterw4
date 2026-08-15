//
//  MessageListPrefetcher.swift
//  BetterLectio
//

import Foundation

/// Warms the Nyeste thread list on disk when missing, and refreshes the Ulæst
/// folder (which drives the tab badge). Uses low task priority and
/// opportunistic HTTP so interactive fetches win.
enum MessageListPrefetcher {

    static func schedulePrefetch(for student: Student) {
        if student.isDemo { return }
        Task {
            await coordinator.schedule(studentId: student.studentId, gymId: student.gymId)
        }
    }

    /// Forces a refresh of the Ulæst folder cache. Use after mutations that
    /// may have changed unread state (mark-as-read, delete, thread open).
    static func refreshUnreadFolder(for student: Student) {
        Task {
            await coordinator.refreshUnread(studentId: student.studentId, gymId: student.gymId)
        }
    }

    private static let coordinator = Coordinator()

    private actor Coordinator {
        private var isPrefetching = false
        private var isRefreshingUnread = false

        func schedule(studentId: String, gymId: Int) async {
            guard !isPrefetching else { return }
            isPrefetching = true
            defer { isPrefetching = false }

            let newestMissing = await MessageCacheManager.loadThreads(studentId: studentId, folder: .newest) == nil
            await Task.detached(priority: .utility) {
                if newestMissing {
                    await MessageListPrefetcher.prefetchThreads(studentId: studentId, gymId: gymId, folder: .newest)
                }
                // Unread count drives the tab badge — always refresh.
                await MessageListPrefetcher.prefetchThreads(studentId: studentId, gymId: gymId, folder: .unread)
            }.value
        }

        func refreshUnread(studentId: String, gymId: Int) async {
            guard !isRefreshingUnread else { return }
            isRefreshingUnread = true
            defer { isRefreshingUnread = false }
            await Task.detached(priority: .utility) {
                await MessageListPrefetcher.prefetchThreads(studentId: studentId, gymId: gymId, folder: .unread)
            }.value
        }
    }

    private static func prefetchThreads(studentId: String, gymId: Int, folder: MessageFolder) async {
        do {
            guard let credentials = KeychainManager.shared.loadCredentials(for: studentId) else {
                return
            }
            let client = LectioHTTPClient()
            let html = try await client.fetchMessages(
                credentials: credentials,
                studentId: studentId,
                schoolId: gymId,
                folder: folder,
                priority: .opportunistic
            )
            let threads = try MessageParser.parseMessageThreads(from: html)
            await MessageCacheManager.saveThreads(threads, studentId: studentId, folder: folder)
        } catch {
            print("⚠️ Message list prefetch failed (\(folder.displayName)): \(error.localizedDescription)")
        }
    }
}
