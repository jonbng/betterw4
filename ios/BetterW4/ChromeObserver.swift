//
//  ChromeObserver.swift
//  BetterW4
//
//  The campus-status chip and the notification bell live in the chrome of EVERY authenticated W4
//  page (`references/pages/UWCRCN W4.html:37-49` [V]). That makes them free if we harvest them from
//  pages we already fetched, and wasteful if we poll for them separately.
//
//  This file holds the harvesting hub plus the two small pieces both chrome repositories share:
//  the transport seam, the "where did this HTML come from" marker, the update fan-out, and the
//  single rule about which errors a repository may never swallow.
//
//  Plan D-23: the `W4Client` hook fires on every HTML response carrying `id="user-panel"` and calls
//  ``ChromeObserver/observe(html:origin:)`` on a detached task. Wave 6 wires that hook up; nothing
//  in this wave touches the UI or the transport. Any repository that has just fetched an
//  authenticated page can call it too, and the chip and the bell refresh with **zero extra
//  requests**.
//
//  Deliberate limits, so nobody is surprised later:
//
//    * A page that is not authenticated W4 chrome (login HTML, an AJAX fragment, a PDF decoded to
//      nonsense) is ignored outright — see ``ChromeObserver/carriesChrome(_:)``. Without that gate
//      `W4NotificationParser.parse` would fall through to `document.body()`, find no rows and
//      quietly *empty* a populated bell.
//    * An observation older than the one we already hold never overwrites it. Pages arrive out of
//      order once several repositories are in flight.
//    * The bell's `notifications/refresh` fragment is NOT a page: it goes through
//      ``NotificationRepository/applyFragment(_:)``, which skips the page gate on purpose.
//

import Foundation

// MARK: - Transport seam

/// One W4 response, reduced to what the chrome layer needs.
///
/// Exists so both chrome repositories can be driven by a stub in `BetterW4Tests` without a socket.
/// `W4HTTPClient` itself is untouched (plan D-29: the transport stack is frozen).
struct ChromePageResponse: Sendable {
    let html: String
    let finalURL: URL?

    init(html: String, finalURL: URL? = nil) {
        self.html = html
        self.finalURL = finalURL
    }
}

/// The two calls the chrome layer makes: fetch an authenticated page, and fire one of W4's own
/// jQuery `$.post` endpoints (`site/setstatus`, `notifications/*`).
protocol W4ChromeTransport: Sendable {

    /// `GET index.php?r={route}` — used for the dedicated chrome refresh (`site/index`).
    func fetchPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse

    /// `POST index.php?r={route}` with `X-Requested-With: XMLHttpRequest`, which is what every
    /// campus-status and notification write is (README §5.3).
    func postAjax(
        route: String,
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse
}

/// The production adapter over `W4HTTPClient`.
///
/// `@unchecked Sendable` because `W4HTTPClient` is a plain class whose only state is a handful of
/// shared singletons (`CookieManager.shared`, `KeychainManager.shared`, the static `URLSession` and
/// the static request gate); nothing per-instance is mutated.
final class W4ChromeClient: W4ChromeTransport, @unchecked Sendable {
    private let client: W4HTTPClient

    init(client: W4HTTPClient = W4HTTPClient()) {
        self.client = client
    }

    func fetchPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse {
        let result = try await client.get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return ChromePageResponse(
            html: client.decodeHTML(from: result.data),
            finalURL: result.finalURL
        )
    }

    func postAjax(
        route: String,
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse {
        let result = try await client.postAjax(
            route: route,
            fields: fields,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return ChromePageResponse(
            html: client.decodeHTML(from: result.data),
            finalURL: result.finalURL
        )
    }
}

// MARK: - Session resolution seam

/// How the chrome layer finds out who is signed in.
///
/// Injectable so a test never has to write to the Keychain — the production default is
/// `W4RequestContext.require()`, which throws `.sessionExpired` when a student record exists but its
/// credentials are gone, and `.missingCookies` when nobody is signed in at all.
typealias W4ChromeContextResolver = @Sendable () throws -> W4RequestContext

// MARK: - Provenance

/// Where a piece of chrome HTML came from.
///
/// The chip and the bell are the only surfaces in the app that can be refreshed by *somebody else's*
/// fetch, so "when was this true?" has to travel with the HTML rather than being assumed to be now.
enum ChromePageOrigin: Sendable, Equatable {
    /// Straight off the wire in this session.
    case live
    /// Replayed out of `W4PageCache` — the page was fetched at this instant, possibly long ago.
    case cache(fetchedAt: Date)

    func fetchedAt(now: Date) -> Date {
        switch self {
        case .live: return now
        case .cache(let fetchedAt): return fetchedAt
        }
    }

    /// TTL comes from `CachePolicy` only — never a literal in a repository.
    func freshness(now: Date) -> W4Freshness {
        switch self {
        case .live:
            return .fresh
        case .cache(let fetchedAt):
            return .cached(
                fetchedAt: fetchedAt,
                isStale: !CachePolicy.isFresh(fetchedAt, for: .chrome, now: now)
            )
        }
    }
}

// MARK: - Failure policy

/// The one rule both chrome repositories obey when a fetch fails.
enum ChromeFailure {

    /// True for the errors that must reach the caller even when a perfectly good cached copy is in
    /// hand.
    ///
    /// `.sessionExpired` is the load-bearing case: swallowing it behind yesterday's campus chip
    /// leaves the app signed out but pretending otherwise, and the re-login never happens.
    /// Cancellation propagates because a cancelled task wants to stop, not to be handed stale data.
    ///
    /// `W4Error.forbidden` is deliberately **absent**: 403 without "Login Required" means signed in
    /// with the wrong role (plan D-21), and it must never look like a dead session.
    static func mustPropagate(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        guard let w4 = error as? W4Error else { return false }
        switch w4 {
        case .sessionExpired, .cookieExpired, .missingCookies, .invalidCredentials:
            return true
        case .forbidden, .invalidURL, .noResponse, .serverConflict, .httpError,
             .notPortedToW4, .networkError, .parsingError, .keychainError:
            return false
        }
    }
}

// MARK: - Update fan-out

/// A tiny multi-consumer broadcast of the newest value.
///
/// The chrome repositories are actors, but their consumers (Wave 6's view models) live on the main
/// actor and want a stream. `AsyncStream` continuations are registered and dropped from whatever
/// isolation domain the consumer happens to be in, so the registry is lock-guarded rather than
/// actor-isolated.
final class ChromeBroadcast<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    /// One independent stream per caller. Buffers the newest value only: a screen that is behind
    /// wants the current chip, not the history of the chip.
    func stream() -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func send(_ value: Value) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(value) }
    }

    /// Ends every stream — logout, or a test tearing the repository down.
    func finish() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }

    var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }
}

// MARK: - Harvest result

/// What one page yielded. Both halves are optional: a page can carry the campus widget and an empty
/// bell, or neither.
struct ChromeHarvest: Sendable {
    let campusStatus: W4Loaded<CampusStatus>?
    let notifications: W4Loaded<W4NotificationSnapshot>?

    init(campusStatus: W4Loaded<CampusStatus>? = nil, notifications: W4Loaded<W4NotificationSnapshot>? = nil) {
        self.campusStatus = campusStatus
        self.notifications = notifications
    }

    /// Nothing was harvested. Not called `none`, so it can never be confused with `Optional.none`.
    static let nothing = ChromeHarvest()

    var didUpdateCampusStatus: Bool { campusStatus != nil }
    var didUpdateNotifications: Bool { notifications != nil }
    var isEmpty: Bool { campusStatus == nil && notifications == nil }
}

// MARK: - Observer

/// The hub every authenticated page passes through.
///
/// Owns no state of its own: it routes HTML to ``CampusStatusRepository`` and
/// ``NotificationRepository``, which own the snapshots, the cache and the writes.
actor ChromeObserver {

    static let shared = ChromeObserver()

    private let campusStatus: CampusStatusRepository
    private let notifications: NotificationRepository

    init(
        campusStatus: CampusStatusRepository = .shared,
        notifications: NotificationRepository = .shared
    ) {
        self.campusStatus = campusStatus
        self.notifications = notifications
    }

    // MARK: - Gate

    /// Cheap pre-filter, run before any HTML reaches SwiftSoup.
    ///
    /// `W4Html.isAuthenticatedHTML` is the D-23 signal: `id="user-panel"` or "Welcome," and not the
    /// login form. Feeding anything else to the chrome parsers is how a populated bell gets silently
    /// cleared by a 404 page.
    nonisolated static func carriesChrome(_ html: String) -> Bool {
        guard !html.isEmpty else { return false }
        return W4Html.isAuthenticatedHTML(html)
    }

    // MARK: - Harvesting

    /// Fire-and-forget entry point for the transport hook (plan D-23).
    ///
    /// Filters first so the overwhelmingly common "not a W4 page" case costs one substring scan on
    /// the caller's thread, then hands the work to a detached task: harvesting must never make the
    /// screen that triggered the fetch wait.
    nonisolated func observe(html: String, origin: ChromePageOrigin = .live) {
        guard Self.carriesChrome(html) else { return }
        Task.detached(priority: .utility) { [self] in
            _ = await self.apply(html: html, origin: origin)
        }
    }

    /// Runs both chrome parsers over one authenticated page and publishes what they found.
    ///
    /// Makes **no** network request — this is the whole point of the design: opening any screen
    /// refreshes the chip and the bell for free.
    @discardableResult
    func apply(html: String, origin: ChromePageOrigin = .live) async -> ChromeHarvest {
        guard Self.carriesChrome(html) else { return .nothing }
        let campus = await campusStatus.apply(pageHTML: html, origin: origin)
        let bell = await notifications.apply(pageHTML: html, origin: origin)
        return ChromeHarvest(campusStatus: campus, notifications: bell)
    }

    /// Half-harvests, so a repository that fetched a page for its *own* half can hand the page to
    /// the other half without parsing its own chrome twice.
    @discardableResult
    func applyCampusStatus(html: String, origin: ChromePageOrigin = .live) async -> W4Loaded<CampusStatus>? {
        guard Self.carriesChrome(html) else { return nil }
        return await campusStatus.apply(pageHTML: html, origin: origin)
    }

    @discardableResult
    func applyNotifications(html: String, origin: ChromePageOrigin = .live) async -> W4Loaded<W4NotificationSnapshot>? {
        guard Self.carriesChrome(html) else { return nil }
        return await notifications.apply(pageHTML: html, origin: origin)
    }

    // MARK: - Cold start

    /// Whatever both repositories have on disk, with no network at all. Call this at launch so the
    /// chip and the bell render before the first fetch lands.
    @discardableResult
    func loadCached() async -> ChromeHarvest {
        let campus = await campusStatus.loadCached()
        let bell = await notifications.loadCached()
        return ChromeHarvest(campusStatus: campus, notifications: bell)
    }

    // MARK: - Streams

    /// Pass-throughs so a view model only has to know about the observer.
    nonisolated func campusStatusUpdates() -> AsyncStream<W4Loaded<CampusStatus>> {
        campusStatus.updatesStream()
    }

    nonisolated func notificationUpdates() -> AsyncStream<W4Loaded<W4NotificationSnapshot>> {
        notifications.updatesStream()
    }

    /// The last known values, with no I/O of any kind.
    func current() async -> ChromeHarvest {
        ChromeHarvest(
            campusStatus: await campusStatus.snapshot(),
            notifications: await notifications.snapshot()
        )
    }

    // MARK: - Dedicated refresh

    /// One `site/index` fetch that refreshes **both** halves.
    ///
    /// Delegates to `CampusStatusRepository.load`, whose broadcast hook feeds the returned page
    /// straight back here for the bell — so this really is one request, not two.
    @discardableResult
    func refresh(priority: FetchPriority = .important) async throws -> ChromeHarvest {
        let campus = try await campusStatus.load(forceRefresh: true, priority: priority)
        return ChromeHarvest(campusStatus: campus, notifications: await notifications.snapshot())
    }

    // MARK: - Teardown

    /// Logout / "Clear cache": drop both snapshots from memory and from `W4PageCache`.
    func reset() async {
        await campusStatus.reset()
        await notifications.reset()
    }
}
