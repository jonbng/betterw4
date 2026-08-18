//
//  CampusStatusRepository.swift
//  BetterW4
//
//  Owns the campus-status chip: the current state, its cached copy, and the one write W4 offers
//  (`POST index.php?r=site/setstatus`).
//
//  Spec: `features.md` §1.7, plan item 5.6, decisions D-12 / D-23, bug B6.
//
//  HOW THIS SURFACE IS DIFFERENT FROM EVERY OTHER REPOSITORY
//
//  The campus widget is rendered into the chrome of every authenticated W4 page, so the happy path
//  makes **no request at all**: ``apply(pageHTML:origin:)`` is fed by `ChromeObserver` from pages
//  other repositories already fetched. ``load(forceRefresh:priority:)`` exists for the cold start
//  and for pull-to-refresh, and it is the only path here that touches the network for a read.
//
//  WHAT GETS CACHED
//
//  Not a page — the parsed ``CampusStatus``, JSON-encoded into `W4PageCache` under
//  `W4Surface.chrome`. Storing the whole 16 KB page on every navigation would duplicate whatever
//  `HomeRepository` already holds, four times a minute, for a value that is under 2 KB. The cache
//  gives us the `fetchedAt` sidecar, per-uwc-id scoping and "Clear cache" for free; the TTL is
//  `CachePolicy.ttl(for: .chrome)` and is never written down here.
//
//  THE WRITE (plan D-12 / bug B6 — the load-bearing rule in this file)
//
//    * "On campus"  → `["status": "on"]` and **no `location` key at all**
//    * "Other"      → `["status": "off", "location": <the #other free text>]`
//    * anything else→ `["status": "off", "location": <the option's POST value>]`
//
//  The body is built by `W4CampusStatusParser.setStatusBody`, which keeps `value` and `label` apart.
//  Posting the *label* is the Kotlin port's bug B6 and breaks two of the eleven options.
//
//  W4's own `campusstatusdropdown.js:19-29` throws the response away and patches the DOM by hand, so
//  the body is usually empty. We re-parse it anyway: if the server did answer with the widget, its
//  answer replaces the snapshot. Only when it answered with nothing do we fall back to the state we
//  asked for.
//

import Foundation

// MARK: - Write errors

/// The two ways a campus write can be rejected before it reaches the wire.
enum CampusStatusWriteError: Error, LocalizedError, Equatable {

    /// The free-text ("Other") option was chosen with an empty box. `campusstatusdropdown.js:12-15`
    /// refuses to post in exactly this case; posting `location=` would silently record nothing.
    case locationRequired

    /// An option id that is not in the widget's list. Never guess a POST value.
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .locationRequired:
            return "Enter your current location"
        case .unknownOption(let id):
            return "That campus location is no longer offered (\(id))"
        }
    }
}

// MARK: - Repository

actor CampusStatusRepository {

    static let shared = CampusStatusRepository()

    /// The chip shares the `chrome` surface with the bell; the key keeps the two apart on disk.
    static let cacheKey = "campus-status"
    private static let surface: W4Surface = .chrome
    private static let cacheContentType = "application/json; charset=utf-8"

    // MARK: Dependencies

    private let client: W4ChromeTransport
    private let cache: W4PageCache
    private let resolveContext: W4ChromeContextResolver

    /// Where a page fetched by *this* repository goes so the notification bell gets refreshed for
    /// free. Production wires it to `ChromeObserver.applyNotifications` — the bell half only, so the
    /// page is never parsed for the campus widget twice.
    ///
    /// Referencing `ChromeObserver.shared` inside the closure body (rather than as a stored default)
    /// keeps the two singletons from initialising each other.
    private let broadcast: (@Sendable (String, ChromePageOrigin) async -> Void)?

    private let updates = ChromeBroadcast<W4Loaded<CampusStatus>>()

    // MARK: State

    private var latest: CampusStatus?
    private var latestFetchedAt: Date?
    private var latestUwcId: String?
    private var isDemoSession = false
    private var didReadDisk = false

    init(
        client: W4ChromeTransport = W4ChromeClient(),
        cache: W4PageCache = .shared,
        resolveContext: @escaping W4ChromeContextResolver = { try W4RequestContext.require() },
        broadcast: (@Sendable (String, ChromePageOrigin) async -> Void)? = { html, origin in
            _ = await ChromeObserver.shared.applyNotifications(html: html, origin: origin)
        }
    ) {
        self.client = client
        self.cache = cache
        self.resolveContext = resolveContext
        self.broadcast = broadcast
    }

    // MARK: - Observation

    /// Every accepted observation, for a view model that wants to follow the chip.
    nonisolated func updatesStream() -> AsyncStream<W4Loaded<CampusStatus>> {
        updates.stream()
    }

    /// The last known status, with no I/O. `nil` until something has been harvested or loaded.
    func snapshot() -> W4Loaded<CampusStatus>? {
        held(now: TimeProvider.now)
    }

    // MARK: - Reading

    /// The persisted copy, with no network request. Safe to call at launch.
    @discardableResult
    func loadCached() async -> W4Loaded<CampusStatus>? {
        guard let context = try? resolveContext() else { return nil }
        adopt(context)
        if context.isDemo {
            return record(Self.demoStatus, fetchedAt: TimeProvider.now, freshness: .demo)
        }
        await primeFromDisk(uwcId: context.uwcId)
        return held(now: TimeProvider.now)
    }

    /// Cache-first read, then a `site/index` fetch when the cached copy is missing or past its TTL.
    ///
    /// A failed fetch degrades to whatever copy we hold rather than throwing, except for the errors
    /// `ChromeFailure.mustPropagate` names — `.sessionExpired` above all, which the app needs in
    /// order to re-login.
    @discardableResult
    func load(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<CampusStatus> {
        let context = try resolveContext()
        adopt(context)
        let now = TimeProvider.now

        // (a) Demo never reaches the network — branch before anything else.
        if context.isDemo {
            return record(latest ?? Self.demoStatus, fetchedAt: now, freshness: .demo)
        }

        // (b) Serve what we already have so a screen can render instantly.
        if !forceRefresh, let fresh = heldIfFresh(now: now) { return fresh }
        await primeFromDisk(uwcId: context.uwcId)
        if !forceRefresh, let fresh = heldIfFresh(now: now) { return fresh }

        // (c) Fetch, parse, store, return honest freshness.
        do {
            let response = try await client.fetchPage(
                route: W4Routes.R.home,
                query: [:],
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            guard ChromeObserver.carriesChrome(response.html),
                  let status = W4CampusStatusParser.parse(response.html) else {
                // W4 answered, but with something that is not authenticated chrome. Showing the
                // last known chip beats blanking it.
                if let cached = held(now: TimeProvider.now) { return cached }
                throw W4Error.parsingError("the W4 home page carried no campus-status control")
            }

            let fetchedAt = TimeProvider.now
            let loaded = record(status, fetchedAt: fetchedAt, freshness: .fresh)
            await persist(status, fetchedAt: fetchedAt, uwcId: context.uwcId)
            // The same page carries the bell. Hand it over: one request, two surfaces.
            if let broadcast {
                await broadcast(response.html, .live)
            }
            return loaded
        } catch {
            if ChromeFailure.mustPropagate(error) { throw error }
            if let cached = held(now: TimeProvider.now) { return cached }
            throw error
        }
    }

    // MARK: - Harvesting

    /// Reads the campus widget out of a page somebody else fetched. Never makes a request.
    ///
    /// Returns `nil` when nobody is signed in, when the session is demo, or when the page carries no
    /// campus chrome. An observation older than the one already held is discarded and the held value
    /// is returned unchanged.
    @discardableResult
    func apply(pageHTML html: String, origin: ChromePageOrigin = .live) async -> W4Loaded<CampusStatus>? {
        guard let context = try? resolveContext() else { return nil }
        adopt(context)
        // A demo session has no pages; anything arriving here is not its data.
        guard !context.isDemo else { return nil }
        guard ChromeObserver.carriesChrome(html) else { return nil }
        guard let status = W4CampusStatusParser.parse(html) else { return nil }

        let now = TimeProvider.now
        let fetchedAt = origin.fetchedAt(now: now)
        // Pages arrive out of order once several repositories are in flight; an older render must
        // never overwrite a newer one.
        if let existing = latestFetchedAt, fetchedAt < existing { return held(now: now) }

        let shouldPersist = latest != status
            || latestFetchedAt == nil
            || !CachePolicy.isFresh(latestFetchedAt ?? .distantPast, for: Self.surface, now: fetchedAt)

        let loaded = record(status, fetchedAt: fetchedAt, freshness: origin.freshness(now: now))
        if shouldPersist {
            await persist(status, fetchedAt: fetchedAt, uwcId: context.uwcId)
        }
        return loaded
    }

    // MARK: - Writing

    /// `POST index.php?r=site/setstatus` for one option of the widget (plan D-12 / bug B6).
    ///
    /// Throws rather than degrading: a write that silently "succeeds" against a cached copy would
    /// tell a student they are marked off campus when the school's board still says otherwise.
    @discardableResult
    func setStatus(
        option: CampusLocationOption,
        freeText: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<CampusStatus> {
        let context = try resolveContext()
        adopt(context)

        guard let fields = W4CampusStatusParser.setStatusBody(option: option, freeText: freeText) else {
            throw CampusStatusWriteError.locationRequired
        }

        let now = TimeProvider.now
        let projected = Self.projected(option: option, freeText: freeText, onto: latest)

        if context.isDemo {
            return record(projected, fetchedAt: now, freshness: .demo)
        }

        let response = try await client.postAjax(
            route: W4CampusStatusParser.setStatusRoute,
            fields: fields,
            credentials: context.credentials,
            studentId: context.uwcId,
            priority: priority
        )

        // Re-parse rather than assume. W4's own JS ignores this body, so it is usually empty —
        // but when the server does echo the widget, the server is right and we are guessing.
        let confirmed = W4CampusStatusParser.parse(response.html) ?? projected
        let fetchedAt = TimeProvider.now
        let loaded = record(confirmed, fetchedAt: fetchedAt, freshness: .fresh)
        await persist(confirmed, fetchedAt: fetchedAt, uwcId: context.uwcId)

        // Some Yii actions answer a `$.post` with the whole page. If this one did, the bell in it
        // is current too.
        if let broadcast, ChromeObserver.carriesChrome(response.html) {
            await broadcast(response.html, .live)
        }
        return loaded
    }

    /// Same write, addressed by the radio's DOM id — what a picker hands back.
    @discardableResult
    func setStatus(
        optionID: String,
        freeText: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<CampusStatus> {
        let available = latest?.options ?? CampusStatus.defaultOptions
        guard let option = available.first(where: { $0.id == optionID }) else {
            throw CampusStatusWriteError.unknownOption(optionID)
        }
        return try await setStatus(option: option, freeText: freeText, priority: priority)
    }

    /// "I am back on campus" — the one write that must post no `location` key at all.
    @discardableResult
    func setOnCampus(priority: FetchPriority = .important) async throws -> W4Loaded<CampusStatus> {
        let available = latest?.options ?? CampusStatus.defaultOptions
        let option = available.first(where: { $0.isOnCampus })
            ?? CampusLocationOption(
                id: "location_0",
                value: CampusLocationOption.onCampusValue,
                label: "On campus"
            )
        return try await setStatus(option: option, priority: priority)
    }

    // MARK: - Teardown

    /// Logout / "Clear cache". Named `reset` to match ``NotificationRepository/reset()``.
    func reset() async {
        let uwcId = latestUwcId
        latest = nil
        latestFetchedAt = nil
        latestUwcId = nil
        isDemoSession = false
        didReadDisk = false
        if let uwcId {
            await cache.remove(surface: Self.surface, key: Self.cacheKey, uwcId: uwcId)
        }
        // Deliberately does NOT finish the update streams: "Clear cache" in Settings uses this path
        // too, and a screen that is still on-screen must keep receiving the next observation.
    }

    // MARK: - State plumbing

    /// Signing in as a different student must never surface the previous student's chip.
    private func adopt(_ context: W4RequestContext) {
        isDemoSession = context.isDemo
        guard latestUwcId != context.uwcId else { return }
        latestUwcId = context.uwcId
        latest = nil
        latestFetchedAt = nil
        didReadDisk = false
    }

    @discardableResult
    private func record(
        _ status: CampusStatus,
        fetchedAt: Date,
        freshness: W4Freshness
    ) -> W4Loaded<CampusStatus> {
        latest = status
        latestFetchedAt = fetchedAt
        let loaded = W4Loaded(status, freshness: freshness)
        updates.send(loaded)
        return loaded
    }

    /// What we hold, described honestly: a value already in hand is `.cached`, never `.fresh`.
    private func held(now: Date) -> W4Loaded<CampusStatus>? {
        guard let status = latest, let fetchedAt = latestFetchedAt else { return nil }
        if isDemoSession { return W4Loaded(status, freshness: .demo) }
        return W4Loaded(
            status,
            freshness: .cached(
                fetchedAt: fetchedAt,
                isStale: !CachePolicy.isFresh(fetchedAt, for: Self.surface, now: now)
            )
        )
    }

    private func heldIfFresh(now: Date) -> W4Loaded<CampusStatus>? {
        guard let candidate = held(now: now) else { return nil }
        if case .cached(_, let isStale) = candidate.freshness, isStale { return nil }
        return candidate
    }

    // MARK: - Disk

    private func primeFromDisk(uwcId: String) async {
        guard !didReadDisk else { return }
        didReadDisk = true
        guard latest == nil else { return }
        guard let page = await cache.page(surface: Self.surface, key: Self.cacheKey, uwcId: uwcId),
              let data = page.html.data(using: .utf8),
              let status = try? JSONDecoder().decode(CampusStatus.self, from: data) else { return }
        latest = status
        latestFetchedAt = page.fetchedAt
    }

    private func persist(_ status: CampusStatus, fetchedAt: Date, uwcId: String) async {
        guard let data = try? JSONEncoder().encode(status),
              let json = String(data: data, encoding: .utf8) else { return }
        await cache.store(
            html: json,
            surface: Self.surface,
            key: Self.cacheKey,
            uwcId: uwcId,
            finalURL: nil,
            contentType: Self.cacheContentType,
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Projection + demo

    /// The state the widget will be in if the POST succeeds, keeping whatever option list we have.
    ///
    /// Mirrors `W4CampusStatusParser.setStatusBody` exactly, including the 20-character cap that
    /// applies to the free-text field and to nothing else.
    static func projected(
        option: CampusLocationOption,
        freeText: String?,
        onto previous: CampusStatus?
    ) -> CampusStatus {
        let options = previous?.options ?? CampusStatus.defaultOptions
        if option.isOnCampus {
            return CampusStatus(
                isOnCampus: true,
                location: nil,
                options: options,
                selectedOptionID: option.id
            )
        }
        let trimmed = (freeText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = option.isFreeText
            ? String(trimmed.prefix(CampusStatus.freeTextMaxLength))
            : option.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return CampusStatus(
            isOnCampus: false,
            location: location.isEmpty ? nil : location,
            options: options,
            selectedOptionID: option.id
        )
    }

    /// What App Review sees. The eleven real options, on campus — same as `CampusStatus.onCampus`.
    static let demoStatus = CampusStatus.onCampus
}
