//
//  W4HTTPClient.swift
//  BetterW4
//

import Foundation

// MARK: - W4 wire constants

enum W4UserAgent {
    /// A stable desktop UA. W4 is a 2016-era jQuery app; it renders the same markup for any
    /// desktop browser string, and a stable value keeps the server-side device story boring.
    static let value = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    static let referer = W4Routes.origin
    static let ajax = "XMLHttpRequest"
    static let formURLEncoded = "application/x-www-form-urlencoded; charset=UTF-8"
}

// MARK: - Compact W4 request logging

enum W4RequestLog {
    /// One line: method, compact path, and cookie names only. Credential values must never
    /// be written to device logs because debug builds are routinely distributed to testers.
    static func outbound(method: String, url: URL, cookieHeader: String?) {
        #if DEBUG
        let path = compactPath(for: url)
        let cookieNames = cookieHeader?
            .split(separator: ";")
            .compactMap { $0.split(separator: "=", maxSplits: 1).first }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ",")
        print("📡 W4 \(method) \(path) | cookies=\(cookieNames?.isEmpty == false ? cookieNames! : "none")")
        #endif
    }

    /// Every W4 page lives at `/index.php`, so the route is the only interesting part.
    static func compactPath(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if let route = W4Routes.route(of: url) {
            return "\(host)\(url.path)?r=\(route)"
        }
        return "\(host)\(url.path)"
    }
}

/// Mutable creds + redirect budget for one `URLSessionTask`, so redirect callbacks and the
/// task completion handler see the same jar.
final class W4DataTaskCookieContext {
    private let lock = NSLock()
    private var _creds: W4Credentials
    private var _hops: Int

    var creds: W4Credentials {
        get { lock.lock(); defer { lock.unlock() }; return _creds }
        set { lock.lock(); defer { lock.unlock() }; _creds = newValue }
    }

    /// Redirect hops already spent on this logical request.
    var hops: Int {
        lock.lock(); defer { lock.unlock() }; return _hops
    }

    func consumeHop() -> Int {
        lock.lock(); defer { lock.unlock() }
        _hops += 1
        return _hops
    }

    let studentId: String?
    /// When true the engine may land on `r=site/login` without calling it a dead session.
    /// Only the login / OTP flow sets this.
    let allowLoginPage: Bool
    let onCredentialsUpdated: ((W4Credentials) -> Void)?

    init(
        credentials: W4Credentials,
        studentId: String?,
        allowLoginPage: Bool = false,
        hops: Int = 0,
        onUpdate: ((W4Credentials) -> Void)?
    ) {
        _creds = credentials
        _hops = hops
        self.studentId = studentId
        self.allowLoginPage = allowLoginPage
        self.onCredentialsUpdated = onUpdate
    }
}

private final class W4CancellableTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var isCancelled = false

    func setTask(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }
}

/// Maps each request task to redirect cookie state.
private enum W4URLSessionTaskCookieRegistry {
    private static var map: [ObjectIdentifier: W4DataTaskCookieContext] = [:]
    private static let mapLock = NSLock()

    static func register(_ context: W4DataTaskCookieContext, for task: URLSessionTask) {
        mapLock.lock()
        map[ObjectIdentifier(task)] = context
        mapLock.unlock()
    }

    static func unregister(_ task: URLSessionTask) {
        mapLock.lock()
        map.removeValue(forKey: ObjectIdentifier(task))
        mapLock.unlock()
    }

    static func context(for task: URLSessionTask) -> W4DataTaskCookieContext? {
        mapLock.lock()
        let c = map[ObjectIdentifier(task)]
        mapLock.unlock()
        return c
    }
}

// MARK: - Credential sync (redirect + every response hop)

/// Notifies the caller and writes to Keychain. Only call this when the in-memory jar actually changed —
/// callers gate on `CookieManager.updateCredentials` returning non-nil so we don't churn the keychain
/// or fire `onCredentialsUpdated` for hops that didn't carry `Set-Cookie`.
private func propagateW4CookieContext(_ context: W4DataTaskCookieContext) {
    context.onCredentialsUpdated?(context.creds)
    if let studentId = context.studentId {
        try? KeychainManager.shared.updateCredentials(context.creds, for: studentId)
    }
}

/// Redirect policy (README §4.5 / §5.4, reviewer-notes §2):
/// 1. merge `Set-Cookie` from the hop **first**,
/// 2. if the target is `r=site/login` and the request did not opt into `allowLoginPage`,
///    stop the chain so the caller sees the 302 instead of a 200 full of login HTML,
/// 3. otherwise rewrite the `Cookie` header and continue, capped at 5 hops,
/// 4. a POST followed by 302/303 becomes a GET with no body.
private final class W4URLSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let cookieManager = CookieManager.shared

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let context = W4URLSessionTaskCookieRegistry.context(for: task) else {
            completionHandler(request)
            return
        }

        // 1. Merge this hop's Set-Cookie before deciding anything. PHP regenerates the id on
        //    login, and the follow-up request must carry the new one.
        cookieManager.logResponseCookies(from: response)
        if let updated = cookieManager.updateCredentials(from: response, currentCredentials: context.creds) {
            context.creds = updated
            propagateW4CookieContext(context)
        }

        // 2. A redirect to the login route is the most reliable session-death signal there is.
        //    Auto-following turns it into a 200 of login HTML that every parser then chokes on.
        if let target = request.url, !context.allowLoginPage, W4Routes.isLoginURL(target) {
            completionHandler(nil)
            return
        }

        // 3. Budget.
        guard context.consumeHop() <= W4HTTPClient.maxRedirects else {
            completionHandler(nil)
            return
        }

        var next = request
        // 4. POST + 302/303 → GET. URLSession normally does this itself; be explicit so the
        //    behaviour does not depend on it.
        if response.statusCode == 302 || response.statusCode == 303,
           next.httpMethod?.uppercased() == "POST" {
            next.httpMethod = "GET"
            next.httpBody = nil
            next.setValue(nil, forHTTPHeaderField: "Content-Type")
        }

        let cookie = cookieManager.cookieHeader(from: context.creds)
        let cookieValue: String? = cookie.isEmpty ? nil : cookie
        next.setValue(cookieValue, forHTTPHeaderField: "Cookie")
        if let logURL = next.url ?? request.url {
            W4RequestLog.outbound(method: next.httpMethod ?? "?", url: logURL, cookieHeader: cookie)
        }
        completionHandler(next)
    }
}

/// HTTP client for making authenticated requests to W4.
///
/// Shape follows the Android `W4HttpEngine`: serial limiter, **no** URLSession cookie jar,
/// manual `Cookie:` header, merge non-empty `PHPSESSID` on every hop, manual redirect policy.
class W4HTTPClient {
    private let cookieManager = CookieManager.shared
    private let keychainManager = KeychainManager.shared

    static let maxRedirects = 5
    private let maxAttempts = 3

    /// Serial gate: at most one in-flight `performSingleAttempt` at a time; important tasks queue ahead of opportunistic.
    private static let requestRateLimiter = PriorityRequestLimiter()

    /// Shared URLSession for all W4 traffic. Cookies are fully disabled so the manually-set
    /// Cookie header is the single source of truth — prevents URLSession + HTTPCookieStorage from
    /// silently overriding or merging cookies, which was causing stale cookies to be sent after
    /// app cold-starts (session cookies don't persist in HTTPCookieStorage across app kill).
    private static let sessionDelegate = W4URLSessionDelegate()

    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    // MARK: - Host gate

    /// Every W4 request must go to `w4.uwcrcn.no`. Feature code inherited from BetterLectio
    /// still builds `lectio.dk` URLs, and those must never leave the device: they would carry a
    /// W4 session cookie to a third party and pester an unrelated server with requests it cannot
    /// answer. Anything off-host is a porting bug, so it fails here rather than on the wire —
    /// and it fails with an error that names the problem instead of a bare "HTTP 500".
    static func requireW4Host(_ url: URL, context: String?) throws {
        guard !W4Routes.isW4Host(url.host) else { return }
        print("""
            ⛔️ Refusing a request to a non-W4 host — this surface is not ported to W4 yet.
               host:    \(url.host ?? "(none)")
               path:    \(url.path)
               context: \(context ?? "(unspecified)")
            """)
        throw W4Error.notPortedToW4(host: url.host ?? "unknown", context: context)
    }

    // MARK: - Core Request Logic

    /// Generic request handler for W4.
    ///
    /// `allowLoginPage` lets the login / OTP flow *see* login pages without the engine
    /// classifying them as session expiry. Everything else leaves it false.
    func performRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        contextForLogging: String? = nil,
        priority: FetchPriority = .important,
        allowLoginPage: Bool = false,
        onCredentialsUpdated: ((W4Credentials) -> Void)? = nil
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        try Self.requireW4Host(url, context: contextForLogging)

        var currentCredentials = credentials
        var lastError: Error = W4Error.noResponse

        for attempt in 0..<maxAttempts {
            do {
                let (data, finalCreds, finalURL) = try await performSingleAttempt(
                    url: url,
                    method: method,
                    body: body,
                    headers: headers,
                    credentials: currentCredentials,
                    studentId: studentId,
                    priority: priority,
                    allowLoginPage: allowLoginPage,
                    onCredentialsUpdated: onCredentialsUpdated
                )
                currentCredentials = finalCreds
                let updatedCredentials = currentCredentials != credentials ? currentCredentials : nil
                return (data, updatedCredentials, finalURL)
            } catch let error as W4Error {
                // Classified W4 outcomes are final: retrying a dead session, a wrong role or a
                // server conflict just hammers a tiny Apache box with the same answer.
                error.notifyIfSessionExpired()
                throw error
            } catch let error as URLError
                where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
                && attempt < maxAttempts - 1 {
                print("🔁 Transient network error on attempt \(attempt + 1)/\(maxAttempts) — retrying in 1s")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                lastError = error
            } catch {
                throw error
            }
        }

        throw lastError
    }

    /// `URLSession` follows 3xx; the redirect delegate merges `Set-Cookie` per hop and decides
    /// whether the chain may continue.
    static func dataTaskForW4Request(
        _ request: URLRequest,
        redirectContext: W4DataTaskCookieContext
    ) async throws -> (Data, URLResponse) {
        let taskBox = W4CancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var dataTask: URLSessionDataTask!
                dataTask = sharedSession.dataTask(with: request) { data, response, error in
                    W4URLSessionTaskCookieRegistry.unregister(dataTask)
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: W4Error.noResponse)
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                W4URLSessionTaskCookieRegistry.register(redirectContext, for: dataTask)
                taskBox.setTask(dataTask)
                dataTask.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    /// Streams an on-disk request body instead of materializing it as `Data`.
    static func uploadTaskForW4Request(
        _ request: URLRequest,
        bodyFileURL: URL,
        redirectContext: W4DataTaskCookieContext
    ) async throws -> (Data, URLResponse) {
        let taskBox = W4CancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var uploadTask: URLSessionUploadTask!
                uploadTask = sharedSession.uploadTask(with: request, fromFile: bodyFileURL) { data, response, error in
                    W4URLSessionTaskCookieRegistry.unregister(uploadTask)
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: W4Error.noResponse)
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                W4URLSessionTaskCookieRegistry.register(redirectContext, for: uploadTask)
                taskBox.setTask(uploadTask)
                uploadTask.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    /// Authenticated request whose body is streamed from disk. Used for multipart file uploads —
    /// the mailer allows 5 × 2 MB attachments, which must never be materialised in memory.
    func performFileUploadRequest(
        url: URL,
        bodyFileURL: URL,
        headers: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority = .important
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        try Self.requireW4Host(url, context: "multipart upload")

        var currentCredentials = credentials
        var lastError: Error = W4Error.noResponse

        for attempt in 0..<maxAttempts {
            do {
                let result = try await performSingleFileUploadAttempt(
                    url: url,
                    bodyFileURL: bodyFileURL,
                    headers: headers,
                    credentials: currentCredentials,
                    studentId: studentId,
                    priority: priority
                )
                currentCredentials = result.credentials
                let changed = currentCredentials != credentials
                return (result.data, changed ? currentCredentials : nil, result.finalURL)
            } catch let error as W4Error {
                error.notifyIfSessionExpired()
                throw error
            } catch let error as URLError
                where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
                && attempt < maxAttempts - 1 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                lastError = error
            } catch {
                throw error
            }
        }

        throw lastError
    }

    private func performSingleFileUploadAttempt(
        url: URL,
        bodyFileURL: URL,
        headers: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (data: Data, credentials: W4Credentials, finalURL: URL) {
        try await Self.withSerialW4Request(priority: priority) {
            var currentCredentials = studentId.flatMap { keychainManager.loadCredentials(for: $0) } ?? credentials
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            applyBaseHeaders(to: &request, credentials: currentCredentials, extra: headers)

            W4RequestLog.outbound(method: "POST", url: url, cookieHeader: request.value(forHTTPHeaderField: "Cookie"))
            let context = W4DataTaskCookieContext(
                credentials: currentCredentials,
                studentId: studentId,
                allowLoginPage: false,
                onUpdate: nil
            )
            let (data, response) = try await Self.uploadTaskForW4Request(
                request,
                bodyFileURL: bodyFileURL,
                redirectContext: context
            )
            currentCredentials = context.creds

            guard let httpResponse = response as? HTTPURLResponse else { throw W4Error.noResponse }
            if let updated = cookieManager.updateCredentials(from: httpResponse, currentCredentials: currentCredentials) {
                currentCredentials = updated
                if let studentId { try? keychainManager.updateCredentials(updated, for: studentId) }
            }
            let finalURL = httpResponse.url ?? url

            switch try classify(
                response: httpResponse,
                data: data,
                requestURL: url,
                finalURL: finalURL,
                allowLoginPage: false
            ) {
            case .success:
                return (data, currentCredentials, finalURL)
            case .redirect:
                // The delegate already followed every legitimate hop (the mailer answers
                // 302 → sent folder on success). A redirect still standing here means the
                // chain was cut: login target, or the 5-hop budget ran out.
                print("❌ Upload redirect chain exhausted — treating as session expired")
                throw W4Error.sessionExpired
            }
        }
    }

    /// A single request attempt, serialized with other W4 requests.
    private func performSingleAttempt(
        url: URL,
        method: String,
        body: Data?,
        headers: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority,
        allowLoginPage: Bool,
        onCredentialsUpdated: ((W4Credentials) -> Void)? = nil
    ) async throws -> (data: Data, credentials: W4Credentials, finalURL: URL) {
        try await withSerialW4Request(priority: priority) {
            // Re-read the freshest credentials from the keychain right before sending. Between
            // when the caller invoked performRequest (snapshotting `credentials`) and now, a
            // concurrent request may have rotated PHPSESSID and written the new value to the
            // keychain. The rate limiter serializes us, so any prior request's keychain update
            // is already visible by the time we get here.
            var currentCredentials = studentId.flatMap { keychainManager.loadCredentials(for: $0) } ?? credentials
            var currentURL = url
            var currentMethod = method
            var currentBody = body
            var redirectCount = 0

            while redirectCount <= Self.maxRedirects {
                var request = URLRequest(url: currentURL)
                request.httpMethod = currentMethod
                request.httpBody = currentBody
                applyBaseHeaders(
                    to: &request,
                    credentials: currentCredentials,
                    extra: headers,
                    hasBody: currentBody != nil
                )

                W4RequestLog.outbound(
                    method: currentMethod,
                    url: currentURL,
                    cookieHeader: request.value(forHTTPHeaderField: "Cookie")
                )

                let redirectContext = W4DataTaskCookieContext(
                    credentials: currentCredentials,
                    studentId: studentId,
                    allowLoginPage: allowLoginPage,
                    hops: redirectCount,
                    onUpdate: onCredentialsUpdated
                )
                let (data, response) = try await Self.dataTaskForW4Request(request, redirectContext: redirectContext)
                currentCredentials = redirectContext.creds
                redirectCount = redirectContext.hops

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw W4Error.noResponse
                }

                cookieManager.logResponseCookies(from: httpResponse)
                if let updatedCreds = cookieManager.updateCredentials(from: httpResponse, currentCredentials: currentCredentials) {
                    currentCredentials = updatedCreds
                    onCredentialsUpdated?(currentCredentials)
                    if let studentId {
                        try? keychainManager.updateCredentials(currentCredentials, for: studentId)
                    }
                }

                let finalURL = httpResponse.url ?? currentURL
                switch try classify(
                    response: httpResponse,
                    data: data,
                    requestURL: currentURL,
                    finalURL: finalURL,
                    allowLoginPage: allowLoginPage
                ) {
                case .success:
                    return (data, currentCredentials, finalURL)

                case .redirect(let target, let becomesGET):
                    if redirectCount >= Self.maxRedirects {
                        print("❌ Exceeded \(Self.maxRedirects) redirects — treating as session expired")
                        throw W4Error.sessionExpired
                    }
                    if becomesGET {
                        currentMethod = "GET"
                        currentBody = nil
                    }
                    currentURL = target
                    redirectCount += 1
                }
            }

            print("❌ Redirect loop exhausted — treating as session expired")
            throw W4Error.sessionExpired
        }
    }

    // MARK: - Session classification (README §4.5)

    private enum W4ResponseOutcome {
        case success
        case redirect(target: URL, becomesGET: Bool)
    }

    /// Every distinct session signal maps to a distinct typed error. Getting `.forbidden`
    /// wrong means a student who opens a staff-only page gets kicked to the login screen.
    private func classify(
        response: HTTPURLResponse,
        data: Data,
        requestURL: URL,
        finalURL: URL,
        allowLoginPage: Bool
    ) throws -> W4ResponseOutcome {
        switch response.statusCode {
        case 200...299:
            if !allowLoginPage {
                // Signal 1 (a 302 the delegate refused to follow can also surface here if the
                // server answered 200 at the login route) and signal 2 (login HTML).
                if W4Routes.isLoginURL(finalURL) {
                    print("❌ Landed on r=site/login — session expired")
                    throw W4Error.sessionExpired
                }
                if shouldClassifyBody(of: response), W4Html.isLoginHTML(decodeHTML(from: data)) {
                    print("❌ Body is the login form — session expired")
                    throw W4Error.sessionExpired
                }
            }
            return .success

        case 300...399:
            guard let location = response.value(forHTTPHeaderField: "Location"),
                  let target = URL(string: location, relativeTo: requestURL)?.absoluteURL else {
                throw W4Error.invalidURL
            }
            if !allowLoginPage, W4Routes.isLoginURL(target) {
                print("❌ Redirect to r=site/login — session expired")
                throw W4Error.sessionExpired
            }
            let becomesGET = response.statusCode == 302 || response.statusCode == 303
            return .redirect(target: target, becomesGET: becomesGET)

        case 401, 403:
            // W4's own init_ajax.js rule: 403 + "Login Required" is a dead session,
            // any other 403 means signed in with the wrong role.
            if W4Html.isAjaxLoginRequired(decodeHTML(from: data)) {
                print("❌ 403 Login Required — session expired")
                throw W4Error.sessionExpired
            }
            throw W4Error.forbidden

        case 409:
            let message = decodeHTML(from: data).trimmingCharacters(in: .whitespacesAndNewlines)
            throw W4Error.serverConflict(message)

        default:
            let route = W4Routes.route(of: finalURL) ?? W4Routes.route(of: requestURL) ?? ""
            // A bare "HTTP 500" is unactionable with many surfaces in flight, and W4 renders
            // its PHP errors into the body — log a bounded excerpt so the cause is visible.
            let body = shouldClassifyBody(of: response)
                ? decodeHTML(from: data).trimmingCharacters(in: .whitespacesAndNewlines)
                : "(non-text body)"
            print("""
                ❌ W4 HTTP \(response.statusCode)
                   route:  \(route.isEmpty ? finalURL.absoluteString : route)
                   body:   \(body.prefix(500))
                """)
            throw W4Error.httpError(status: response.statusCode, route: route)
        }
    }

    /// Skip body sniffing for binaries — photos, PDFs and the 600 KB Letter of Attendance
    /// should never be decoded into a String just to look for a login form.
    private func shouldClassifyBody(of response: HTTPURLResponse) -> Bool {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
            return true
        }
        return contentType.contains("html")
            || contentType.contains("text")
            || contentType.contains("json")
            || contentType.contains("xml")
    }

    // MARK: - Headers

    private func applyBaseHeaders(
        to request: inout URLRequest,
        credentials: W4Credentials,
        extra: [String: String],
        hasBody: Bool = false
    ) {
        let cookie = cookieManager.cookieHeader(from: credentials)
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.setValue(W4UserAgent.value, forHTTPHeaderField: "User-Agent")
        request.setValue(W4UserAgent.referer, forHTTPHeaderField: "Referer")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

        let extraKeys = Set(extra.keys.map { $0.lowercased() })
        if !extraKeys.contains("accept") {
            request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        if hasBody, !extraKeys.contains("content-type") {
            request.setValue(W4UserAgent.formURLEncoded, forHTTPHeaderField: "Content-Type")
        }

        for (key, value) in extra where key.lowercased() != "cookie" {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    static func withSerialW4Request<T>(
        priority: FetchPriority,
        _ body: () async throws -> T
    ) async throws -> T {
        try await requestRateLimiter.begin(priority: priority)
        do {
            let value = try await body()
            await requestRateLimiter.end()
            return value
        } catch {
            await requestRateLimiter.end()
            throw error
        }
    }

    private func withSerialW4Request<T>(
        priority: FetchPriority,
        _ body: () async throws -> T
    ) async throws -> T {
        try await Self.withSerialW4Request(priority: priority, body)
    }

    /// Legacy wrapper for fetchWithCookies
    func fetchWithCookies(
        url: URL,
        credentials: W4Credentials,
        studentId: String?,
        contextForLogging: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        try await performRequest(
            url: url,
            method: "GET",
            credentials: credentials,
            studentId: studentId,
            contextForLogging: contextForLogging,
            priority: priority
        )
    }

    // MARK: - Route conveniences

    /// `GET index.php?r={route}&…`
    func get(
        route: String,
        query: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority = .important,
        allowLoginPage: Bool = false
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        try await performRequest(
            url: W4Routes.url(route, query),
            method: "GET",
            credentials: credentials,
            studentId: studentId,
            contextForLogging: route,
            priority: priority,
            allowLoginPage: allowLoginPage
        )
    }

    /// Standard Yii 1 form POST — `application/x-www-form-urlencoded`, cookie auth only.
    /// W4 has no CSRF token on any student form (README §3).
    func postForm(
        route: String,
        fields: [String: String],
        query: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority = .important,
        allowLoginPage: Bool = false
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        let url = W4Routes.url(route, query)
        return try await performRequest(
            url: url,
            method: "POST",
            body: W4Form.encode(fields),
            headers: [
                "Content-Type": W4UserAgent.formURLEncoded,
                "Referer": url.absoluteString
            ],
            credentials: credentials,
            studentId: studentId,
            contextForLogging: route,
            priority: priority,
            allowLoginPage: allowLoginPage
        )
    }

    /// Standard form POST retaining duplicate field names and browser order.
    func postForm(
        route: String,
        fields: [(String, String)],
        query: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority = .important,
        allowLoginPage: Bool = false
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        let url = W4Routes.url(route, query)
        return try await performRequest(
            url: url,
            method: "POST",
            body: W4Form.encode(fields),
            headers: [
                "Content-Type": W4UserAgent.formURLEncoded,
                "Referer": url.absoluteString
            ],
            credentials: credentials,
            studentId: studentId,
            contextForLogging: route,
            priority: priority,
            allowLoginPage: allowLoginPage
        )
    }

    /// jQuery-shaped POST: W4's `$.post` handlers (campus status, notifications) branch on
    /// `X-Requested-With` and answer with an HTML fragment plus the 403/409 codes from §5.3.
    func postAjax(
        route: String,
        fields: [String: String],
        query: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority = .important
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        let url = W4Routes.url(route, query)
        return try await performRequest(
            url: url,
            method: "POST",
            body: W4Form.encode(fields),
            headers: [
                "Content-Type": W4UserAgent.formURLEncoded,
                "X-Requested-With": W4UserAgent.ajax,
                "Accept": "*/*",
                "Referer": url.absoluteString
            ],
            credentials: credentials,
            studentId: studentId,
            contextForLogging: route,
            priority: priority
        )
    }

    /// GETs a Yii page, harvests the form's own hidden fields plus the clicked submit button,
    /// merges `extra` over them and POSTs the lot back. This is the Yii analogue of an
    /// ASP.NET postback — minus `__VIEWSTATE`, since Yii forms carry almost nothing.
    func postYiiForm(
        route: String,
        extra: [String: String] = [:],
        submitName: String = "yt0",
        submitValue: String? = nil,
        formSelector: String? = nil,
        query: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority = .important
    ) async throws -> (data: Data, updatedCredentials: W4Credentials?, finalURL: URL) {
        let opened = try await get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        let credentialsAfterGET = opened.updatedCredentials ?? credentials
        let html = decodeHTML(from: opened.data)
        let fields = YiiForm.fieldsForSubmit(
            html: html,
            extra: extra,
            submitName: submitName,
            submitValue: submitValue,
            formSelector: formSelector
        )

        // Post to the form's own action when it declares one; Yii usually omits it, which
        // means "post back to the page you are on". A declared action is relative to that
        // same page (`index.php?r=…`), not to the origin.
        let parsed = YiiForm.parse(html, formSelector: formSelector)
        let target: URL
        if let action = parsed.action, !action.isEmpty {
            if let absolute = URL(string: action), absolute.scheme != nil, absolute.host != nil {
                target = absolute
            } else {
                target = URL(string: action, relativeTo: opened.finalURL)?.absoluteURL ?? opened.finalURL
            }
        } else {
            target = opened.finalURL
        }

        let posted = try await performRequest(
            url: target,
            method: "POST",
            body: W4Form.encode(fields),
            headers: [
                "Content-Type": W4UserAgent.formURLEncoded,
                "Referer": opened.finalURL.absoluteString
            ],
            credentials: credentialsAfterGET,
            studentId: studentId,
            contextForLogging: route,
            priority: priority
        )
        return (posted.data, posted.updatedCredentials ?? opened.updatedCredentials, posted.finalURL)
    }

    // MARK: - Helpers

    func decodeHTML(from data: Data) -> String {
        // W4 serves XHTML 1.0 Transitional, charset=utf-8. The Latin-1 fallback only matters
        // for the odd legacy attachment name.
        if let html = String(data: data, encoding: .utf8) {
            return html
        }
        if let html = String(data: data, encoding: .isoLatin1) {
            return html
        }
        return String(decoding: data, as: UTF8.self)
    }

    func formURLEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - Fetch Priority

enum FetchPriority {
    case important
    case opportunistic
}

// MARK: - Priority Request Limiter (serial + cooldown)

/// Serializes W4 HTTP attempts AND enforces a minimum gap between consecutive requests.
/// W4 runs on one small Apache box for ~200 students (README §5.5); a native client that
/// fans out requests is the rudest thing it could do. Spacing them also gives each hop's
/// `Set-Cookie` time to land in the keychain before the next request reads it.
private actor PriorityRequestLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var busy = false
    private var importantWaiters: [Waiter] = []
    private var opportunisticWaiters: [Waiter] = []
    private var cancelledWaiterIDs: Set<UUID> = []
    private var pendingAcquisitionIDs: Set<UUID> = []
    private var lastEndedAt: Date?
    private let minIntervalNanos: UInt64 = 100_000_000

    func begin(priority: FetchPriority) async throws {
        try Task.checkCancellation()
        let waiterID = UUID()
        pendingAcquisitionIDs.insert(waiterID)
        let acquired = await withTaskCancellationHandler {
            await acquireSlot(priority: priority, waiterID: waiterID)
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
        pendingAcquisitionIDs.remove(waiterID)
        cancelledWaiterIDs.remove(waiterID)
        guard acquired else { throw CancellationError() }

        do {
            try Task.checkCancellation()
            try await waitForCooldown()
        } catch {
            end()
            throw error
        }
    }

    private func acquireSlot(priority: FetchPriority, waiterID: UUID) async -> Bool {
        if cancelledWaiterIDs.remove(waiterID) != nil || Task.isCancelled {
            return false
        }

        switch priority {
        case .important:
            if !busy {
                busy = true
                return true
            }
            return await withCheckedContinuation { continuation in
                importantWaiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        case .opportunistic:
            if !busy && importantWaiters.isEmpty {
                busy = true
                return true
            }
            return await withCheckedContinuation { continuation in
                opportunisticWaiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard pendingAcquisitionIDs.contains(id) else { return }
        if let index = importantWaiters.firstIndex(where: { $0.id == id }) {
            importantWaiters.remove(at: index).continuation.resume(returning: false)
            return
        }
        if let index = opportunisticWaiters.firstIndex(where: { $0.id == id }) {
            opportunisticWaiters.remove(at: index).continuation.resume(returning: false)
            return
        }
        cancelledWaiterIDs.insert(id)
    }

    private func waitForCooldown() async throws {
        guard let lastEndedAt else { return }
        let elapsedSeconds = max(0, Date().timeIntervalSince(lastEndedAt))
        let elapsedNanos = UInt64(elapsedSeconds * 1_000_000_000)
        if elapsedNanos < minIntervalNanos {
            try await Task.sleep(nanoseconds: minIntervalNanos - elapsedNanos)
        }
    }

    func end() {
        lastEndedAt = Date()
        if !importantWaiters.isEmpty {
            let next = importantWaiters.removeFirst()
            next.continuation.resume(returning: true)
            return
        }
        if !opportunisticWaiters.isEmpty {
            let next = opportunisticWaiters.removeFirst()
            next.continuation.resume(returning: true)
            return
        }
        busy = false
    }
}
