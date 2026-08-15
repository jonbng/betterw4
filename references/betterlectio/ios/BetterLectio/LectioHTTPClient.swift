//
//  LectioHTTPClient.swift
//  BetterLectio
//

import Foundation

// MARK: - Compact Lectio request logging

enum LectioRequestLog {
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
        print("📡 Lectio \(method) \(path) | cookies=\(cookieNames?.isEmpty == false ? cookieNames! : "none")")
        #endif
    }

    static func compactPath(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if host.contains("lectio.dk") {
            return url.path.isEmpty ? "lectio.dk/" : url.path
        }
        return "\(host)\(url.path)"
    }
}

/// Mutable creds for one `URLSessionDataTask` so redirect callbacks and `dataTask` completion see the same jar.
final class LectioDataTaskCookieContext {
    private let lock = NSLock()
    private var _creds: LectioCredentials
    var creds: LectioCredentials {
        get { lock.lock(); defer { lock.unlock() }; return _creds }
        set { lock.lock(); defer { lock.unlock() }; _creds = newValue }
    }
    let studentId: String?
    let onCredentialsUpdated: ((LectioCredentials) -> Void)?

    init(credentials: LectioCredentials, studentId: String?, onUpdate: ((LectioCredentials) -> Void)?) {
        _creds = credentials
        self.studentId = studentId
        self.onCredentialsUpdated = onUpdate
    }
}

private final class LectioCancellableTaskBox: @unchecked Sendable {
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
private enum LectioURLSessionTaskCookieRegistry {
    private static var map: [ObjectIdentifier: LectioDataTaskCookieContext] = [:]
    private static let mapLock = NSLock()

    static func register(_ context: LectioDataTaskCookieContext, for task: URLSessionTask) {
        mapLock.lock()
        map[ObjectIdentifier(task)] = context
        mapLock.unlock()
    }

    static func unregister(_ task: URLSessionTask) {
        mapLock.lock()
        map.removeValue(forKey: ObjectIdentifier(task))
        mapLock.unlock()
    }

    static func context(for task: URLSessionTask) -> LectioDataTaskCookieContext? {
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
private func propagateLectioCookieContext(_ context: LectioDataTaskCookieContext) {
    context.onCredentialsUpdated?(context.creds)
    if let studentId = context.studentId {
        try? KeychainManager.shared.updateCredentials(context.creds, for: studentId)
    }
}

/// True when the URL is on the UniLogin broker host — a definitive logout signal.
/// Authenticated Lectio API calls never legitimately land on broker.unilogin.dk; any
/// redirect or final URL on this host means the autologin is dead. Host alone, no path
/// constraint — UniLogin's flow can route through several paths (auth/realms, broker
/// selection, SAML callbacks) and any of them are equally definitive.
func isLectioUniLoginURL(_ url: URL) -> Bool {
    (url.host ?? "").lowercased().contains("broker.unilogin.dk")
}

/// Follows redirects; when a task is registered, merges `Set-Cookie` from *each* hop and refreshes the follow-up `Cookie` header.
private final class LectioURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let cookieManager = CookieManager.shared

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let from = response.url.map { LectioRequestLog.compactPath(for: $0) } ?? "(unknown)"
        let locationHeader = response.value(forHTTPHeaderField: "Location").flatMap { raw in
            URL(string: raw, relativeTo: response.url).map { LectioRequestLog.compactPath(for: $0) }
        }
        let to = request.url.map { LectioRequestLog.compactPath(for: $0) } ?? "(unknown)"
        print("🔀 [redirect] HTTP \(response.statusCode) from \(from)")
        if let loc = locationHeader {
            print("🔀 [redirect] Location: \(loc)")
        }
        print("🔀 [redirect] session will follow → \(to)")

        // Definitive logout signal: any redirect to broker.unilogin.dk means the autologin is
        // dead. Post `.lectioSessionExpired` immediately so the login screen appears now,
        // instead of waiting for the request to finish and the retry loop to exhaust.
        if let target = request.url, isLectioUniLoginURL(target) {
            print("❌ Redirect to UniLogin broker — posting sessionExpired immediately")
            NotificationCenter.default.post(name: .lectioSessionExpired, object: nil)
        }

        guard let context = LectioURLSessionTaskCookieRegistry.context(for: task) else {
            completionHandler(request)
            return
        }

        cookieManager.logResponseCookies(from: response)
        if let updated = cookieManager.updateCredentials(from: response, currentCredentials: context.creds) {
            context.creds = updated
            propagateLectioCookieContext(context)
        }
        var next = request
        let cookie = cookieManager.cookieHeader(from: context.creds)
        next.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let logURL = next.url ?? request.url {
            LectioRequestLog.outbound(method: next.httpMethod ?? "?", url: logURL, cookieHeader: cookie)
        }
        completionHandler(next)
    }
}

/// HTTP client for making authenticated requests to Lectio
class LectioHTTPClient {
    private let cookieManager = CookieManager.shared
    private let keychainManager = KeychainManager.shared

    private let maxRedirects = 5
    private let maxAttempts = 3

    /// Serial gate: at most one in-flight `performSingleAttempt` at a time; important tasks queue ahead of opportunistic.
    private static let requestRateLimiter = PriorityRequestLimiter()

    /// Shared URLSession for all Lectio traffic. Cookies are fully disabled so the manually-set
    /// Cookie header is the single source of truth — prevents URLSession + HTTPCookieStorage from
    /// silently overriding or merging cookies, which was causing stale cookies to be sent after
    /// app cold-starts (session cookies don't persist in HTTPCookieStorage across app kill).
    private static let sessionDelegate = LectioURLSessionDelegate()

    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    // MARK: - Core Request Logic

    /// Generic request handler for Lectio
    func performRequest(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        credentials: LectioCredentials,
        studentId: String?,
        contextForLogging: String? = nil,
        priority: FetchPriority = .important,
        onCredentialsUpdated: ((LectioCredentials) -> Void)? = nil
    ) async throws -> (data: Data, updatedCredentials: LectioCredentials?, finalURL: URL) {
        var currentCredentials = credentials
        var lastError: Error = LectioError.noResponse

        // Retry loop: transient failures (auth blips, robot detection, network hiccups) never wipe
        // credentials. Always worth another try — Lectio frequently rotates cookies on retry.
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
                    onCredentialsUpdated: onCredentialsUpdated
                )
                currentCredentials = finalCreds
                let updatedCredentials = (currentCredentials.autologinkey != credentials.autologinkey ||
                                          currentCredentials.sessionId != credentials.sessionId ||
                                          currentCredentials.additionalCookies != credentials.additionalCookies) ? currentCredentials : nil
                return (data, updatedCredentials, finalURL)
            } catch LectioError.invalidCredentials where attempt < maxAttempts - 1 {
                let delay: UInt64 = attempt == 0 ? 500_000_000 : 1_500_000_000
                print("🔁 Auth failure on attempt \(attempt + 1)/\(maxAttempts) — retrying in \(Double(delay) / 1e9)s")
                try await Task.sleep(nanoseconds: delay)
                lastError = LectioError.invalidCredentials
            } catch LectioError.robotDetection where attempt < maxAttempts - 1 {
                // Robot detection is literally the server's rate-limit response — give it room.
                let jitter = UInt64.random(in: 0...1_500_000_000)
                let delay: UInt64 = 3_000_000_000 + jitter
                print("🔁 Robot detection on attempt \(attempt + 1)/\(maxAttempts) — backing off \(Double(delay) / 1e9)s")
                try await Task.sleep(nanoseconds: delay)
                lastError = LectioError.robotDetection
            } catch let e as URLError where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(e.code) && attempt < maxAttempts - 1 {
                print("🔁 Transient network error on attempt \(attempt + 1)/\(maxAttempts) — retrying in 1s")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                lastError = e
            } catch {
                throw error
            }
        }

        // Single source of truth for posting `.lectioSessionExpired`: any path that exhausts
        // here with `.invalidCredentials` triggers logout, so individual call sites do not
        // need to remember to forward the signal.
        (lastError as? LectioError)?.notifyIfSessionExpired()
        throw lastError
    }

    /// `URLSession` follows 3xx automatically; the redirect delegate merges `Set-Cookie` per hop when a context is registered.
    static func dataTaskForLectioRequest(
        _ request: URLRequest,
        redirectContext: LectioDataTaskCookieContext
    ) async throws -> (Data, URLResponse) {
        let taskBox = LectioCancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var dataTask: URLSessionDataTask!
                dataTask = sharedSession.dataTask(with: request) { data, response, error in
                    LectioURLSessionTaskCookieRegistry.unregister(dataTask)
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: LectioError.noResponse)
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                LectioURLSessionTaskCookieRegistry.register(redirectContext, for: dataTask)
                taskBox.setTask(dataTask)
                dataTask.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    /// Streams an on-disk request body instead of materializing it as `Data`.
    static func uploadTaskForLectioRequest(
        _ request: URLRequest,
        bodyFileURL: URL,
        redirectContext: LectioDataTaskCookieContext
    ) async throws -> (Data, URLResponse) {
        let taskBox = LectioCancellableTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var uploadTask: URLSessionUploadTask!
                uploadTask = sharedSession.uploadTask(with: request, fromFile: bodyFileURL) { data, response, error in
                    LectioURLSessionTaskCookieRegistry.unregister(uploadTask)
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: LectioError.noResponse)
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                LectioURLSessionTaskCookieRegistry.register(redirectContext, for: uploadTask)
                taskBox.setTask(uploadTask)
                uploadTask.resume()
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    /// Authenticated request whose body is streamed from disk. Used for multipart file uploads.
    func performFileUploadRequest(
        url: URL,
        bodyFileURL: URL,
        headers: [String: String],
        credentials: LectioCredentials,
        studentId: String?,
        priority: FetchPriority = .important
    ) async throws -> (data: Data, updatedCredentials: LectioCredentials?, finalURL: URL) {
        var currentCredentials = credentials
        var lastError: Error = LectioError.noResponse

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
                let changed = currentCredentials.autologinkey != credentials.autologinkey ||
                    currentCredentials.sessionId != credentials.sessionId ||
                    currentCredentials.additionalCookies != credentials.additionalCookies
                return (result.data, changed ? currentCredentials : nil, result.finalURL)
            } catch LectioError.invalidCredentials where attempt < maxAttempts - 1 {
                let delay: UInt64 = attempt == 0 ? 500_000_000 : 1_500_000_000
                try await Task.sleep(nanoseconds: delay)
                lastError = LectioError.invalidCredentials
            } catch LectioError.robotDetection where attempt < maxAttempts - 1 {
                try await Task.sleep(nanoseconds: 3_000_000_000 + UInt64.random(in: 0...1_500_000_000))
                lastError = LectioError.robotDetection
            } catch let error as URLError where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code) && attempt < maxAttempts - 1 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                lastError = error
            } catch {
                throw error
            }
        }
        (lastError as? LectioError)?.notifyIfSessionExpired()
        throw lastError
    }

    private func performSingleFileUploadAttempt(
        url: URL,
        bodyFileURL: URL,
        headers: [String: String],
        credentials: LectioCredentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (data: Data, credentials: LectioCredentials, finalURL: URL) {
        try await Self.withSerialLectioRequest(priority: priority) {
            var currentCredentials = studentId.flatMap { keychainManager.loadCredentials(for: $0) } ?? credentials
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cookieManager.cookieHeader(from: currentCredentials), forHTTPHeaderField: "Cookie")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.lectio.dk", forHTTPHeaderField: "Referer")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

            LectioRequestLog.outbound(method: "POST", url: url, cookieHeader: request.value(forHTTPHeaderField: "Cookie"))
            let context = LectioDataTaskCookieContext(credentials: currentCredentials, studentId: studentId, onUpdate: nil)
            let (data, response) = try await Self.uploadTaskForLectioRequest(
                request,
                bodyFileURL: bodyFileURL,
                redirectContext: context
            )
            currentCredentials = context.creds

            guard let httpResponse = response as? HTTPURLResponse else { throw LectioError.noResponse }
            if let updated = cookieManager.updateCredentials(from: httpResponse, currentCredentials: currentCredentials) {
                currentCredentials = updated
                if let studentId { try? keychainManager.updateCredentials(updated, for: studentId) }
            }
            let finalURL = httpResponse.url ?? url
            if isLectioUniLoginURL(finalURL) { throw LectioError.invalidCredentials }

            switch httpResponse.statusCode {
            case 200:
                if isRobotDetectionPage(decodeHTML(from: data)) { throw LectioError.robotDetection }
                return (data, currentCredentials, finalURL)
            case 401, 403:
                throw LectioError.invalidCredentials
            default:
                throw LectioError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode))
            }
        }
    }

    /// A single request attempt, serialized with other Lectio requests: send → handle redirects. Throws on auth error,
    /// robot detection, or transient network issues — the outer `performRequest` catches and retries.
    private func performSingleAttempt(
        url: URL,
        method: String,
        body: Data?,
        headers: [String: String],
        credentials: LectioCredentials,
        studentId: String?,
        priority: FetchPriority,
        onCredentialsUpdated: ((LectioCredentials) -> Void)? = nil
    ) async throws -> (data: Data, credentials: LectioCredentials, finalURL: URL) {
        try await withSerialLectioRequest(priority: priority) {
            // Re-read the freshest credentials from the keychain right before sending. Between
            // when the caller invoked performRequest (snapshotting `credentials`) and now, a
            // concurrent request may have rotated ASP.NET_SessionId / autologinkeyV2 and written
            // the new values to the keychain. The rate limiter serializes us, so any prior
            // request's keychain update is already visible by the time we get here.
            var currentCredentials = studentId.flatMap { keychainManager.loadCredentials(for: $0) } ?? credentials
            var currentURL = url
            var redirectCount = 0

            while redirectCount < maxRedirects {
                var request = URLRequest(url: currentURL)
                request.httpMethod = method
                request.httpBody = body

                request.setValue(cookieManager.cookieHeader(from: currentCredentials), forHTTPHeaderField: "Cookie")
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("https://www.lectio.dk", forHTTPHeaderField: "Referer")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }

                LectioRequestLog.outbound(
                    method: method,
                    url: currentURL,
                    cookieHeader: request.value(forHTTPHeaderField: "Cookie")
                )

                let redirectContext = LectioDataTaskCookieContext(
                    credentials: currentCredentials,
                    studentId: studentId,
                    onUpdate: onCredentialsUpdated
                )
                let (data, response) = try await Self.dataTaskForLectioRequest(request, redirectContext: redirectContext)
                currentCredentials = redirectContext.creds

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw LectioError.noResponse
                }

                print("📍 Status: \(httpResponse.statusCode) (\(currentURL.lastPathComponent))")
                cookieManager.logResponseCookies(from: httpResponse)

                if let updatedCreds = cookieManager.updateCredentials(from: httpResponse, currentCredentials: currentCredentials) {
                    currentCredentials = updatedCreds
                    onCredentialsUpdated?(currentCredentials)
                    if let studentId = studentId {
                        try? keychainManager.updateCredentials(currentCredentials, for: studentId)
                    }
                }

                switch httpResponse.statusCode {
                case 200:
                    let finalURL = httpResponse.url ?? currentURL
                    if isLectioUniLoginURL(finalURL) {
                        print("❌ Final URL is on UniLogin broker — session expired")
                        throw LectioError.invalidCredentials
                    }
                    if isRobotDetectionPage(decodeHTML(from: data)) {
                        print("❌ Robot detection page")
                        throw LectioError.robotDetection
                    }
                    return (data, currentCredentials, finalURL)

                case 301, 302, 303, 307, 308:
                    let locationRaw = httpResponse.value(forHTTPHeaderField: "Location") ?? "<missing>"
                    print("🔀 [redirect] HTTP \(httpResponse.statusCode) from \(LectioRequestLog.compactPath(for: currentURL))")
                    let safeLocation = URL(string: locationRaw, relativeTo: currentURL)
                        .map { LectioRequestLog.compactPath(for: $0) } ?? "<invalid>"
                    print("🔀 [redirect] Location: \(safeLocation)")

                    guard let location = httpResponse.value(forHTTPHeaderField: "Location"),
                          let redirectURL = URL(string: location, relativeTo: currentURL) else {
                        print("🔀 [redirect] could not resolve Location to a valid URL")
                        throw LectioError.invalidURL
                    }

                    print("🔀 [redirect] resolved → \(LectioRequestLog.compactPath(for: redirectURL)) (hop \(redirectCount + 1)/\(maxRedirects))")

                    if isLectioUniLoginURL(redirectURL) {
                        print("❌ Redirected to UniLogin broker (expired)")
                        throw LectioError.invalidCredentials
                    }

                    currentURL = redirectURL
                    redirectCount += 1

                case 401, 403:
                    throw LectioError.invalidCredentials

                default:
                    throw LectioError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode))
                }
            }

            print("❌ Exceeded \(maxRedirects) redirects — treating as session expired")
            throw LectioError.invalidCredentials
        }
    }

    static func withSerialLectioRequest<T>(
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

    private func withSerialLectioRequest<T>(
        priority: FetchPriority,
        _ body: () async throws -> T
    ) async throws -> T {
        try await Self.withSerialLectioRequest(priority: priority, body)
    }

    /// Legacy wrapper for fetchWithCookies
    func fetchWithCookies(
        url: URL,
        credentials: LectioCredentials,
        studentId: String?,
        contextForLogging: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> (data: Data, updatedCredentials: LectioCredentials?, finalURL: URL) {
        try await performRequest(
            url: url,
            method: "GET",
            credentials: credentials,
            studentId: studentId,
            contextForLogging: contextForLogging,
            priority: priority
        )
    }

    // MARK: - Helpers

    func decodeHTML(from data: Data) -> String {
        if let html = String(data: data, encoding: .utf8) {
            return html
        }
        if let html = String(data: data, encoding: .isoLatin1) {
            return html
        }
        return String(decoding: data, as: UTF8.self)
    }

    func isRobotDetectionPage(_ html: String) -> Bool {
        html.contains("ikke er en robot") ||
        html.contains("Af hensyn til sikkerheden") ||
        html.contains("RobotDetection.aspx")
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

/// Serializes Lectio HTTP attempts AND enforces a minimum gap between consecutive requests.
/// Lectio's autologin reuse-detector trips when requests fire too close together — concurrent
/// requests racing through redirects can each present what looks like a freshly-rotated token,
/// and the server invalidates the session. Spacing requests gives Set-Cookie writes time to
/// land in the keychain and prevents the rapid-rotation pattern from looking like replay.
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
