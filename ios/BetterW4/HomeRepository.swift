//
//  HomeRepository.swift
//  BetterW4
//
//  One `r=site/index` fetch, many models (features.md §1.16, plan Wave 5 item 5.8).
//
//  Home is the densest page W4 serves. The single response carries the week grid, both attendance
//  meters, the greeting and the signed-in student's own UWC id, birthdays, announcements, the links
//  block, the campus-status widget and the notification bell. If every screen fetched it for itself,
//  a cold launch would hit `site/index` four times through a serial request gate on a school server
//  that runs ~200 students off one Apache box.
//
//  So this file owns exactly one thing: **the Home page, fetched at most once.**
//
//  ── The seam other repositories consume ────────────────────────────────────────────────────────
//
//  `HomeRepository.shared.homePage()` returns the raw Home HTML plus honest provenance. It is:
//
//    * cache-first  — a page still inside `CachePolicy.ttl(for: .home)` is returned with no request;
//    * single-flight — N concurrent callers on a cold cache produce exactly ONE network fetch, and
//                      all N await the same `Task`;
//    * demo-safe    — a demo session never reaches the network. `snapshot()` answers with demo data;
//                     `homePage()` throws `HomeRepositoryError.demoSessionHasNoHTML`, because there
//                     is no Home markup to hand out and faking some would push synthetic HTML
//                     through the real parsers.
//
//  Wave 5 siblings use it like this, and none of them refetch `site/index`:
//
//    AttendanceRepository (5.4)   let doc = try await HomeRepository.shared.homePage()
//                                 W4AbsenceParser.parseHomeMeters(doc.value.html)
//    TimetableRepository  (5.1)   W4TimetableParser.parseWeek(html: doc.value.html, source: .academics)
//    Chrome repos         (5.6)   W4CampusStatusParser.parse(doc.value.html)
//                                 W4NotificationParser.parse(doc.value.html)
//
//  Two more doors into the same data, both deliberate:
//
//    * `cachedHomePage()` never fetches. A screen that must render instantly (or must not generate
//      traffic while backgrounded) reads this first, then asks for the live one.
//    * `ingest(html:finalURL:)` lets a component that already *has* a Home response — the D-23
//      chrome hook, a WebView landing on `site/index` after login — donate it, so the next reader
//      is served from cache instead of refetching a page the app just received.
//
//  Authority note (D-23): the live campus chip and bell are owned by the chrome repositories, fed by
//  the client-side hook on *every* page. `HomeSnapshot.campus` / `.notifications` are the Home
//  screen's view of that same markup, not a second source of truth.
//
//  This file also declares the small transport/cache seam shared by the four repositories of plan
//  item 5.8 part B (Home, Feeds, Extra Academics, Resources). It lives here because Home is the
//  anchor of the group; see "Shared page seam" below.
//

import Foundation
import OSLog
import SwiftSoup

// MARK: - Shared page seam (Home / Feeds / Extra Academics / Resources)

/// The one thing these repositories need from the transport: "GET this route, give me the HTML".
///
/// It exists so the repositories can be unit-tested against a stub without touching `W4HTTPClient`,
/// which stays frozen per D-29. `W4HTTPClient` conforms below; the real implementation is four lines.
protocol W4RouteFetching {
    func fetchRoute(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4RouteResponse
}

/// A decoded response: what a repository actually wants back from a GET.
struct W4RouteResponse: Sendable {
    let html: String
    let finalURL: URL?
    /// `nil` from the real client — `W4HTTPClient.get` does not surface response headers. Kept in the
    /// type because `W4PageCache` records it and a future transport may fill it in.
    let contentType: String?

    init(html: String, finalURL: URL? = nil, contentType: String? = nil) {
        self.html = html
        self.finalURL = finalURL
        self.contentType = contentType
    }
}

extension W4HTTPClient: W4RouteFetching {
    func fetchRoute(
        route: String,
        query: [String: String] = [:],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4RouteResponse {
        let result = try await get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return W4RouteResponse(
            html: decodeHTML(from: result.data),
            finalURL: result.finalURL,
            contentType: nil
        )
    }
}

/// Which page, on which cache shelf. One value describes a whole surface.
struct W4PageTarget: Sendable, Equatable {
    /// Decides the TTL. TTLs live only in `CachePolicy`; nothing here may invent one.
    let surface: W4Surface
    /// Cache key inside the surface. Include every query parameter that changes the response.
    let cacheKey: String
    /// The Yii `r=` route.
    let route: String
    let query: [String: String]

    init(surface: W4Surface, cacheKey: String, route: String, query: [String: String] = [:]) {
        self.surface = surface
        self.cacheKey = cacheKey
        self.route = route
        self.query = query
    }

    /// The common case: the route is its own cache key.
    init(surface: W4Surface, route: String) {
        self.init(surface: surface, cacheKey: route, route: route, query: [:])
    }
}

/// One W4 page as this app holds it: the markup, when W4 produced it, and where it landed.
struct W4PageSnapshot: Sendable, Equatable {
    let html: String
    let fetchedAt: Date
    let finalURL: URL?

    init(html: String, fetchedAt: Date, finalURL: URL? = nil) {
        self.html = html
        self.fetchedAt = fetchedAt
        self.finalURL = finalURL
    }

    /// The inner HTML of `#content_inner`, W4's per-page content well.
    ///
    /// **[V]** on 19 of the 20 W4 fixtures (every full page; the exception is the notifications AJAX
    /// *fragment*, which has no page chrome at all). This is the honest way to render a surface whose
    /// detailed markup has never been captured — see `ExtraAcademicsRepository` and
    /// `ResourceRepository` — without inventing selectors nobody has verified.
    var contentFragmentHTML: String? {
        guard let document = try? SwiftSoup.parse(html),
              let inner = try? document.select("#content_inner").first(),
              let fragment = try? inner.html() else { return nil }
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The `<h2>` W4 puts at the top of `#content_inner` — the page's own title. **[V]**
    var heading: String? {
        guard let document = try? SwiftSoup.parse(html),
              let heading = try? document.select("#content_inner h2").first(),
              let text = try? heading.text() else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Cache-first page loading, written once instead of four times.
///
/// The rules it enforces, which are the whole point of the repository layer:
///
///   1. a cached page inside its TTL is served without a request;
///   2. a fetch stores to `W4PageCache` and reports `.fresh`;
///   3. a failed fetch with any usable cached copy — stale included — returns that copy rather than
///      an error, because offline with a warm cache is a working app (features.md §3 rule 4);
///   4. **`.sessionExpired` is never swallowed.** It is the one error that logs the user out, and a
///      repository that hides it behind yesterday's HTML strands the app in a signed-out session
///      forever. `.forbidden` is explicitly *not* in that club (features.md §3 rule 6);
///   5. cancellation propagates untouched — the caller asked for that.
struct W4PageLoader {
    let client: any W4RouteFetching
    let cache: W4PageCache

    init(client: any W4RouteFetching, cache: W4PageCache) {
        self.client = client
        self.cache = cache
    }

    /// The cached copy, fresh or stale, without touching the network.
    func cached(_ target: W4PageTarget, context: W4RequestContext) async -> W4Loaded<W4PageSnapshot>? {
        guard let page = await cache.page(
            surface: target.surface,
            key: target.cacheKey,
            uwcId: context.uwcId
        ) else { return nil }
        return W4Loaded(
            W4PageSnapshot(html: page.html, fetchedAt: page.fetchedAt, finalURL: page.finalURL),
            freshness: .cached(fetchedAt: page.fetchedAt, isStale: page.isStale)
        )
    }

    /// Cache-first load. `persist: false` keeps the response out of the on-disk cache entirely —
    /// used by `FeedsRepository`, whose HTML carries password-equivalent tokens.
    func load(
        _ target: W4PageTarget,
        context: W4RequestContext,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important,
        persist: Bool = true
    ) async throws -> W4Loaded<W4PageSnapshot> {
        let cachedPage = persist ? await cached(target, context: context) : nil

        if !forceRefresh, let cachedPage, Self.isUsable(cachedPage.freshness) {
            return cachedPage
        }

        do {
            let response = try await client.fetchRoute(
                route: target.route,
                query: target.query,
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            let fetchedAt = TimeProvider.now
            if persist {
                await cache.store(
                    html: response.html,
                    surface: target.surface,
                    key: target.cacheKey,
                    uwcId: context.uwcId,
                    finalURL: response.finalURL,
                    contentType: response.contentType,
                    fetchedAt: fetchedAt
                )
            }
            return W4Loaded(
                W4PageSnapshot(html: response.html, fetchedAt: fetchedAt, finalURL: response.finalURL),
                freshness: .fresh
            )
        } catch {
            if Self.mustPropagate(error) { throw error }
            guard let cachedPage else { throw error }
            W4PageLoader.warn("\(target.surface.rawValue): fetch failed, serving the cached copy")
            return cachedPage
        }
    }

    /// Errors a repository has no business converting into "here is an old copy".
    ///
    /// `.forbidden` is deliberately absent: a 403 without `Login Required` means the student is
    /// signed in with the wrong role, and treating it as session death ejects them to the login
    /// screen (reviewer-notes.md §3).
    static func mustPropagate(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let w4 = error as? W4Error {
            switch w4 {
            case .sessionExpired, .cookieExpired:
                // Same fact under two names; hiding either strands the app signed-out.
                return true
            default:
                return false
            }
        }
        return false
    }

    /// True when a value may be shown without refetching: straight off the wire, still inside its
    /// TTL, or demo data (which has no server to be stale against).
    ///
    /// Namespaced under this type rather than added as an extension on `W4Freshness`: that enum is
    /// shared by every repository in Wave 5, and a convenience bolted onto it from one file is a
    /// redeclaration waiting to happen.
    static func isUsable(_ freshness: W4Freshness) -> Bool {
        switch freshness {
        case .fresh, .demo:
            return true
        case .cached(_, let isStale):
            return !isStale
        }
    }

    /// Static text only. Never a route with query values, never page content.
    private static func warn(_ message: String) {
        Logger(subsystem: "dk.jonathanb.w4", category: "W4PageLoader")
            .warning("\(message, privacy: .public)")
    }
}

/// Failures that belong to the 5.8b repositories themselves rather than to the transport.
enum HomeRepositoryError: Error, Equatable {
    /// `homePage()` was asked for raw Home markup inside a demo session. There is none, and
    /// fabricating some would push synthetic markup through the real parsers. Demo callers use
    /// `snapshot()`, which returns demo data.
    case demoSessionHasNoHTML
}

// MARK: - The Home snapshot

/// Everything one `r=site/index` response yields, composed once (features.md §1.16).
///
/// Each member is the output of a parser that Wave 4 already verified against `home.html`; this type
/// invents nothing. Optionality is meaningful throughout: `nil` means "Home did not render that
/// block", which is a different fact from an empty block, and the UI must be able to tell them apart.
struct HomeSnapshot: Sendable, Equatable {

    /// Greeting, own UWC id, birthdays, announcements, links, server version.
    let page: HomePage

    /// The `#timetable` grid Home embeds, or `nil` when Home rendered no grid at all.
    ///
    /// W4 does not label the Home grid Academics or Extra Academics, so it is attributed to
    /// ``HomeRepository/homeWeekSource``. `TimetableRepository` (5.1) stays authoritative for the
    /// real AC/EA split; this is the free copy that makes the Home screen render with no extra
    /// request.
    let week: ScheduleWeek?

    /// `#academic-absences` and `#ea-absences`. **[V]**
    let meters: AttendanceMeters

    /// `.status-dropdown`. `nil` when the widget is missing. Read-only here — mutations belong to
    /// `CampusStatusRepository` (5.6, D-23).
    let campus: CampusStatus?

    /// `div.notifications`. Empty is the normal state at this school (bug B8).
    let notifications: W4NotificationSnapshot

    /// When W4 produced the response this was composed from.
    let fetchedAt: Date

    init(
        page: HomePage,
        week: ScheduleWeek?,
        meters: AttendanceMeters,
        campus: CampusStatus?,
        notifications: W4NotificationSnapshot,
        fetchedAt: Date
    ) {
        self.page = page
        self.week = week
        self.meters = meters
        self.campus = campus
        self.notifications = notifications
        self.fetchedAt = fetchedAt
    }

    /// True when Home gave us nothing renderable — a shape change, not an empty school day.
    var isEmpty: Bool {
        page.isEmpty && week == nil && meters.isEmpty && campus == nil && notifications.isEmpty
    }
}

// MARK: - Repository

/// The Home page, fetched at most once.
actor HomeRepository {

    static let shared = HomeRepository()

    /// `W4Surface.home` + this key is the shelf `site/index` lives on. Exposed so a sibling
    /// repository can read the very same cache entry directly if it prefers not to call in here.
    static let cacheKey = W4Routes.R.home

    /// What the Home grid's events are attributed to. Home does not say, and `EventSource` has no
    /// "combined" case; `.academics` is the primary in every merge (`W4TimetableParser.merge`).
    static let homeWeekSource: EventSource = .academics

    private let loader: W4PageLoader
    private let cache: W4PageCache
    private let resolveContext: @Sendable () throws -> W4RequestContext

    /// In-flight fetch, so four screens waking at once cost one request instead of four.
    private var inFlight: Task<W4Loaded<W4PageSnapshot>, Error>?
    private var inFlightID: UInt64 = 0
    private var nextInFlightID: UInt64 = 1

    init(
        client: any W4RouteFetching = W4HTTPClient(),
        cache: W4PageCache = .shared,
        context: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() }
    ) {
        self.loader = W4PageLoader(client: client, cache: cache)
        self.cache = cache
        self.resolveContext = context
    }

    private var target: W4PageTarget {
        W4PageTarget(surface: .home, cacheKey: Self.cacheKey, route: W4Routes.R.home)
    }

    // MARK: - Composed snapshot

    /// Everything the Home screen needs, from one response.
    ///
    /// Cache-first: a Home page inside `CachePolicy.ttl(for: .home)` is composed straight off disk.
    /// Pass `forceRefresh: true` for pull-to-refresh.
    func snapshot(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<HomeSnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoSnapshot(), freshness: .demo)
        }
        let document = try await page(context: context, forceRefresh: forceRefresh, priority: priority)
        return document.map { Self.compose($0) }
    }

    /// The composed snapshot from cache only. Never fetches, never throws — `nil` simply means
    /// "nothing cached yet". This is the instant first paint; follow it with `snapshot()`.
    func cachedSnapshot() async -> W4Loaded<HomeSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoSnapshot(), freshness: .demo)
        }
        guard let document = await loader.cached(target, context: context) else { return nil }
        return document.map { Self.compose($0) }
    }

    // MARK: - Raw page seam

    /// The raw Home HTML, coalesced across callers. This is what the attendance, timetable and
    /// chrome repositories harvest their own parts from.
    ///
    /// Throws in a demo session: there is no Home HTML to hand out, and returning a fabricated page
    /// would put synthetic markup through the real parsers. Demo callers ask for `snapshot()`.
    func homePage(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<W4PageSnapshot> {
        let context = try resolveContext()
        guard !context.isDemo else { throw HomeRepositoryError.demoSessionHasNoHTML }
        return try await page(context: context, forceRefresh: forceRefresh, priority: priority)
    }

    /// The cached Home HTML, or `nil`. Never fetches.
    func cachedHomePage() async -> W4Loaded<W4PageSnapshot>? {
        guard let context = try? resolveContext(), !context.isDemo else { return nil }
        return await loader.cached(target, context: context)
    }

    /// Donate a Home response someone else already has, so the next reader does not refetch it.
    ///
    /// The login flow lands on `site/index`, and the D-23 chrome hook sees every HTML response.
    /// Both hold a Home page this repository would otherwise request again seconds later. Ignored
    /// (silently, by design) in demo or when signed out.
    func ingest(html: String, finalURL: URL? = nil, fetchedAt: Date = TimeProvider.now) async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await cache.store(
            html: html,
            surface: .home,
            key: Self.cacheKey,
            uwcId: context.uwcId,
            finalURL: finalURL,
            contentType: nil,
            fetchedAt: fetchedAt
        )
    }

    /// Drop the cached Home page for the signed-in student.
    func invalidate() async {
        guard let context = try? resolveContext() else { return }
        await cache.remove(surface: .home, key: Self.cacheKey, uwcId: context.uwcId)
    }

    // MARK: - Fetch coalescing

    private func page(
        context: W4RequestContext,
        forceRefresh: Bool,
        priority: FetchPriority
    ) async throws -> W4Loaded<W4PageSnapshot> {
        // A fresh cached page never needs the gate, so check it before joining any in-flight fetch.
        if !forceRefresh,
           let cached = await loader.cached(target, context: context),
           W4PageLoader.isUsable(cached.freshness) {
            return cached
        }

        if !forceRefresh, let existing = inFlight {
            // Someone is already fetching exactly this page. Join them: one request, N readers.
            return try await existing.value
        }

        let id = nextInFlightID
        nextInFlightID &+= 1
        let task = Task<W4Loaded<W4PageSnapshot>, Error> {
            try await self.performLoad(context: context, forceRefresh: forceRefresh, priority: priority)
        }
        inFlight = task
        inFlightID = id

        do {
            let loaded = try await task.value
            clearInFlight(id)
            return loaded
        } catch {
            clearInFlight(id)
            throw error
        }
    }

    /// The actual fetch, kept on the actor so the coalescing `Task` captures nothing but `self`.
    private func performLoad(
        context: W4RequestContext,
        forceRefresh: Bool,
        priority: FetchPriority
    ) async throws -> W4Loaded<W4PageSnapshot> {
        try await loader.load(target, context: context, forceRefresh: forceRefresh, priority: priority)
    }

    private func clearInFlight(_ id: UInt64) {
        guard inFlightID == id else { return }
        inFlight = nil
    }

    // MARK: - Composition

    /// Runs every Home parser over one response. Pure and synchronous: parsers are `nonisolated`,
    /// take no clock and touch no storage, so this is safe to call from any isolation domain.
    static func compose(_ snapshot: W4PageSnapshot) -> HomeSnapshot {
        let html = snapshot.html
        let page = W4HomeParser.parse(html)
        let meters = W4AbsenceParser.parseHomeMeters(html)
        let campus = W4CampusStatusParser.parse(html)
        let notifications = W4NotificationParser.parse(html)

        // The parser is pure and cannot read a clock, so the repository stamps `fetchedAt`.
        let parsed = W4TimetableParser.parseWeek(html: html, source: homeWeekSource)
        let week: ScheduleWeek? = parsed.days.isEmpty
            ? nil
            : ScheduleWeek(
                year: parsed.year,
                week: parsed.week,
                title: parsed.title,
                source: parsed.source,
                startHour: parsed.startHour,
                endHour: parsed.endHour,
                days: parsed.days,
                fetchedAt: snapshot.fetchedAt
            )

        return HomeSnapshot(
            page: page,
            week: week,
            meters: meters,
            campus: campus,
            notifications: notifications,
            fetchedAt: snapshot.fetchedAt
        )
    }

    // MARK: - Demo

    /// What an App Review account sees on Home (features.md §4). Deliberately small and obviously
    /// synthetic: no fabricated timetable — `TimetableRepository` owns the demo week, and two
    /// repositories inventing different demo weeks would contradict each other on one screen.
    static func demoSnapshot(now: Date = TimeProvider.now) -> HomeSnapshot {
        var page = HomePage()
        page.greetingText = "Hello Demo Student"
        page.greetingName = "Demo Student"
        page.uwcId = Student.demoStudentId
        page.announcementsEmptyText = "No announcements..."
        page.serverVersion = "25.9.1"
        page.links = [
            HomeLink(title: "Trip Form", url: W4Routes.url(W4Routes.R.trips), route: W4Routes.R.trips),
            HomeLink(title: "College Policies", url: W4Routes.url(W4Routes.R.documents), route: W4Routes.R.documents)
        ]

        return HomeSnapshot(
            page: page,
            week: nil,
            meters: AttendanceMeters(
                academic: AttendanceMeter(absences: 1, latenesses: 2),
                extraAcademic: AttendanceMeter(absences: 0, latenesses: 0)
            ),
            campus: CampusStatus(isOnCampus: true),
            notifications: .empty,
            fetchedAt: now
        )
    }
}
