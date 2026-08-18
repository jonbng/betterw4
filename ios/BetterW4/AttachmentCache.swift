//
//  AttachmentCache.swift
//  BetterW4
//
//  `Caches/Attachments/` — downloaded mail attachments, LRU-evicted at 50 MB / 100 files
//  (features.md §2.4 item 3, mirroring `feature/attachments/AttachmentCache.kt:30-76`).
//
//  Why a bounded cache and not just "write it to Caches and forget":
//    a term's worth of PDFs is comfortably a gigabyte, iOS purges Caches at its own convenience
//    (which is to say, in the middle of the one lesson the student needed the handout offline),
//    and an unbounded directory makes the Settings "storage used" row meaningless. Two ceilings —
//    bytes *and* file count — because 100 tiny images and one 200 MB video are the same problem
//    from opposite ends.
//
//  Recency is the file's modification date, refreshed on every read (`file(for:)` touches). No
//  sidecar index: an index and a directory drift apart the first time a write is interrupted,
//  and the recovery code for that is worse than the mtime it replaces. iOS does not update access
//  times reliably, which is why this touches on read rather than trusting `.contentAccessDateKey`.
//
//  Nothing here is scoped per student on purpose: the key is a hash of the absolute URL, and a W4
//  attachment URL already carries its own id. Sign-out calls `clear()`.
//

import CryptoKit
import Foundation

/// Disk cache for downloaded files, evicting the least recently used first.
///
/// An actor: downloads finish on arbitrary tasks and the eviction sweep must not interleave with
/// a concurrent store. `init(root:…)` exists so tests get their own directory and their own clock.
actor AttachmentCache {

    static let shared = AttachmentCache()

    /// features.md §2.4 item 3.
    static let defaultMaximumByteCount: Int64 = 50 * 1_024 * 1_024
    static let defaultMaximumFileCount = 100

    private let fileManager = FileManager.default
    private let root: URL?
    private let maximumByteCount: Int64
    private let maximumFileCount: Int
    private let now: @Sendable () -> Date

    init(
        root: URL? = nil,
        maximumByteCount: Int64 = AttachmentCache.defaultMaximumByteCount,
        maximumFileCount: Int = AttachmentCache.defaultMaximumFileCount,
        now: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        if let root {
            self.root = root
        } else {
            self.root = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Attachments", isDirectory: true)
        }
        self.maximumByteCount = maximumByteCount
        self.maximumFileCount = maximumFileCount
        self.now = now
    }

    // MARK: - Reading

    /// The local file for `remoteURL`, or nil when it is not cached.
    ///
    /// Reading counts as use: the file is touched so it moves to the back of the eviction queue.
    func file(for remoteURL: String, name: String? = nil) -> URL? {
        guard let url = fileURL(for: remoteURL, name: name),
              fileManager.fileExists(atPath: url.path) else { return nil }
        touch(url)
        return url
    }

    func contains(_ remoteURL: String, name: String? = nil) -> Bool {
        guard let url = fileURL(for: remoteURL, name: name) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Writing

    /// Writes `data` and evicts until both ceilings hold again.
    ///
    /// The file just written is never the eviction victim, even when it alone exceeds the byte
    /// ceiling: the caller is about to open it, and handing back a URL we just deleted would be
    /// worse than being briefly over budget.
    @discardableResult
    func store(_ data: Data, for remoteURL: String, name: String? = nil) -> URL? {
        guard directory(create: true) != nil,
              let url = fileURL(for: remoteURL, name: name) else { return nil }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            #if DEBUG
            print("⚠️ [AttachmentCache] write failed: \(error.localizedDescription)")
            #endif
            return nil
        }
        touch(url)
        evict(protecting: url)
        return url
    }

    // MARK: - Clearing

    func remove(_ remoteURL: String, name: String? = nil) {
        guard let url = fileURL(for: remoteURL, name: name) else { return }
        try? fileManager.removeItem(at: url)
    }

    func clear() {
        guard let root else { return }
        try? fileManager.removeItem(at: root)
    }

    // MARK: - Accounting

    func sizeInBytes() -> Int64 {
        entries().reduce(0) { $0 + $1.byteCount }
    }

    func fileCount() -> Int {
        entries().count
    }

    // MARK: - Eviction

    private struct Entry {
        let url: URL
        let byteCount: Int64
        let lastUsedAt: Date
    }

    /// Oldest first, until both ceilings hold.
    private func evict(protecting survivor: URL?) {
        let candidates = entries().sorted { $0.lastUsedAt < $1.lastUsedAt }
        var totalBytes = candidates.reduce(0) { $0 + $1.byteCount }
        var totalFiles = candidates.count
        let survivorPath = survivor?.standardizedFileURL.path

        var index = 0
        while index < candidates.count, totalBytes > maximumByteCount || totalFiles > maximumFileCount {
            let candidate = candidates[index]
            index += 1
            if candidate.url.standardizedFileURL.path == survivorPath { continue }
            guard (try? fileManager.removeItem(at: candidate.url)) != nil else { continue }
            totalBytes -= candidate.byteCount
            totalFiles -= 1
        }
    }

    private func entries() -> [Entry] {
        guard let root,
              let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            if values?.isDirectory == true { return nil }
            return Entry(
                url: url,
                byteCount: Int64(values?.fileSize ?? 0),
                lastUsedAt: values?.contentModificationDate ?? .distantPast
            )
        }
    }

    private func touch(_ url: URL) {
        try? fileManager.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
    }

    // MARK: - Layout

    private func directory(create: Bool) -> URL? {
        guard let root else { return nil }
        guard create else {
            return fileManager.fileExists(atPath: root.path) ? root : nil
        }
        if !fileManager.fileExists(atPath: root.path) {
            do {
                try fileManager.createDirectory(
                    at: root,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
            } catch {
                return nil
            }
            // Re-downloadable, and it holds other people's documents: keep it out of iCloud.
            var mutable = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutable.setResourceValues(values)
        }
        return root
    }

    /// `sha256(remoteURL)__<sanitised name>` (features.md §2.4 item 3). The hash carries identity
    /// so two files called `handbook.pdf` from different URLs cannot collide; the readable suffix
    /// survives so a Files-app export and a QuickLook preview both show something meaningful, and
    /// so the extension still drives UTI detection.
    private func fileURL(for remoteURL: String, name: String?) -> URL? {
        guard let root, !remoteURL.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(remoteURL.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let suffix = Self.sanitised(name ?? Self.lastPathComponent(of: remoteURL))
        return root.appendingPathComponent("\(digest)__\(suffix)")
    }

    /// Everything outside `[A-Za-z0-9._-]` becomes `_`, then the whole thing is capped so
    /// hash + separator + name stays well inside the 255-byte filename limit.
    static func sanitised(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        var cleaned = String(raw.map { allowed.contains($0) ? $0 : "_" })
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.isEmpty { return "file" }
        if cleaned.count > 80 {
            // Keep the extension: it is what QuickLook and the share sheet key off.
            let parts = cleaned.split(separator: ".")
            if parts.count > 1, let ext = parts.last, ext.count <= 8 {
                let stem = cleaned.dropLast(ext.count + 1)
                cleaned = String(stem.prefix(80 - ext.count - 1)) + "." + ext
            } else {
                cleaned = String(cleaned.prefix(80))
            }
        }
        return cleaned
    }

    private static func lastPathComponent(of remoteURL: String) -> String {
        let path = remoteURL.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? remoteURL
        guard let last = path.split(separator: "/").last else { return "file" }
        let decoded = String(last).removingPercentEncoding ?? String(last)
        return decoded.isEmpty ? "file" : decoded
    }
}
