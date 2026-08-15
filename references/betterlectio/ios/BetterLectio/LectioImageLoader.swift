//
//  LectioImageLoader.swift
//  BetterLectio
//

import Foundation
import ImageIO
import UIKit

/// Loads Lectio profile images with in-memory caching and in-flight deduplication.
/// Multiple callers requesting the same URL share a single network fetch.
/// Uses Keychain credentials for authenticated requests (Lectio requires cookies).
actor LectioImageLoader {
    static let shared = LectioImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let keychainManager = KeychainManager.shared
    private let cookieManager = CookieManager.shared

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024  // ~50 MB
    }

    private static let defaultPlaceholderPath = "defaultfoto_small.jpg"
    private static let maxRetries = 3
    private static let maxImageBytes = 8 * 1_024 * 1_024

    func loadImage(from url: URL) async -> UIImage? {
        guard Self.isLectioURL(url) else {
            print("⚠️ [Pfp] Refused to attach Lectio credentials to a non-Lectio URL")
            return nil
        }
        // Demo mode: never hit the network for avatars; UI falls back to initials.
        if keychainManager.loadStudent()?.isDemo == true {
            return nil
        }

        let key = url.absoluteString as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        // If this URL is already being fetched, wait for that result
        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            defer { inFlight[url] = nil }

            for attempt in 0..<Self.maxRetries {
                do {
                    print("🖼️ [Pfp] Fetching image: \(LectioRequestLog.compactPath(for: url))")
                    var request = URLRequest(url: url)
                    request.setValue("https://www.lectio.dk", forHTTPHeaderField: "Referer")
                    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

                    // Add auth cookies from Keychain (Lectio requires authenticated requests for profile images).
                    // Always try with stored credentials even if dates look stale — server rotates on valid autologin.
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
                    LectioRequestLog.outbound(method: "GET", url: url, cookieHeader: cookieHeader)

                    let (data, response): (Data, URLResponse) = try await LectioHTTPClient.withSerialLectioRequest(
                        priority: .opportunistic
                    ) {
                        try Task.checkCancellation()
                        if let credentials, let studentId = student?.studentId {
                            // Image traffic rotates the same cookie jar as HTML traffic, so it must
                            // use the global Lectio gate as well as the redirect cookie context.
                            let freshestCredentials = keychainManager.loadCredentials(for: studentId) ?? credentials
                            request.setValue(cookieManager.cookieHeader(from: freshestCredentials), forHTTPHeaderField: "Cookie")
                            let context = LectioDataTaskCookieContext(
                                credentials: freshestCredentials,
                                studentId: studentId,
                                onUpdate: nil
                            )
                            let result = try await LectioHTTPClient.dataTaskForLectioRequest(request, redirectContext: context)
                            if let httpResponse = result.1 as? HTTPURLResponse,
                               let updated = cookieManager.updateCredentials(from: httpResponse, currentCredentials: context.creds) {
                                try? keychainManager.updateCredentials(updated, for: studentId)
                            }
                            return result
                        }
                        return try await LectioHTTPClient.sharedSession.data(for: request)
                    }

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200,
                          data.count <= Self.maxImageBytes,
                          let decoded = Self.downsample(data: data, maxPixelSize: 1_024) else {
                        return nil
                    }
                    // Force decompression here (off the main thread) so the image doesn't
                    // get decoded lazily during scrolling, which causes janky list scrolling.
                    let image = decoded.preparingForDisplay() ?? decoded

                    // If redirected to default placeholder, retry after 1s
                    let wasRedirected = httpResponse.url?.absoluteString.contains(Self.defaultPlaceholderPath) ?? false
                    if wasRedirected && attempt < Self.maxRetries - 1 {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }

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

    nonisolated static func isLectioURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "lectio.dk" || host == "www.lectio.dk" || host.hasSuffix(".lectio.dk")
    }
    
    // MARK: - Cache Management
    
    /// Clears the in-memory image cache
    func clearCache() {
        cache.removeAllObjects()
        print("🗑️ Cleared image cache")
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
