//
//  MessageCacheManager.swift
//  BetterLectio
//

import Foundation

extension Notification.Name {
    /// Posted when the cached `Ulæst` (`-40`) folder for a student is rewritten.
    /// `userInfo` contains `"studentId": String` and `"count": Int`.
    static let unreadMessageCountDidChange = Notification.Name("unreadMessageCountDidChange")
}

/// Simple file-based cache for message data.
/// Stores JSON files in the Caches directory so iOS can reclaim space if needed.
enum MessageCacheManager {
    private static let storage = Storage()

    static func saveThreads(_ threads: [MessageThread], studentId: String, folder: MessageFolder) async {
        await storage.saveThreads(threads, studentId: studentId, folder: folder)
    }

    static func loadThreads(studentId: String, folder: MessageFolder) async -> [MessageThread]? {
        await storage.loadThreads(studentId: studentId, folder: folder)
    }

    static func saveThreadDetail(_ detail: MessageThreadDetail, studentId: String, gymId: Int) async {
        await storage.saveThreadDetail(detail, studentId: studentId, gymId: gymId)
    }

    static func loadThreadDetail(threadId: String, studentId: String, gymId: Int) async -> MessageThreadDetail? {
        await storage.loadThreadDetail(threadId: threadId, studentId: studentId, gymId: gymId)
    }

    static func clearCache() async {
        await storage.clearCache()
    }

    static func clearCache(studentId: String) async {
        await storage.clearCache(studentId: studentId)
    }

    private actor Storage {

        // MARK: - Cache Directory

        private var cacheDirectory: URL {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = caches.appendingPathComponent("MessageCache", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            return dir
        }

        private func writeProtected(_ data: Data, to file: URL) throws {
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }

        private func safeComponent(_ value: String) -> String {
            Data(value.utf8).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "=", with: "")
        }

        private func accountDirectory(studentId: String) -> URL {
            let directory = cacheDirectory
                .appendingPathComponent("account_\(safeComponent(studentId))", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            return directory
        }

        // MARK: - Thread Lists (per student + folder)

        /// Saves the message thread list for a given student and folder.
        func saveThreads(_ threads: [MessageThread], studentId: String, folder: MessageFolder) async {
            let file = accountDirectory(studentId: studentId)
                .appendingPathComponent("threads_\(safeComponent(folder.id)).json")
            do {
                let data = try JSONEncoder().encode(threads)
                try writeProtected(data, to: file)
                if folder.id == MessageFolder.unread.id {
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .unreadMessageCountDidChange,
                            object: nil,
                            userInfo: ["studentId": studentId, "count": threads.count]
                        )
                    }
                }
            } catch {
                print("⚠️ Cache write failed (threads): \(error)")
            }
        }

        /// Loads the cached message thread list for a given student and folder.
        func loadThreads(studentId: String, folder: MessageFolder) -> [MessageThread]? {
            let file = accountDirectory(studentId: studentId)
                .appendingPathComponent("threads_\(safeComponent(folder.id)).json")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode([MessageThread].self, from: data)
        }

        // MARK: - Thread Details (per thread ID)

        /// Saves a full thread detail (all messages, recipients, etc).
        func saveThreadDetail(_ detail: MessageThreadDetail, studentId: String, gymId: Int) {
            let file = threadDetailFile(threadId: detail.threadId, studentId: studentId, gymId: gymId)
            do {
                let data = try JSONEncoder().encode(detail)
                try writeProtected(data, to: file)
            } catch {
                print("⚠️ Cache write failed (detail): \(error)")
            }
        }

        /// Loads a cached thread detail by thread ID.
        func loadThreadDetail(threadId: String, studentId: String, gymId: Int) -> MessageThreadDetail? {
            let file = threadDetailFile(threadId: threadId, studentId: studentId, gymId: gymId)
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(MessageThreadDetail.self, from: data)
        }

        private func threadDetailFile(threadId: String, studentId: String, gymId: Int) -> URL {
            accountDirectory(studentId: studentId)
                .appendingPathComponent("detail_\(gymId)_\(safeComponent(threadId)).json")
        }

        // MARK: - Clear Cache

        /// Deletes all cached message threads and details.
        func clearCache() {
            let fileManager = FileManager.default
            do {
                let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                for file in files {
                    try fileManager.removeItem(at: file)
                }
                print("🗑️ Message cache directory cleared")
            } catch {
                print("⚠️ Failed to clear message cache: \(error)")
            }
        }

        func clearCache(studentId: String) {
            do {
                let account = accountDirectory(studentId: studentId)
                try? FileManager.default.removeItem(at: account)
                // Also remove files written by app versions before account subdirectories.
                let files = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                for file in files where file.lastPathComponent.contains("_\(studentId)_") {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                print("⚠️ Failed to clear message cache for signed-out account: \(error)")
            }
        }
    }
}
