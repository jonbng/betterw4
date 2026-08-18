//
//  CookieManager.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import WebKit

/// Tracks live `WKWebView` instances so a session sync reaches each WebView's own
/// `WKHTTPCookieStore`, not only `WKWebsiteDataStore.default()`.
///
/// Login itself is native (no WebView), but W4's CMS pages — Documents, subject pages,
/// the Letter of Attendance — are plain authenticated HTML that is far cheaper to render
/// in a WebView than to reparse, and those WebViews need `PHPSESSID`.
final class W4ActiveWebViewRegistry {
    static let shared = W4ActiveWebViewRegistry()

    private let lock = NSLock()
    private let webViews = NSHashTable<WKWebView>.weakObjects()

    private init() {}

    func add(_ webView: WKWebView) {
        lock.lock()
        defer { lock.unlock() }
        webViews.add(webView)
    }

    func remove(_ webView: WKWebView) {
        lock.lock()
        defer { lock.unlock() }
        webViews.remove(webView)
    }

    /// Default persistent store plus any distinct stores from registered WebViews (reference-uniqued).
    @MainActor
    func distinctCookieStoresIncludingDefault() -> [WKHTTPCookieStore] {
        lock.lock()
        defer { lock.unlock() }
        let defaultStore = WKWebsiteDataStore.default().httpCookieStore
        var stores: [WKHTTPCookieStore] = [defaultStore]
        for webView in webViews.allObjects {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            if !stores.contains(where: { $0 === store }) {
                stores.append(store)
            }
        }
        return stores
    }
}

/// W4's cookie jar. Exactly one cookie exists — `PHPSESSID` (README §4.1) — so this type
/// only ever merges, formats and reports that single name. Values are never logged.
class CookieManager {
    static let shared = CookieManager()

    /// W4's only cookie.
    static let sessionCookieName = "PHPSESSID"

    private init() {}

    // MARK: - Cookie to HTTP Header Conversion

    /// `PHPSESSID=…`, plus any other cookie W4 has issued (a "remember this device" cookie, for
    /// instance). Empty when we have no session yet, e.g. the very first GET of the login page —
    /// callers must not send an empty `Cookie:` header.
    ///
    /// Sorted by name so the header is deterministic, which makes it testable and keeps request
    /// logs comparable between runs.
    func cookieHeader(from credentials: W4Credentials) -> String {
        var pairs: [String] = []
        if !credentials.sessionId.isEmpty {
            pairs.append("\(Self.sessionCookieName)=\(credentials.sessionId)")
        }
        for name in credentials.additionalCookies.keys.sorted() {
            guard let value = credentials.additionalCookies[name], !value.isEmpty else { continue }
            pairs.append("\(name)=\(value)")
        }
        return pairs.joined(separator: "; ")
    }

    // MARK: - Parse Set-Cookie Headers

    /// Cookie metadata sent by the server. Names only — values are never written to device
    /// logs, because debug builds are routinely distributed to testers.
    func logResponseCookies(from response: HTTPURLResponse) {
        #if DEBUG
        guard let headers = response.allHeaderFields as? [String: String],
              let url = response.url else {
            print("🍪 [response cookies] (invalid response — no headers/URL)")
            return
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        if cookies.isEmpty { return }
        let names = cookies.map(\.name).sorted().joined(separator: ",")
        print("🍪 [response cookies] \(names) ← \(W4RequestLog.compactPath(for: url))")
        #endif
    }

    /// Merges `Set-Cookie` from one response hop into the jar. Returns new credentials when
    /// anything changed, otherwise nil so callers can skip a Keychain write.
    ///
    /// PHP regenerates the session id on login (`session_regenerate_id`), so a non-empty
    /// value always wins. An **empty** value is ignored rather than stored: wiping a live
    /// session id because one hop echoed a blank cookie is exactly the bug Lectio taught us.
    func updateCredentials(
        from response: HTTPURLResponse,
        currentCredentials: W4Credentials
    ) -> W4Credentials? {
        guard let headers = response.allHeaderFields as? [String: String],
              let url = response.url,
              W4Routes.isW4Host(url.host) else {
            return nil
        }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .filter { Self.isW4CookieDomain($0.domain) }
        guard !cookies.isEmpty else { return nil }

        var sessionId = currentCredentials.sessionId
        var extras = currentCredentials.additionalCookies

        for cookie in cookies {
            if cookie.name == Self.sessionCookieName {
                // Empty means "the server said nothing on this hop", not "log out".
                if !cookie.value.isEmpty { sessionId = cookie.value }
                continue
            }

            guard !W4Credentials.refusedNames.contains(cookie.name) else { continue }

            if cookie.value.isEmpty {
                // An explicit blanking IS meaningful for a non-session cookie: it is how a server
                // revokes a remember-me token. Honour it rather than clinging to a dead value.
                extras.removeValue(forKey: cookie.name)
            } else {
                extras[cookie.name] = cookie.value
            }
        }

        guard sessionId != currentCredentials.sessionId || extras != currentCredentials.additionalCookies else {
            return nil
        }
        return W4Credentials(sessionId: sessionId, additionalCookies: extras)
    }

    /// W4 sets the cookie without a `Domain=` attribute, so `HTTPCookie` reports the
    /// host itself; tolerate a leading dot in case that ever changes.
    private static func isW4CookieDomain(_ domain: String) -> Bool {
        var host = domain.lowercased()
        if host.hasPrefix(".") { host.removeFirst() }
        return W4Routes.isW4Host(host)
    }

    // MARK: - WebView session sync

    /// Reads `PHPSESSID` out of a `WKWebView`'s cookie store. W4's cookie is **not**
    /// `HttpOnly`, so this works — used when a WebView flow (CMS page) rotates the session.
    @MainActor
    func extractW4Credentials(from webView: WKWebView) async throws -> W4Credentials {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let sessionCookie = await cookieStore.allCookies().first {
            $0.name == Self.sessionCookieName && Self.isW4CookieDomain($0.domain)
        }
        guard let sessionCookie, !sessionCookie.value.isEmpty else {
            print("❌ [CookieManager] No \(Self.sessionCookieName) in the WebView cookie store")
            throw W4Error.missingCookies
        }
        return W4Credentials(sessionId: sessionCookie.value)
    }

    /// Pushes the native `PHPSESSID` into every WebKit cookie store so an authenticated
    /// `WKWebView` (Documents / subject pages / Letter of Attendance) loads signed in.
    @MainActor
    func syncCredentialsToWebViews(_ credentials: W4Credentials) async {
        await removeSessionCookieFromWebViews()
        guard !credentials.sessionId.isEmpty,
              let cookie = Self.makeSessionCookie(value: credentials.sessionId) else { return }

        for store in W4ActiveWebViewRegistry.shared.distinctCookieStoresIncludingDefault() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }

    /// Removes `PHPSESSID` from every WebKit cookie store.
    @MainActor
    func removeSessionCookieFromWebViews() async {
        let stores = W4ActiveWebViewRegistry.shared.distinctCookieStoresIncludingDefault()
        var removed = 0
        for store in stores {
            let stale = await store.allCookies().filter {
                $0.name == Self.sessionCookieName && Self.isW4CookieDomain($0.domain)
            }
            removed += stale.count
            for cookie in stale {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.delete(cookie) { continuation.resume() }
                }
            }
        }
        print("🗑️ Removed \(removed) \(Self.sessionCookieName) cookie(s) across \(stores.count) WKHTTPCookieStore(s)")
    }

    private static func makeSessionCookie(value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .name: sessionCookieName,
            .value: value,
            // Host-only, exactly as W4 sets it: no `Domain=`, path `/`, `Secure`,
            // and a session lifetime (no expiry date).
            .domain: W4Routes.host,
            .path: "/",
            .secure: true
        ])
    }

    // MARK: - Wipe WebView data

    /// Removes every cookie + storage entry from `WKWebsiteDataStore.default()`.
    /// Called on logout so no residual session lingers for the next account.
    ///
    /// `@MainActor` is load-bearing: WebKit traps if its data stores are touched off the main
    /// thread, and this runs from cold-start restore, which is not main-isolated in Swift 5 mode.
    @MainActor
    func clearAllWebViewData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Debug (Keychain cookie jar)

    /// Prints what the Keychain holds for a student — cookie name and value length only.
    func logKeychainW4Cookies(forStudentId studentId: String?) {
        guard let studentId else {
            print("🔐 [Keychain cookies] No student — nothing to log")
            return
        }
        guard let creds = KeychainManager.shared.loadCredentials(for: studentId) else {
            print("🔐 [Keychain cookies] No stored credentials for student \(studentId)")
            return
        }
        print("🔐 [Keychain cookies] student \(studentId)")
        print("  \(Self.sessionCookieName)=<redacted, \(creds.sessionId.count) chars>")
    }
}
