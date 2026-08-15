//
//  CookieManager.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import WebKit

/// Tracks live `WKWebView` instances (e.g. MitID login) so Settings cookie edits apply to each WebView’s `WKHTTPCookieStore`, not only `WKWebsiteDataStore.default()`.
final class LectioActiveWebViewRegistry {
    static let shared = LectioActiveWebViewRegistry()

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

/// Manages cookie extraction, parsing, and HTTP header conversion
class CookieManager {
    static let shared = CookieManager()

    private static let primaryCookieNames: Set<String> = ["ASP.NET_SessionId", "autologinkeyV2"]

    /// Stores that must receive manual Lectio cookie sync (default jar + any live `WKWebView` buckets).
    private func cookieStoresForLectioSync() -> [WKHTTPCookieStore] {
        LectioActiveWebViewRegistry.shared.distinctCookieStoresIncludingDefault()
    }

    private init() {}

    // MARK: - Cookie Extraction from WKWebView

    /// Extracts Lectio credentials from WKWebView cookies
    func extractLectioCredentials(from webView: WKWebView) async throws -> LectioCredentials {
        // Get all cookies from WebView
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await cookieStore.allCookies()

        print("📍 Total cookies found: \(allCookies.count)")

        // Filter for lectio.dk domain
        let lectioCookies = allCookies.filter { cookie in
            cookie.domain.contains("lectio.dk")
        }

        print("📍 Lectio cookies found: \(lectioCookies.count)")
        for cookie in lectioCookies {
            print("  - \(cookie.name) | Domain: \(cookie.domain) | Path: \(cookie.path)")
        }

        // Extract required cookies
        guard let autologinkeyCookie = lectioCookies.first(where: { $0.name == "autologinkeyV2" }),
              let sessionIdCookie = lectioCookies.first(where: { $0.name == "ASP.NET_SessionId" }) else {
            print("❌ Missing required cookies")
            throw LectioError.missingCookies
        }

        // Expiry metadata is best-effort. We don't gate requests on these — they're advisory only.
        // A past date here would not prevent a retry (server rotates cookies on valid autologin).
        let autologinkeyExpiresAt = autologinkeyCookie.expiresDate ?? Date().addingTimeInterval(60 * 60 * 24 * 60)
        let sessionIdExpiresAt = sessionIdCookie.expiresDate ?? Date().addingTimeInterval(60 * 60 * 24 * 60)

        print("✅ Autologinkey expires: \(autologinkeyExpiresAt)")
        print("✅ SessionId expires: \(sessionIdExpiresAt)")

        var additionalCookies: [String: String] = [:]
        for cookie in lectioCookies where !Self.primaryCookieNames.contains(cookie.name) {
            if !cookie.value.isEmpty {
                additionalCookies[cookie.name] = cookie.value
            }
        }

        if additionalCookies["isloggedin3"] == nil {
            additionalCookies["isloggedin3"] = "Y"
            print("📌 Seeded isloggedin3=Y (Dart parity — UniLogin WK snapshot had no isloggedin3)")
        }

        let extraNames = additionalCookies.keys.sorted().joined(separator: ", ")
        print("✅ Additional Lectio cookie names: \(extraNames.isEmpty ? "(none)" : extraNames)")

        return LectioCredentials(
            autologinkey: autologinkeyCookie.value,
            sessionId: sessionIdCookie.value,
            autologinkeyExpiresAt: autologinkeyExpiresAt,
            sessionIdExpiresAt: sessionIdExpiresAt,
            additionalCookies: additionalCookies
        )
    }

    // MARK: - Cookie to HTTP Header Conversion

    /// Converts credentials to Cookie header string for HTTP requests.
    /// Order: `ASP.NET_SessionId` (if non-empty), `autologinkeyV2`, `isloggedin3` (if any), then remaining names sorted.
    func cookieHeader(from credentials: LectioCredentials) -> String {
        var rest = credentials.additionalCookies
        let isloggedin = rest.removeValue(forKey: "isloggedin3")

        var segments: [String] = []
        if !credentials.sessionId.isEmpty {
            segments.append("ASP.NET_SessionId=\(credentials.sessionId)")
        }
        segments.append("autologinkeyV2=\(credentials.autologinkey)")
        if let v = isloggedin {
            segments.append("isloggedin3=\(v)")
        }
        for name in rest.keys.sorted() {
            if let value = rest[name] {
                segments.append("\(name)=\(value)")
            }
        }

        return segments.joined(separator: "; ")
    }

    // MARK: - Parse Set-Cookie Headers

    /// Cookie metadata sent by the server. Values are intentionally redacted.
    func logResponseCookies(from response: HTTPURLResponse) {
        #if DEBUG
        guard let headers = response.allHeaderFields as? [String: String],
              let url = response.url else {
            print("🍪 [response cookies] (invalid response — no headers/URL)")
            return
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        if cookies.isEmpty {
            print("🍪 [response cookies] (none) ← \(LectioRequestLog.compactPath(for: url))")
            return
        }
        let sorted = cookies.sorted { $0.name < $1.name }
        let expiresFormatter = ISO8601DateFormatter()
        print("🍪 [response cookies] \(sorted.count) from \(url.lastPathComponent) ← \(LectioRequestLog.compactPath(for: url))")
        for cookie in sorted {
            let exp = cookie.expiresDate.map { expiresFormatter.string(from: $0) } ?? "session"
            print("  • \(cookie.name)=<redacted>")
            print("    domain=\(cookie.domain) path=\(cookie.path) expires=\(exp) secure=\(cookie.isSecure) httpOnly=\(cookie.isHTTPOnly)")
        }
        #endif
    }

    /// Merges `Set-Cookie` from the response into stored credentials. Returns new credentials when anything changed.
    func updateCredentials(
        from response: HTTPURLResponse,
        currentCredentials: LectioCredentials
    ) -> LectioCredentials? {
        guard let headers = response.allHeaderFields as? [String: String],
              let url = response.url else {
            return nil
        }

        // Only merge cookies from the lectio.dk realm. Redirect chains can hop through
        // broker.unilogin.dk during autologin recovery; cookies set on those hosts have no
        // business in our Lectio cookie jar and would otherwise be re-sent on every lectio.dk
        // request via the manual Cookie header.
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .filter { $0.domain.contains("lectio.dk") }
        if cookies.isEmpty { return nil }

        var autologinkey = currentCredentials.autologinkey
        var sessionId = currentCredentials.sessionId
        var additionalCookies = currentCredentials.additionalCookies
        additionalCookies.removeValue(forKey: "ASP.NET_SessionId")
        additionalCookies.removeValue(forKey: "autologinkeyV2")

        for cookie in cookies {
            switch cookie.name {
            case "autologinkeyV2":
                // Empty value means Lectio is invalidating the autologin (e.g. token-replay
                // detection on a stale snapshot). Don't propagate that into our stored creds —
                // the caller's redirect chain will surface the unauthenticated final URL and
                // we'll throw `.invalidCredentials` from there. Overwriting with "" here would
                // wipe a still-valid keychain token whenever a stale concurrent request races.
                if !cookie.value.isEmpty {
                    autologinkey = cookie.value
                }
            case "ASP.NET_SessionId":
                if !cookie.value.isEmpty {
                    sessionId = cookie.value
                }
            default:
                if cookie.value.isEmpty {
                    additionalCookies.removeValue(forKey: cookie.name)
                } else {
                    additionalCookies[cookie.name] = cookie.value
                }
            }
        }

        let next = LectioCredentials(
            autologinkey: autologinkey,
            sessionId: sessionId,
            autologinkeyExpiresAt: currentCredentials.autologinkeyExpiresAt,
            sessionIdExpiresAt: currentCredentials.sessionIdExpiresAt,
            additionalCookies: additionalCookies
        )
        return next == currentCredentials ? nil : next
    }

    // MARK: - Cookie Validation

    /// Validates cookie expiration
    func isCookieValid(_ cookie: HTTPCookie) -> Bool {
        guard let expiresDate = cookie.expiresDate else {
            return true // No expiration date means session cookie (valid)
        }
        return expiresDate > Date()
    }

    /// Validates credentials expiration
    func areCredentialsValid(_ credentials: LectioCredentials) -> Bool {
        credentials.isValid
    }

    // MARK: - Wipe WebView data

    /// Removes every cookie + storage entry from `WKWebsiteDataStore.default()` — the same
    /// store `LectioWebView` uses for the MitID/UniLogin login flow. Called on logout so
    /// the next login starts from a clean slate; otherwise stale UniLogin session cookies
    /// linger in the WK jar and Lectio rejects the next login attempt.
    func clearAllWebViewData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Remove cookies (Settings / debugging)

    /// Removes `ASP.NET_SessionId` from WebKit cookie stores (default + registered WebViews) and, when `forStudentId` is set, from Keychain `LectioCredentials` for that student.
    func clearASPNETSessionIdEverywhere(forStudentId studentId: String?) async {
        await deleteASPNETSessionIdFromSyncedWebKitStores()

        guard let studentId else {
            print("⚠️ [CookieManager] No student id — keychain session id unchanged")
            return
        }
        guard let creds = KeychainManager.shared.loadCredentials(for: studentId) else {
            print("⚠️ [CookieManager] No keychain credentials for student — only WebKit cookies were cleared")
            return
        }
        let cleared = creds.clearingASPNETSessionId()
        do {
            try KeychainManager.shared.updateCredentials(cleared, for: studentId)
            print("🗑️ Cleared ASP.NET_SessionId from keychain for student \(studentId)")
        } catch {
            print("❌ [CookieManager] Keychain update after session clear failed: \(error.localizedDescription)")
        }
    }

    private func deleteASPNETSessionIdFromSyncedWebKitStores() async {
        let stores = cookieStoresForLectioSync()
        var totalRemoved = 0
        for store in stores {
            let all = await store.allCookies()
            let toDelete = all.filter { $0.name == "ASP.NET_SessionId" && $0.domain.contains("lectio.dk") }
            totalRemoved += toDelete.count
            for cookie in toDelete {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.delete(cookie) {
                        continuation.resume()
                    }
                }
            }
        }
        print("🗑️ Removed \(totalRemoved) ASP.NET_SessionId cookie(s) across \(stores.count) WKHTTPCookieStore(s)")
    }

    /// Replaces `ASP.NET_SessionId` in WebKit cookie stores (default + registered WebViews) and, when keychain creds exist for the student, updates the primary `sessionId` field.
    func setASPNETSessionIdEverywhere(sessionId: String, forStudentId studentId: String?) async {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        await deleteASPNETSessionIdFromSyncedWebKitStores()
        if !trimmed.isEmpty {
            await setASPNETSessionIdInSyncedWebKitStores(value: trimmed)
        }

        guard let studentId else {
            print("⚠️ [CookieManager] No student id — keychain session id not updated")
            return
        }
        guard let creds = KeychainManager.shared.loadCredentials(for: studentId) else {
            print("⚠️ [CookieManager] No keychain credentials — only WebKit cookies were updated")
            return
        }
        let updated: LectioCredentials = trimmed.isEmpty
            ? creds.clearingASPNETSessionId()
            : creds.withASPNETSessionId(trimmed)
        do {
            try KeychainManager.shared.updateCredentials(updated, for: studentId)
            print("🍪 Updated ASP.NET_SessionId in keychain for student \(studentId)")
        } catch {
            print("❌ [CookieManager] Keychain update after set session failed: \(error.localizedDescription)")
        }
    }

    private func setASPNETSessionIdInSyncedWebKitStores(value: String) async {
        guard let cookie = makeLectioASPNETSessionCookie(value: value) else {
            print("❌ [CookieManager] Could not build HTTPCookie for ASP.NET_SessionId")
            return
        }
        let stores = cookieStoresForLectioSync()
        for store in stores {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func makeLectioASPNETSessionCookie(value: String) -> HTTPCookie? {
        let expires = Date().addingTimeInterval(60 * 60 * 24 * 60)
        return HTTPCookie(properties: [
            .name: "ASP.NET_SessionId",
            .value: value,
            .domain: ".lectio.dk",
            .path: "/",
            .secure: true,
            .expires: expires
        ])
    }

    private func deleteAutologinkeyV2FromSyncedWebKitStores() async {
        let stores = cookieStoresForLectioSync()
        var totalRemoved = 0
        for store in stores {
            let all = await store.allCookies()
            let toDelete = all.filter { $0.name == "autologinkeyV2" && $0.domain.contains("lectio.dk") }
            totalRemoved += toDelete.count
            for cookie in toDelete {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    store.delete(cookie) {
                        continuation.resume()
                    }
                }
            }
        }
        print("🗑️ Removed \(totalRemoved) autologinkeyV2 cookie(s) across \(stores.count) WKHTTPCookieStore(s)")
    }

    /// Replaces `autologinkeyV2` in WebKit cookie stores (default + registered WebViews) and, when keychain creds exist for the student, updates the primary `autologinkey` field.
    func setAutologinkeyV2Everywhere(autologinkey: String, forStudentId studentId: String?) async {
        let trimmed = autologinkey.trimmingCharacters(in: .whitespacesAndNewlines)
        await deleteAutologinkeyV2FromSyncedWebKitStores()
        if !trimmed.isEmpty {
            await setAutologinkeyV2InSyncedWebKitStores(value: trimmed)
        }

        guard let studentId else {
            print("⚠️ [CookieManager] No student id — keychain autologinkey not updated")
            return
        }
        guard let creds = KeychainManager.shared.loadCredentials(for: studentId) else {
            print("⚠️ [CookieManager] No keychain credentials — only WebKit cookies were updated")
            return
        }
        let updated: LectioCredentials = trimmed.isEmpty
            ? creds.clearingAutologinkeyV2()
            : creds.withAutologinkeyV2(trimmed)
        do {
            try KeychainManager.shared.updateCredentials(updated, for: studentId)
            print("🍪 Updated autologinkeyV2 in keychain for student \(studentId)")
        } catch {
            print("❌ [CookieManager] Keychain update after set autologinkey failed: \(error.localizedDescription)")
        }
    }

    private func setAutologinkeyV2InSyncedWebKitStores(value: String) async {
        guard let cookie = makeLectioAutologinkeyV2Cookie(value: value) else {
            print("❌ [CookieManager] Could not build HTTPCookie for autologinkeyV2")
            return
        }
        let stores = cookieStoresForLectioSync()
        for store in stores {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func makeLectioAutologinkeyV2Cookie(value: String) -> HTTPCookie? {
        let expires = Date().addingTimeInterval(60 * 60 * 24 * 60)
        return HTTPCookie(properties: [
            .name: "autologinkeyV2",
            .value: value,
            .domain: ".lectio.dk",
            .path: "/",
            .secure: true,
            .expires: expires
        ])
    }

    // MARK: - Debug (Keychain cookie jar)

    /// Prints cookie metadata stored in Keychain without secret values.
    func logKeychainLectioCookies(forStudentId studentId: String?) {
        guard let studentId else {
            print("🔐 [Keychain cookies] Ingen elev — intet at logge")
            return
        }
        guard let creds = KeychainManager.shared.loadCredentials(for: studentId) else {
            print("🔐 [Keychain cookies] Ingen loginoplysninger i nøglering for elev \(studentId)")
            return
        }

        print("🔐 [Keychain cookies] elev \(studentId)")
        print("  ASP.NET_SessionId=<redacted, \(creds.sessionId.count) chars>")
        print("  sessionIdExpiresAt=\(creds.sessionIdExpiresAt)")
        print("  autologinkeyV2=<redacted, \(creds.autologinkey.count) chars>")
        print("  autologinkeyExpiresAt=\(creds.autologinkeyExpiresAt)")
        if creds.additionalCookies.isEmpty {
            print("  additionalCookies: (ingen)")
        } else {
            for name in creds.additionalCookies.keys.sorted() {
                print("  \(name)=<redacted>")
            }
        }
    }
}
