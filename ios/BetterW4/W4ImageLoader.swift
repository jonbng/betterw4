//
//  W4ImageLoader.swift
//  BetterW4
//
//  Loads W4 member portraits with an in-memory cache and in-flight deduplication.
//
//  Three rules, and they are the whole file:
//
//    1. **W4 host only.** A portrait request carries the PHPSESSID, so the URL is checked against
//       `W4Routes.isW4Host` before anything else. Anything else returns nil rather than leaking a
//       session cookie to a third party.
//    2. **Avatars never outrank a screen.** Every fetch goes through the same serial request gate
//       as HTML traffic at `.opportunistic`, so a list of 200 portraits can never starve the
//       timetable the student is actually looking at (features.md §3 rule 12).
//    3. **Demo makes no requests.** A demo session returns nil immediately and the UI draws
//       initials (features.md §4).
//
//  W4 serves portraits at `https://w4.uwcrcn.no/files/user_photos/{uwc_id}_thumb.jpg`
//  (`W4PeopleParser.photoURL(forUWCId:)` is the one place that URL is built).
//

import Foundation
import ImageIO
import UIKit

actor W4ImageLoader {
    static let shared = W4ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let keychainManager = KeychainManager.shared
    private let cookieManager = CookieManager.shared

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024  // ~50 MB
    }

    /// W4's missing-portrait placeholder. A redirect to it means "this person has no photo".
    private static let placeholderPath = "/images/user.png"
    private static let maxRetries = 3
    private static let maxImageBytes = 8 * 1_024 * 1_024

    /// Portraits are prefetch-shaped traffic: never let one queue ahead of a screen fetch.
    private static let priority: FetchPriority = .opportunistic

    // MARK: - Loading

    /// The portrait for `uwcId`, or nil when W4 has none.
    func loadImage(forUWCId uwcId: String) async -> UIImage? {
        guard let url = W4PeopleParser.photoURL(forUWCId: uwcId) else { return nil }
        return await loadImage(from: url)
    }

    func loadImage(from url: URL) async -> UIImage? {
        guard Self.isW4URL(url) else {
            print("⚠️ [Photo] Refused to attach the W4 session cookie to a non-W4 URL")
            return nil
        }
        // Demo mode: never hit the network for portraits; the UI falls back to initials.
        if keychainManager.loadStudent()?.isDemo == true {
            return nil
        }

        let key = url.absoluteString as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        // If this URL is already being fetched, wait for that result rather than starting a second
        // request for the same bytes.
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            defer { inFlight[url] = nil }

            for attempt in 0..<Self.maxRetries {
                do {
                    print("🖼️ [Photo] Fetching \(W4RequestLog.compactPath(for: url))")
                    var request = URLRequest(url: url)
                    request.setValue(W4UserAgent.referer, forHTTPHeaderField: "Referer")
                    request.setValue(W4UserAgent.value, forHTTPHeaderField: "User-Agent")
                    request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*", forHTTPHeaderField: "Accept")

                    // W4 serves portraits only to an authenticated session, so the PHPSESSID rides
                    // along exactly as it does for HTML.
                    let student = keychainManager.loadStudent()
                    let credentials = student.flatMap { keychainManager.loadCredentials(for: $0.studentId) }
                    let cookieHeader: String?
                    if let credentials {
                        let header = cookieManager.cookieHeader(from: credentials)
                        request.setValue(header, forHTTPHeaderField: "Cookie")
                        cookieHeader = header
                    } else {
                        cookieHeader = nil
                    }
                    W4RequestLog.outbound(method: "GET", url: url, cookieHeader: cookieHeader)

                    let (data, response): (Data, URLResponse) = try await W4HTTPClient.withSerialW4Request(
                        priority: Self.priority
                    ) {
                        try Task.checkCancellation()
                        if let credentials, let studentId = student?.studentId {
                            // Portrait traffic rotates the same cookie jar as HTML traffic, so it
                            // needs the redirect cookie context as well as the global gate.
                            let freshestCredentials = keychainManager.loadCredentials(for: studentId) ?? credentials
                            request.setValue(cookieManager.cookieHeader(from: freshestCredentials), forHTTPHeaderField: "Cookie")
                            let context = W4DataTaskCookieContext(
                                credentials: freshestCredentials,
                                studentId: studentId,
                                onUpdate: nil
                            )
                            let result = try await W4HTTPClient.dataTaskForW4Request(request, redirectContext: context)
                            if let httpResponse = result.1 as? HTTPURLResponse,
                               let updated = cookieManager.updateCredentials(from: httpResponse, currentCredentials: context.creds) {
                                try? keychainManager.updateCredentials(updated, for: studentId)
                            }
                            return result
                        }
                        return try await W4HTTPClient.sharedSession.data(for: request)
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200,
                          data.count <= Self.maxImageBytes,
                          let decoded = Self.downsample(data: data, maxPixelSize: 1_024) else {
                        return nil
                    }

                    // W4 answers "no photo on file" with a redirect to its placeholder. Retry once
                    // in case the portrait was still being written, then give up and let the
                    // caller draw initials.
                    if Self.isPlaceholder(httpResponse.url) {
                        if attempt < Self.maxRetries - 1 {
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                            continue
                        }
                        return nil
                    }

                    // Force decompression here (off the main thread) so the image is not decoded
                    // lazily during scrolling, which makes lists stutter.
                    let image = decoded.preparingForDisplay() ?? decoded
                    cache.setObject(image, forKey: key, cost: data.count)
                    return image
                } catch {
                    return nil
                }
            }
            return nil
        }

        inFlight[url] = task
        return await task.value
    }

    /// True only for `https://w4.uwcrcn.no` (and subdomains). W4 is one school on one host.
    nonisolated static func isW4URL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && W4Routes.isW4Host(url.host)
    }

    private nonisolated static func isPlaceholder(_ url: URL?) -> Bool {
        guard let path = url?.path.lowercased() else { return false }
        return path.hasSuffix(placeholderPath)
    }

    // MARK: - Cache Management

    /// Drops every decoded portrait. Called by Settings ▸ Clear cache and on sign-out.
    func clearCache() {
        cache.removeAllObjects()
        print("🗑️ Cleared the portrait cache")
    }

    private nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
