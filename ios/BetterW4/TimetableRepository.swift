//
//  TimetableRepository.swift
//  BetterW4
//
//  The daily driver (plan Wave 5.1; features.md §0.2, §1.2, §2.1, §2.5; D-9/D-18/D-22).
//
//  One week of the timetable is two W4 pages that have to be fetched, merged and cached as if
//  they were one:
//
//    * `academics/timetable/mytimetable`      — `.important`, the page the student is waiting for
//    * `extraacademics/timetable/mytimetable` — `.opportunistic`, kayaking and CAS
//
//  They are fetched in parallel and merged by date (`W4TimetableParser.merge`). Every W4 request
//  shares one serial gate, so the priorities are not decoration: an Extra Academics prefetch that
//  queues ahead of the grid the student is staring at makes the app feel broken.
//
//  Three things this file is careful about:
//
//  1. **Home carries the same grid.** `site/index` renders the current week's `#timetable`. When
//     the requested week is the current one and a fresh Home page is already in the page cache,
//     that grid is used instead of issuing a second request for a table we already have.
//  2. **A failed refresh must not lose a good week.** Any failure that is not a dead session
//     falls back to the cached page, and then to the SwiftData store. `W4Error.forbidden` is
//     explicitly *not* a dead session (D-21) — a student who trips a role check keeps their
//     timetable and stays signed in. `W4Error.sessionExpired` is the one error that always
//     propagates, because the app has to re-login.
//  3. **A half-rendered page must not erase real data.** Rows are deleted only after a parse that
//     produced a real grid — `div.column` count ≥ 8, i.e. the hour gutter plus seven days (D-22)
//     — and only for the sources that fetch actually covered.
//

import Foundation
import SwiftSoup

// MARK: - Transport seam

/// One fetched W4 page, decoded.
struct TimetablePageResponse: Sendable {
    let html: String
    let finalURL: URL?

    init(html: String, finalURL: URL? = nil) {
        self.html = html
        self.finalURL = finalURL
    }
}

/// The repository's whole view of the network. It exists so the tests can drive every path —
/// success, EA-only failure, `.forbidden`, `.sessionExpired` — without a socket, and without
/// bending `W4HTTPClient` into a testable shape.
protocol TimetablePageLoading: Sendable {
    func loadPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        uwcId: String,
        priority: FetchPriority
    ) async throws -> TimetablePageResponse
}

/// Live implementation: `W4HTTPClient.get` plus HTML decoding.
///
/// `@unchecked Sendable` is honest here — `W4HTTPClient` holds only two immutable references
/// (`CookieManager.shared`, `KeychainManager.shared`); all of its mutable state lives in the
/// static request limiter and the keychain, both of which are already thread-safe.
final class W4TimetablePageLoader: TimetablePageLoading, @unchecked Sendable {
    private let client: W4HTTPClient

    init(client: W4HTTPClient = W4HTTPClient()) {
        self.client = client
    }

    func loadPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        uwcId: String,
        priority: FetchPriority
    ) async throws -> TimetablePageResponse {
        let response = try await client.get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: uwcId,
            priority: priority
        )
        return TimetablePageResponse(
            html: client.decodeHTML(from: response.data),
            finalURL: response.finalURL
        )
    }
}

// MARK: - Store seam

/// The `ScheduleStore` calls this repository makes, as closures.
///
/// `ScheduleStore` is `@MainActor` and owns a SwiftData `ModelContext`, which is not `Sendable`
/// and must never cross an actor boundary (D-30). Bridging through three `@Sendable` closures
/// keeps the context where it belongs and lets the tests substitute an in-memory double.
struct TimetableStoreBridge: Sendable {
    var load: @Sendable (_ uwcId: String, _ weekKey: String) async -> TimetableWeekSnapshot?
    var persist: @Sendable (
        _ week: ScheduleWeek,
        _ uwcId: String,
        _ weekKey: String,
        _ replacingSources: Set<EventSource>
    ) async -> Void
    var clear: @Sendable (_ uwcId: String) async -> Void

    static let live = TimetableStoreBridge(
        load: { uwcId, weekKey in
            await ScheduleStore.shared.timetableWeek(uwcId: uwcId, weekKey: weekKey)
        },
        persist: { week, uwcId, weekKey, replacingSources in
            await ScheduleStore.shared.persistTimetableWeek(
                week,
                uwcId: uwcId,
                weekKey: weekKey,
                replacingSources: replacingSources
            )
        },
        clear: { uwcId in
            await ScheduleStore.shared.deleteTimetable(uwcId: uwcId)
        }
    )

    /// Reads nothing, writes nothing. For tests and for any caller that only wants the page cache.
    static let disabled = TimetableStoreBridge(
        load: { _, _ in nil },
        persist: { _, _, _, _ in },
        clear: { _ in }
    )
}

// MARK: - Policy

/// How hard the caller wants us to try the network.
///
/// There is no `.cacheOnly`: that is `cachedWeek(containing:)`, which never touches the network
/// and returns `nil` instead of inventing an empty week.
enum TimetableRefreshPolicy: Sendable, Equatable {
    /// Serve a cached week that is still inside its TTL; fetch when it is stale or missing.
    case refreshWhenStale
    /// Always go to W4, and fall back to the cache only if that fails.
    case alwaysRefresh
}

/// D-18: whether `?year=&week=` actually paginates the timetable.
///
/// Both parameters are **unverified** — no capture of a non-current week exists. So the first
/// non-current request is a probe: ask for a week, compare the header dates W4 answers with. On a
/// mismatch, week navigation is switched off rather than silently mislabelling every lesson.
enum TimetableWeekParamSupport: String, Sendable, Equatable {
    case unknown
    case supported
    case unsupported
}

// MARK: - Grid guard

/// D-22's guard: has this page really rendered a grid?
///
/// The captured grid is one hour-gutter column plus seven day columns, so a real page has at
/// least eight `div.column` children. Fewer means a truncated or error page, and a truncated page
/// must never be allowed to delete lessons we already have.
enum TimetableGridGuard {
    static let minimumColumns = 8

    /// Counts `div.column` children of the grid. Bug B1: the grid is the **last** `#timetable`.
    static func columnCount(in html: String) -> Int {
        guard let document = try? SwiftSoup.parse(html),
              let grid = (try? document.select("div#timetable").array())?.last else {
            return 0
        }
        return grid.children().array().filter { element in
            let raw = (try? element.attr("class")) ?? ""
            let classes = Set(
                raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
            )
            return classes.contains("column")
        }.count
    }

    static func hasFullGrid(html: String) -> Bool {
        columnCount(in: html) >= minimumColumns
    }
}

// MARK: - Repository

actor TimetableRepository {

    static let shared = TimetableRepository(
        schoolCalendarOverlay: { year, week in
            guard SettingsStore.shared.showSchoolCalendar else { return nil }
            return await SchoolCalendarRepository.shared.weekOverlay(year: year, week: week)
        }
    )

    private let loader: any TimetablePageLoading
    private let cache: W4PageCache
    private let store: TimetableStoreBridge
    private let resolveContext: @Sendable () throws -> W4RequestContext
    private let clock: @Sendable () -> Date
    /// School Google-Calendar ICS overlay. `nil` ⇒ never fetch. The shared instance wires
    /// `SchoolCalendarRepository` and honours the Settings toggle (off by default, OQ-8).
    private let schoolCalendarOverlay: (@Sendable (_ year: Int, _ week: Int) async -> ScheduleWeek?)?

    /// Whether `?year=&week=` has been proven to work. The UI reads this to decide if the
    /// previous/next-week controls are usable at all (D-18).
    private(set) var weekParamSupport: TimetableWeekParamSupport = .unknown

    var supportsWeekNavigation: Bool {
        weekParamSupport != .unsupported
    }

    init(
        loader: any TimetablePageLoading = W4TimetablePageLoader(),
        cache: W4PageCache = .shared,
        store: TimetableStoreBridge = .live,
        context: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() },
        clock: @escaping @Sendable () -> Date = { TimeProvider.now },
        schoolCalendarOverlay: (@Sendable (_ year: Int, _ week: Int) async -> ScheduleWeek?)? = nil
    ) {
        self.loader = loader
        self.cache = cache
        self.store = store
        self.resolveContext = context
        self.clock = clock
        self.schoolCalendarOverlay = schoolCalendarOverlay
    }

    // MARK: Reading

    /// The week we can render *right now*: cached page first, stored lessons second, `nil` when
    /// this student has never seen that week. Never touches the network, so a screen can call it
    /// before its refresh and paint immediately.
    func cachedWeek(containing date: Date) async -> W4Loaded<ScheduleWeek>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoWeek(containing: date), freshness: .demo)
        }
        let iso = W4Dates.isoWeek(of: date)
        if let cached = await cachedWeek(iso: iso, uwcId: context.uwcId) {
            return cached
        }
        return await storedWeek(iso: iso, uwcId: context.uwcId)
    }

    /// The week, refreshed according to `policy`.
    ///
    /// Throws only when there is genuinely nothing to show: a dead session (always), or a failure
    /// with no cached page and no stored lessons behind it.
    @discardableResult
    func week(
        containing date: Date,
        policy: TimetableRefreshPolicy = .refreshWhenStale
    ) async throws -> W4Loaded<ScheduleWeek> {
        let context = try resolveContext()
        if context.isDemo {
            // Demo never touches the network — the branch is here, before any fetch, on purpose.
            return W4Loaded(Self.demoWeek(containing: date), freshness: .demo)
        }

        let iso = W4Dates.isoWeek(of: date)
        let uwcId = context.uwcId
        let cached = await cachedWeek(iso: iso, uwcId: uwcId)

        if policy == .refreshWhenStale, let cached, !Self.isStale(cached) {
            return await overlaySchoolCalendar(cached)
        }

        do {
            return try await fetchWeek(iso: iso, context: context)
        } catch {
            if let w4Error = error as? W4Error, case .sessionExpired = w4Error {
                // Never swallowed: the app has to route the student back to login.
                throw error
            }
            // Everything else — including `.forbidden`, which must NOT log anybody out — keeps
            // whatever good copy we already hold.
            if let cached {
                return cached
            }
            if let stored = await storedWeek(iso: iso, uwcId: uwcId) {
                return stored
            }
            throw error
        }
    }

    /// Convenience for pull-to-refresh.
    @discardableResult
    func refresh(weekContaining date: Date) async throws -> W4Loaded<ScheduleWeek> {
        try await week(containing: date, policy: .alwaysRefresh)
    }

    // MARK: Cache maintenance

    /// Drops the cached pages for one week, so the next read must go to W4.
    func invalidate(weekContaining date: Date) async {
        guard let context = try? resolveContext() else { return }
        let iso = W4Dates.isoWeek(of: date)
        let weekKey = ScheduleIdentity.weekKey(year: iso.year, week: iso.week)
        await cache.remove(
            surface: .timetableAcademics,
            key: Self.cacheKey(route: W4Routes.R.myTimetable, weekKey: weekKey),
            uwcId: context.uwcId
        )
        await cache.remove(
            surface: .timetableExtraAcademics,
            key: Self.cacheKey(route: W4Routes.R.eaTimetable, weekKey: weekKey),
            uwcId: context.uwcId
        )
    }

    /// Sign-out / "Clear cache": forget every stored lesson for the signed-in student.
    func clearStoredLessons() async {
        guard let context = try? resolveContext() else { return }
        await store.clear(context.uwcId)
    }

    // MARK: - Fetching

    private func fetchWeek(
        iso: (year: Int, week: Int),
        context: W4RequestContext
    ) async throws -> W4Loaded<ScheduleWeek> {
        let uwcId = context.uwcId
        let isCurrentWeek = Self.isCurrentWeek(iso, now: clock())
        let query = try weekQuery(iso: iso, isCurrentWeek: isCurrentWeek)

        // Home already carries this grid when the requested week is the current one. Reuse it
        // rather than asking W4 to render the same table twice.
        var academicsHTML: String?
        var academicsWeekFromHome: ScheduleWeek?
        var servedFrom: Date?
        if isCurrentWeek,
           let home = await borrowedHomePage(uwcId: uwcId, requireFresh: true),
           let homeGrid = Self.academicsGrid(in: home.html, forWeek: iso) {
            academicsHTML = home.html
            academicsWeekFromHome = homeGrid
            servedFrom = home.fetchedAt
        }

        async let academicsTask = self.loadPage(
            route: W4Routes.R.myTimetable,
            query: query,
            context: context,
            priority: .important,
            skip: academicsHTML != nil,
            tolerateFailure: false
        )
        async let extraTask = self.loadPage(
            route: W4Routes.R.eaTimetable,
            query: query,
            context: context,
            priority: .opportunistic,
            skip: false,
            tolerateFailure: true
        )

        let academics = try await academicsTask
        let extra = try await extraTask

        guard let primaryHTML = academicsHTML ?? academics?.html else {
            throw W4Error.noResponse
        }

        let academicsWeek = academicsWeekFromHome ?? W4TimetableParser.parseWeek(
            html: primaryHTML,
            source: .academics,
            fallbackYear: iso.year,
            fallbackWeek: iso.week
        )
        guard !academicsWeek.days.isEmpty else {
            // No day columns at all: a truncated page, an error page, or markup we do not know.
            // Treat it as a failed fetch so the caller keeps the copy it already had.
            throw W4Error.parsingError("timetable page carried no day columns")
        }

        var merged = academicsWeek
        var sources: Set<EventSource> = [.academics]

        if let extraHTML = extra?.html {
            let extraWeek = W4TimetableParser.parseWeek(
                html: extraHTML,
                source: .extraAcademics,
                fallbackYear: academicsWeek.year,
                fallbackWeek: academicsWeek.week
            )
            // Only merge grids that describe the same week — a stale or redirected EA page must
            // not scatter its lessons across the wrong days.
            if extraWeek.year == academicsWeek.year, extraWeek.week == academicsWeek.week {
                merged = W4TimetableParser.merge(academicsWeek, with: extraWeek)
                sources.insert(.extraAcademics)
            }
        }

        // D-18 probe: did W4 honour the week parameters at all?
        if !query.isEmpty {
            weekParamSupport = (merged.year == iso.year && merged.week == iso.week)
                ? .supported
                : .unsupported
        }

        // Always key on the week W4 actually answered with, never on the one we asked for. If the
        // probe just failed, writing this grid under the requested key would poison the cache.
        let weekKey = ScheduleIdentity.weekKey(year: merged.year, week: merged.week)
        let fetchedAt = servedFrom ?? clock()

        await cache.store(
            html: primaryHTML,
            surface: .timetableAcademics,
            key: Self.cacheKey(route: W4Routes.R.myTimetable, weekKey: weekKey),
            uwcId: uwcId,
            finalURL: academics?.finalURL,
            contentType: Self.htmlContentType,
            fetchedAt: fetchedAt
        )
        if let extra, sources.contains(.extraAcademics) {
            await cache.store(
                html: extra.html,
                surface: .timetableExtraAcademics,
                key: Self.cacheKey(route: W4Routes.R.eaTimetable, weekKey: weekKey),
                uwcId: uwcId,
                finalURL: extra.finalURL,
                contentType: Self.htmlContentType,
                fetchedAt: clock()
            )
        }

        let week = merged.withFetchedAt(fetchedAt)

        // D-22: delete only what this fetch can actually vouch for. An empty set means
        // "upsert, delete nothing". School-calendar events are not stored here — the ICS
        // overlay is applied after persist so a later toggle cannot duplicate them.
        let replacingSources = TimetableGridGuard.hasFullGrid(html: primaryHTML)
            ? sources
            : Set<EventSource>()
        await store.persist(week, uwcId, weekKey, replacingSources)

        let presented = await overlaySchoolCalendarIfNeeded(week) ?? week

        // Reusing Home is still cached data, and saying otherwise would put a false
        // "just now" under a grid that may be a quarter of an hour old.
        if let servedFrom {
            return W4Loaded(presented, freshness: .cached(fetchedAt: servedFrom, isStale: false))
        }
        return W4Loaded(presented, freshness: .fresh)
    }

    /// One page fetch, with the two behaviours the caller needs to vary: skip it entirely (we
    /// already have the HTML), and tolerate its failure (Extra Academics is a bonus, not the
    /// screen). A dead session is never tolerated.
    ///
    /// `nonisolated` so the two `async let`s above really do run side by side instead of taking
    /// turns on the actor; it reads nothing but the immutable, `Sendable` `loader`.
    private nonisolated func loadPage(
        route: String,
        query: [String: String],
        context: W4RequestContext,
        priority: FetchPriority,
        skip: Bool,
        tolerateFailure: Bool
    ) async throws -> TimetablePageResponse? {
        guard !skip else { return nil }
        do {
            return try await loader.loadPage(
                route: route,
                query: query,
                credentials: context.credentials,
                uwcId: context.uwcId,
                priority: priority
            )
        } catch {
            if let w4Error = error as? W4Error, case .sessionExpired = w4Error { throw error }
            guard tolerateFailure else { throw error }
            #if DEBUG
            print("⚠️ [TimetableRepository] optional page \(route) failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// D-18: the current week is fetched from the bare route, because that is the only request
    /// shape any capture proves. Other weeks carry `year`/`week` — until the probe says they do
    /// nothing, after which asking is pointless and we say so instead of returning a wrong week.
    private func weekQuery(iso: (year: Int, week: Int), isCurrentWeek: Bool) throws -> [String: String] {
        guard !isCurrentWeek else { return [:] }
        guard weekParamSupport != .unsupported else {
            throw W4Error.parsingError(Self.weekNavigationUnsupported)
        }
        return ["year": String(iso.year), "week": String(iso.week)]
    }

    // MARK: - Cached reads

    private func cachedWeek(iso: (year: Int, week: Int), uwcId: String) async -> W4Loaded<ScheduleWeek>? {
        let weekKey = ScheduleIdentity.weekKey(year: iso.year, week: iso.week)

        var academicsWeek: ScheduleWeek?
        var fetchedAt = Date.distantPast
        var isStale = false

        if let page = await cache.page(
            surface: .timetableAcademics,
            key: Self.cacheKey(route: W4Routes.R.myTimetable, weekKey: weekKey),
            uwcId: uwcId
        ) {
            let parsed = W4TimetableParser.parseWeek(
                html: page.html,
                source: .academics,
                fallbackYear: iso.year,
                fallbackWeek: iso.week
            )
            if !parsed.days.isEmpty {
                academicsWeek = parsed
                fetchedAt = page.fetchedAt
                isStale = page.isStale
            }
        }

        if academicsWeek == nil, Self.isCurrentWeek(iso, now: clock()) {
            // No timetable page yet, but Home may already hold this week's grid.
            if let home = await borrowedHomePage(uwcId: uwcId, requireFresh: false),
               let grid = Self.academicsGrid(in: home.html, forWeek: iso) {
                academicsWeek = grid
                fetchedAt = home.fetchedAt
                isStale = home.isStale
            }
        }

        guard var week = academicsWeek else { return nil }

        if let page = await cache.page(
            surface: .timetableExtraAcademics,
            key: Self.cacheKey(route: W4Routes.R.eaTimetable, weekKey: weekKey),
            uwcId: uwcId
        ) {
            let extraWeek = W4TimetableParser.parseWeek(
                html: page.html,
                source: .extraAcademics,
                fallbackYear: week.year,
                fallbackWeek: week.week
            )
            if extraWeek.year == week.year, extraWeek.week == week.week {
                week = W4TimetableParser.merge(week, with: extraWeek)
                // The honest timestamp of a merged pair is its oldest ingredient.
                fetchedAt = min(fetchedAt, page.fetchedAt)
                isStale = isStale || page.isStale
            }
        }

        let loaded = W4Loaded(
            week.withFetchedAt(fetchedAt),
            freshness: W4Freshness.cached(fetchedAt: fetchedAt, isStale: isStale)
        )
        return await overlaySchoolCalendar(loaded)
    }

    /// Lays the school Google Calendar over a week when the overlay hook is wired
    /// and the student has it turned on. Identity function otherwise.
    private func overlaySchoolCalendar(_ loaded: W4Loaded<ScheduleWeek>) async -> W4Loaded<ScheduleWeek> {
        guard let overlaid = await overlaySchoolCalendarIfNeeded(loaded.value) else { return loaded }
        return W4Loaded(overlaid.withFetchedAt(loaded.value.fetchedAt), freshness: loaded.freshness)
    }

    private func overlaySchoolCalendarIfNeeded(_ week: ScheduleWeek) async -> ScheduleWeek? {
        guard let schoolCalendarOverlay,
              let overlay = await schoolCalendarOverlay(week.year, week.week) else {
            return nil
        }
        let withoutCalendar = week.withDays(
            week.days.map { day in
                day.withEvents(day.events.filter { !SchoolCalendar.isSchoolCalendarEvent($0) })
            }
        )
        return SchoolCalendar.overlay(withoutCalendar, with: overlay.allEvents)
    }

    /// The last resort: rebuild a week out of stored lessons when both W4 and the page cache are
    /// gone. Lossy on purpose — `eaNote`, attendance markers and tooltips are not columns — so it
    /// is only ever reached after the cached page has been ruled out.
    private func storedWeek(iso: (year: Int, week: Int), uwcId: String) async -> W4Loaded<ScheduleWeek>? {
        let weekKey = ScheduleIdentity.weekKey(year: iso.year, week: iso.week)
        guard let snapshot = await store.load(uwcId, weekKey), !snapshot.isEmpty,
              let monday = W4Dates.startOfISOWeek(year: iso.year, week: iso.week) else {
            return nil
        }

        let now = clock()
        let eventsByDay = Dictionary(grouping: snapshot.events) { W4Dates.startOfDay($0.date) }
        let days = (0..<7).map { offset -> ScheduleDay in
            let date = W4Dates.startOfDay(W4Dates.adding(days: offset, to: monday))
            return ScheduleDay(
                date: date,
                dayName: W4Dates.weekdayName(of: date),
                rotationDay: snapshot.rotationDays[date],
                isNoClasses: false,
                eaNote: nil,
                isToday: W4Dates.isSameDay(date, now),
                events: eventsByDay[date] ?? []
            )
        }

        let week = ScheduleWeek(
            year: iso.year,
            week: iso.week,
            title: nil,
            source: .academics,
            days: days,
            fetchedAt: snapshot.updatedAt
        )
        let loaded = W4Loaded(
            week,
            freshness: .cached(
                fetchedAt: snapshot.updatedAt,
                isStale: !CachePolicy.isFresh(snapshot.updatedAt, for: .timetableAcademics, now: now)
            )
        )
        return await overlaySchoolCalendar(loaded)
    }

    // MARK: - Helpers

    static let weekNavigationUnsupported =
        "W4 ignored the week parameters, so only the current week can be shown"

    private static let htmlContentType = "text/html"

    /// Home page keys we are willing to **read**. `site/index` is fetched once and its parts are
    /// distributed (plan §1.3); `HomeRepository` stores it under `W4Routes.R.home`. The alternate
    /// is one extra file lookup that keeps the zero-request path alive if that ever changes. This
    /// repository never *writes* a Home page.
    private static let homeCacheKeys = [W4Routes.R.home, "home"]

    /// The Home page someone else already fetched, if there is one.
    private func borrowedHomePage(uwcId: String, requireFresh: Bool) async -> CachedPage? {
        for key in Self.homeCacheKeys {
            if requireFresh {
                if let page = await cache.freshPage(surface: .home, key: key, uwcId: uwcId) {
                    return page
                }
            } else if let page = await cache.page(surface: .home, key: key, uwcId: uwcId) {
                return page
            }
        }
        return nil
    }

    /// `"<route>|2026-W33"` — one cache entry per route per ISO week.
    private static func cacheKey(route: String, weekKey: String) -> String {
        "\(route)|\(weekKey)"
    }

    private static func isCurrentWeek(_ iso: (year: Int, week: Int), now: Date) -> Bool {
        let current = W4Dates.isoWeek(of: now)
        return current.year == iso.year && current.week == iso.week
    }

    private static func isStale(_ loaded: W4Loaded<ScheduleWeek>) -> Bool {
        if case .cached(_, let isStale) = loaded.freshness { return isStale }
        return false
    }

    /// Parses a page's grid and returns it **only** if it really is the requested week. No
    /// fallback year/week here on purpose: the whole point is to check the header dates, and a
    /// fallback would make any page match.
    private static func academicsGrid(in html: String, forWeek iso: (year: Int, week: Int)) -> ScheduleWeek? {
        let week = W4TimetableParser.parseWeek(html: html, source: .academics)
        guard !week.days.isEmpty, week.year == iso.year, week.week == iso.week else { return nil }
        return week
    }

    // MARK: - Demo

    /// A plausible IB week for App Review. Built from the clock so it is always "this week", and
    /// never fetched — `week(containing:)` returns this before it can reach any network code.
    static func demoWeek(containing date: Date) -> ScheduleWeek {
        let iso = W4Dates.isoWeek(of: date)
        guard let monday = W4Dates.startOfISOWeek(year: iso.year, week: iso.week) else {
            return ScheduleWeek.empty(source: .academics)
        }

        let days: [ScheduleDay] = (0..<7).map { offset in
            let day = W4Dates.startOfDay(W4Dates.adding(days: offset, to: monday))
            let isWeekend = offset >= 5
            let events: [TimetableEvent] = isWeekend ? [] : demoLessons.enumerated().map { slot, lesson in
                TimetableEvent(
                    id: "\(lesson.source.idPrefix)-demo-\(offset)-\(slot)",
                    title: lesson.title,
                    subject: lesson.subject,
                    source: lesson.source,
                    start: W4Dates.date(onDayOf: day, minutesFromMidnight: lesson.start),
                    end: W4Dates.date(onDayOf: day, minutesFromMidnight: lesson.end),
                    date: day,
                    room: lesson.room,
                    teacher: lesson.teacher,
                    status: .normal,
                    isAllDay: false
                )
            }
            return ScheduleDay(
                date: day,
                dayName: W4Dates.weekdayName(of: day),
                rotationDay: isWeekend ? "Weekend" : "Day \(offset + 1)",
                isNoClasses: isWeekend,
                eaNote: isWeekend ? nil : "Sea Kayaking",
                isToday: W4Dates.isSameDay(day, date),
                events: events
            )
        }

        return ScheduleWeek(
            year: iso.year,
            week: iso.week,
            title: "Demo week \(iso.week)",
            source: .academics,
            days: days,
            fetchedAt: date
        )
    }

    private static let demoLessons: [(
        title: String,
        subject: String,
        room: String,
        teacher: String,
        start: Int,
        end: Int,
        source: EventSource
    )] = [
        ("Biology HL", "Biology", "Lab 2", "A. Nordby", 8 * 60 + 30, 9 * 60 + 50, .academics),
        ("Mathematics AA SL", "Mathematics", "R14", "P. Haugen", 10 * 60 + 10, 11 * 60 + 30, .academics),
        ("English A Lang & Lit", "English", "R7", "S. Duncan", 11 * 60 + 40, 13 * 60, .academics),
        ("Theory of Knowledge", "TOK", "R2", "M. Iversen", 14 * 60, 15 * 60 + 20, .academics),
        ("Sea Kayaking", "Sea Kayaking", "Boathouse", "T. Lie", 16 * 60, 17 * 60 + 30, .extraAcademics)
    ]
}
