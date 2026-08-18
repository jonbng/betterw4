//
//  W4PageCache.swift
//  BetterW4
//
//  On-disk cache of fetched W4 pages, so every screen can render instantly from the last known
//  copy and then refresh (features.md §2.4).
//
//  Layout:  Caches/W4Pages/<base64url(uwcId)>/<sha256(key)>.html
//           Caches/W4Pages/<base64url(uwcId)>/<sha256(key)>.meta.json
//
//  Scoped per uwc id so signing in as a different student can never surface the previous
//  student's pages. Marked `excludedFromBackup` — this is re-fetchable data and it may contain
//  personal information; it has no business in an iCloud backup.
//

import CryptoKit
import Foundation

/// A page as it was last served by W4.
struct CachedPage: Sendable {
    let html: String
    let fetchedAt: Date
    let finalURL: URL?
    let contentType: String?
    /// True when the page is past its surface's TTL: still renderable, but the caller should refetch.
    let isStale: Bool
}

/// An actor because several repositories read and write it concurrently while the request gate
/// serialises the network underneath.
actor W4PageCache {

    static let shared = W4PageCache()

    private let fileManager = FileManager.default
    private let root: URL?

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            self.root = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("W4Pages", isDirectory: true)
        }
    }

    // MARK: - Reading

    /// Returns the cached page for `surface` + `key`, or nil when nothing is stored.
    ///
    /// A page past its TTL is still returned, flagged `isStale`, because showing yesterday's
    /// timetable beats showing a spinner — the caller decides whether to refresh.
    func page(surface: W4Surface, key: String, uwcId: String) -> CachedPage? {
        guard let base = directory(for: uwcId, create: false) else { return nil }
        let stem = filename(for: surface, key: key)
        let htmlURL = base.appendingPathComponent(stem + ".html")
        let metaURL = base.appendingPathComponent(stem + ".meta.json")

        guard let html = try? String(contentsOf: htmlURL, encoding: .utf8) else { return nil }

        let meta = (try? Data(contentsOf: metaURL)).flatMap {
            try? JSONDecoder().decode(Meta.self, from: $0)
        }
        // A page whose sidecar is missing or corrupt is treated as ancient rather than discarded:
        // stale-but-present still beats an empty screen.
        let fetchedAt = meta?.fetchedAt ?? .distantPast

        return CachedPage(
            html: html,
            fetchedAt: fetchedAt,
            finalURL: meta?.finalURL.flatMap(URL.init(string:)),
            contentType: meta?.contentType,
            isStale: !CachePolicy.isFresh(fetchedAt, for: surface)
        )
    }

    /// Convenience: only returns a page that is still within its TTL.
    func freshPage(surface: W4Surface, key: String, uwcId: String) -> CachedPage? {
        guard let page = page(surface: surface, key: key, uwcId: uwcId), !page.isStale else { return nil }
        return page
    }

    // MARK: - Writing

    func store(
        html: String,
        surface: W4Surface,
        key: String,
        uwcId: String,
        finalURL: URL? = nil,
        contentType: String? = nil,
        fetchedAt: Date = TimeProvider.now
    ) {
        guard let base = directory(for: uwcId, create: true) else { return }
        let stem = filename(for: surface, key: key)

        do {
            try html.write(
                to: base.appendingPathComponent(stem + ".html"),
                atomically: true,
                encoding: .utf8
            )
            let meta = Meta(
                fetchedAt: fetchedAt,
                finalURL: finalURL?.absoluteString,
                contentType: contentType
            )
            try JSONEncoder().encode(meta).write(
                to: base.appendingPathComponent(stem + ".meta.json"),
                options: .atomic
            )
        } catch {
            // A cache miss is survivable; never let it break a fetch that already succeeded.
            #if DEBUG
            print("⚠️ [W4PageCache] Could not store \(surface.rawValue): \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Clearing

    func remove(surface: W4Surface, key: String, uwcId: String) {
        guard let base = directory(for: uwcId, create: false) else { return }
        let stem = filename(for: surface, key: key)
        try? fileManager.removeItem(at: base.appendingPathComponent(stem + ".html"))
        try? fileManager.removeItem(at: base.appendingPathComponent(stem + ".meta.json"))
    }

    /// Drops every page for one student, or the whole cache when `uwcId` is nil.
    /// Used by "Clear cache" in Settings and on logout.
    func clear(uwcId: String? = nil) {
        guard let root else { return }
        if let uwcId, let base = directory(for: uwcId, create: false) {
            try? fileManager.removeItem(at: base)
        } else {
            try? fileManager.removeItem(at: root)
        }
    }

    /// Total bytes on disk, for the Settings cache row.
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
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Layout

    private struct Meta: Codable {
        let fetchedAt: Date
        let finalURL: String?
        let contentType: String?
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

    /// Hashed so a route with query parameters can never produce an illegal filename, and so a
    /// long route cannot blow the 255-byte filename limit.
    private func filename(for surface: W4Surface, key: String) -> String {
        let digest = SHA256.hash(data: Data("\(surface.rawValue)|\(key)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Base64url without padding: safe as a directory name, and it keeps the uwc id out of the
    /// filesystem in plain text.
    private func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
