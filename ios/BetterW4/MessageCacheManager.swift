//
//  MessageCacheManager.swift
//  BetterW4
//
//  The on-disk cache of *parsed* W4 mail (features.md §2.4).
//
//  Layout:  Caches/MailCache/<base64url(uwcId)>/list_<base64url(folderId)>.json
//           Caches/MailCache/<base64url(uwcId)>/message_<base64url(messageId)>.json
//
//  Why a second cache when `W4PageCache` already stores the HTML:
//    * a list must render the instant the tab opens, and re-running SwiftSoup over a 60 KB Yii
//      grid on every cold launch is exactly the cost the page cache cannot avoid;
//    * a message body is immutable — a sent message never changes — so it is worth keeping in a
//      form that needs no parsing at all.
//  The HTML page cache stays the lossless record; this is the fast path.
//
//  Scoped per uwc id, so signing in as another student can never surface the previous student's
//  mail. Excluded from backup: it is re-fetchable and it is personal correspondence.
//

import Foundation

// MARK: - Snapshots

/// One cached mail grid, stored as JSON so the list paints without re-parsing a Yii table.
///
/// The column layout is persisted too. It is a parsing artefact, but it is the thing that tells
/// the row view whether this grid even had a `From` column — dropping it made a restored inbox
/// render as though W4 had never sent one.
struct MailListSnapshot: Codable, Sendable {
    let folderID: String
    let messages: [MailMessage]
    let pagination: MailPagination?
    let outcome: MailListOutcome
    let columns: MailColumnLayout
    let fetchedAt: Date

    init(page: MailListPage, fetchedAt: Date) {
        self.folderID = page.folder.id
        self.messages = page.messages
        self.pagination = page.pagination
        self.outcome = page.outcome
        self.columns = page.columns
        self.fetchedAt = fetchedAt
    }

    /// Rebuilt page. The caller passes the folder it asked for rather than having it looked up
    /// from the stored id, so a snapshot written under an id this build no longer recognises
    /// still renders instead of being discarded.
    func page(folder: MailFolder) -> MailListPage {
        MailListPage(
            folder: folder,
            messages: messages,
            pagination: pagination,
            outcome: outcome,
            columns: columns
        )
    }

    /// Convenience for callers that have only the snapshot; falls back to the inbox when the
    /// stored folder id is unknown.
    var page: MailListPage {
        page(folder: MailFolder.folder(id: folderID) ?? .inbox)
    }

    /// Unread messages in this snapshot — what the tab badge counts.
    var unreadCount: Int {
        messages.filter(\.isUnread).count
    }
}

/// One cached message body.
struct MailMessageSnapshot: Codable, Sendable {
    let detail: MailMessageDetail
    let fetchedAt: Date

    init(detail: MailMessageDetail, fetchedAt: Date) {
        self.detail = detail
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Store

actor MailFileCache {

    static let shared = MailFileCache()

    private let fileManager = FileManager.default
    private let root: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MailCache", isDirectory: true)
        }
    }

    // MARK: Lists

    func storeList(_ snapshot: MailListSnapshot, uwcId: String) {
        write(snapshot, to: "list_" + base64URL(snapshot.folderID), uwcId: uwcId)

        // The tab badge is a fact about the inbox, so it is published wherever the inbox is
        // written — a background prefetch updates the badge exactly like a foreground load.
        guard snapshot.folderID == MailFolder.inbox.id else { return }
        let count = snapshot.messages.filter(\.isUnread).count
        NotificationCenter.default.post(
            name: .unreadMessageCountDidChange,
            object: nil,
            userInfo: ["studentId": uwcId, "count": count]
        )
    }

    func list(folderID: String, uwcId: String) -> MailListSnapshot? {
        read(MailListSnapshot.self, from: "list_" + base64URL(folderID), uwcId: uwcId)
    }

    /// Unread count from the cached inbox, for the badge on cold launch before any fetch.
    func unreadInboxCount(uwcId: String) -> Int {
        list(folderID: MailFolder.inbox.id, uwcId: uwcId)?
            .messages.filter(\.isUnread).count ?? 0
    }

    // MARK: Messages

    func storeMessage(_ snapshot: MailMessageSnapshot, uwcId: String) {
        write(snapshot, to: "message_" + base64URL(snapshot.detail.id), uwcId: uwcId)
    }

    func message(id: String, uwcId: String) -> MailMessageSnapshot? {
        read(MailMessageSnapshot.self, from: "message_" + base64URL(id), uwcId: uwcId)
    }

    // MARK: Housekeeping

    /// Drops one student's mail, or all of it when `uwcId` is nil.
    func clear(uwcId: String? = nil) {
        guard let root else { return }
        if let uwcId, let directory = directory(for: uwcId, create: false) {
            try? fileManager.removeItem(at: directory)
        } else {
            try? fileManager.removeItem(at: root)
        }
    }

    func sizeInBytes() -> Int64 {
        guard let root,
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: Files

    private func write<Value: Encodable>(_ value: Value, to name: String, uwcId: String) {
        guard let directory = directory(for: uwcId, create: true) else { return }
        do {
            let data = try encoder.encode(value)
            try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        } catch {
            #if DEBUG
            print("⚠️ [MailFileCache] Could not write \(name): \(error.localizedDescription)")
            #endif
        }
    }

    private func read<Value: Decodable>(_ type: Value.Type, from name: String, uwcId: String) -> Value? {
        guard let directory = directory(for: uwcId, create: false),
              let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".json"))
        else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func directory(for uwcId: String, create: Bool) -> URL? {
        guard let root else { return nil }
        let scoped = root.appendingPathComponent(base64URL(uwcId), isDirectory: true)
        if create, !fileManager.fileExists(atPath: scoped.path) {
            do {
                try fileManager.createDirectory(at: scoped, withIntermediateDirectories: true)
                var mutable = scoped
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? mutable.setResourceValues(values)
            } catch {
                return nil
            }
        }
        return scoped
    }

    private func base64URL(_ value: String) -> String {
        Self.safeComponent(value)
    }

    /// Base64url without padding: legal as a filename, and it keeps uwc ids, folder names and
    /// message ids out of the filesystem in plain text. `nonisolated` and internal so the cache
    /// layout can be asserted without booting the actor.
    nonisolated static func safeComponent(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - App-facing façade

/// Cache operations the rest of the app performs without knowing how mail is stored:
/// logging out, "Clear cache" in Settings, and the cache-size row.
enum MessageCacheManager {

    /// Clears one student's cached mail, or every student's when `studentId` is nil.
    static func clearCache(studentId: String? = nil) async {
        await MailFileCache.shared.clear(uwcId: studentId)
        await AttachmentCache.shared.clear()
    }

    /// Bytes used by cached mail plus its attachments, for the Settings row.
    static func mailCacheSizeInBytes() async -> Int64 {
        async let mail = MailFileCache.shared.sizeInBytes()
        async let attachments = AttachmentCache.shared.sizeInBytes()
        return await mail + attachments
    }
}

extension Notification.Name {
    /// Posted whenever the cached inbox is written. `userInfo` carries `studentId` (the uwc id)
    /// and `count`, so the tab badge updates from a background prefetch as well as a foreground
    /// load without either one having to know about the other.
    static let unreadMessageCountDidChange = Notification.Name("dk.jonathanb.w4.unreadMessageCountDidChange")
}
