//
//  PublicProfileImage.swift
//  BetterW4
//
//  A cookie-free image loader for portraits that do **not** live on W4.
//
//  It exists so that the app can never send the PHPSESSID to a host that is not
//  `w4.uwcrcn.no`: this loader runs on an ephemeral `URLSession` with no cookie storage, refuses
//  to follow a redirect off an allowed host, and strips `Cookie` / `Authorization` from every hop.
//  `isAllowed` therefore rejects W4 URLs outright — those belong to `W4ImageLoader`, which is the
//  only place a W4 session cookie is ever attached to an image request.
//
//  `ProfileAvatarView` is the router: W4 URLs go to the authenticated loader, everything else
//  comes here, and both fall back to locally drawn initials.
//

import ImageIO
import SwiftUI
import UIKit

private final class PublicProfileImageSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, PublicProfileImageLoader.isAllowed(url) else {
            completionHandler(nil)
            return
        }
        var safeRequest = request
        safeRequest.httpShouldHandleCookies = false
        safeRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        safeRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(safeRequest)
    }
}

/// Loads approved public profile images without sharing the app's cookie jar.
/// This must remain separate from `W4ImageLoader`, which attaches W4 credentials.
actor PublicProfileImageLoader {
    static let shared = PublicProfileImageLoader()

    private static let maximumDownloadSize = 6 * 1024 * 1024
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(
            configuration: configuration,
            delegate: PublicProfileImageSessionDelegate(),
            delegateQueue: nil
        )
        cache.countLimit = 100
        cache.totalCostLimit = 30 * 1024 * 1024
    }

    func loadImage(from url: URL, maximumPixelSize: CGFloat) async -> UIImage? {
        guard Self.isAllowed(url) else { return nil }
        let keyString = "\(url.absoluteString)|\(Int(maximumPixelSize))"
        let key = keyString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let existing = inFlight[keyString] { return await existing.value }

        let task = Task<UIImage?, Never> { [session] in
            defer { inFlight[keyString] = nil }
            do {
                var request = URLRequest(url: url)
                request.httpShouldHandleCookies = false
                request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 200,
                      let finalURL = http.url,
                      Self.isAllowed(finalURL),
                      http.expectedContentLength <= Int64(Self.maximumDownloadSize),
                      http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true else {
                    return nil
                }
                var data = Data()
                if http.expectedContentLength > 0 {
                    data.reserveCapacity(Int(http.expectedContentLength))
                }
                for try await byte in bytes {
                    guard data.count < Self.maximumDownloadSize else { return nil }
                    data.append(byte)
                }
                guard let image = Self.downsample(data: data, maximumPixelSize: maximumPixelSize) else { return nil }
                cache.setObject(image, forKey: key, cost: data.count)
                return image
            } catch {
                return nil
            }
        }
        inFlight[keyString] = task
        return await task.value
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    /// HTTPS, a real host, no embedded credentials — and never a W4 host.
    ///
    /// The W4 exclusion is the load-bearing clause: this session carries no cookies, so a W4
    /// portrait fetched through here would 403, and allowing it would blur the line between the
    /// authenticated and the anonymous loader.
    nonisolated static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            return false
        }
        return !W4Routes.isW4Host(host)
    }

    private nonisolated static func downsample(data: Data, maximumPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maximumPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct PublicProfileAvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat
    var w4FallbackURL: URL? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var hasFinishedLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if hasFinishedLoading, let w4FallbackURL {
                W4AvatarView(url: w4FallbackURL, name: name, size: size)
            } else {
                W4AvatarView.initialsPlaceholder(name: name, size: size)
                    .overlay {
                        if url != nil && !hasFinishedLoading {
                            ProgressView().tint(.white)
                        }
                    }
            }
        }
        .frame(width: size, height: size, alignment: .top)
        .clipShape(Circle())
        .task(id: url?.absoluteString) {
            image = nil
            hasFinishedLoading = false
            guard let url else {
                hasFinishedLoading = true
                return
            }
            image = await PublicProfileImageLoader.shared.loadImage(
                from: url,
                maximumPixelSize: size * displayScale
            )
            hasFinishedLoading = true
        }
    }
}

/// Routes W4 URLs through the authenticated loader and every other URL
/// through the cookie-free public loader.
struct ProfileAvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        if let url, !W4ImageLoader.isW4URL(url) {
            PublicProfileAvatarView(url: url, name: name, size: size)
        } else {
            W4AvatarView(url: url, name: name, size: size)
        }
    }
}

/// Larger, non-circular companion used by context-menu image previews.
struct PublicProfilePreviewImage<Placeholder: View>: View {
    let url: URL?
    let w4FallbackURL: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var hasFinishedLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if hasFinishedLoading {
                RateLimitedPreviewImage(url: w4FallbackURL, placeholder: placeholder)
            } else {
                placeholder()
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .task(id: url?.absoluteString) {
            image = nil
            hasFinishedLoading = false
            guard let url else {
                hasFinishedLoading = true
                return
            }
            image = await PublicProfileImageLoader.shared.loadImage(
                from: url,
                maximumPixelSize: 640 * displayScale
            )
            hasFinishedLoading = true
        }
    }
}
