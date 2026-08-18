//
//  TimetableRepositoryTests.swift
//  BetterW4Tests
//
//  These tests never touch the network and never touch the real caches:
//
//    * the transport is a `TimetablePageLoading` stub that records every call it is asked to make
//      (route, query, priority) and answers from a canned table;
//    * the page cache is a real `W4PageCache` rooted in a per-test temporary directory, so the
//      TTL logic under test is the shipping one;
//    * the SwiftData store is a `TimetableStoreBridge` double, so nothing here opens a store file.
//
//  The HTML is synthesized from the shape of the one real capture (`home.html`): two nested
//  `#timetable` elements, a `#timetable-header` whose first cell is the empty gutter header, an
//  hour-gutter `.column` full of `.cell` labels and one `.column` per day. Lesson blocks are
//  **[I]** — no `.period` element has ever been captured — so the assertions about them are
//  assertions about *our* parser and repository, not about W4's markup.
//

import XCTest
@testable import BetterW4

// MARK: - Doubles

/// Records every request and answers from a canned table keyed by route.
private actor StubTimetableLoader: TimetablePageLoading {

    struct Call: Equatable, Sendable {
        let route: String
        let query: [String: String]
        /// `FetchPriority` spelled as a string so the recording stays comparable.
        let priority: String
    }

    private var responses: [String: Result<TimetablePageResponse, any Error>]
    private var recorded: [Call] = []

    init(responses: [String: Result<TimetablePageResponse, any Error>] = [:]) {
        self.responses = responses
    }

    func loadPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        uwcId: String,
        priority: FetchPriority
    ) async throws -> TimetablePageResponse {
        recorded.append(
            Call(
                route: route,
                query: query,
                priority: priority == .important ? "important" : "opportunistic"
            )
        )
        switch responses[route] {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case nil:
            throw W4Error.httpError(status: 404, route: route)
        }
    }

    func calls() -> [Call] { recorded }
    func routes() -> [String] { recorded.map(\.route) }
    func setResponse(_ result: Result<TimetablePageResponse, any Error>, for route: String) {
        responses[route] = result
    }
}

/// In-memory stand-in for `ScheduleStore`, so no test opens `Timetable.store`.
private actor FakeTimetableStore {

    struct PersistCall: Sendable {
        let weekKey: String
        let eventIDs: [String]
        let replacingSources: Set<EventSource>
    }

    private var snapshots: [String: TimetableWeekSnapshot] = [:]
    private var persists: [PersistCall] = []
    private var cleared: [String] = []

    func seed(_ snapshot: TimetableWeekSnapshot) {
        snapshots[snapshot.weekKey] = snapshot
    }

    func load(weekKey: String) -> TimetableWeekSnapshot? { snapshots[weekKey] }

    func record(week: ScheduleWeek, weekKey: String, replacingSources: Set<EventSource>) {
        persists.append(
            PersistCall(
                weekKey: weekKey,
                eventIDs: week.allEvents.map(\.id),
                replacingSources: replacingSources
            )
        )
    }

    func clear(uwcId: String) { cleared.append(uwcId) }

    func persistCalls() -> [PersistCall] { persists }
    func clearedIDs() -> [String] { cleared }

    nonisolated func bridge() -> TimetableStoreBridge {
        TimetableStoreBridge(
            load: { _, weekKey in await self.load(weekKey: weekKey) },
            persist: { week, _, weekKey, sources in
                await self.record(week: week, weekKey: weekKey, replacingSources: sources)
            },
            clear: { uwcId in await self.clear(uwcId: uwcId) }
        )
    }
}

// MARK: - Tests

final class TimetableRepositoryTests: XCTestCase {

    /// Every test pins "now" to the real clock, because `W4PageCache` stamps and judges its own
    /// entries with `TimeProvider.now`; a fake clock days away from it would make every stored
    /// page look ancient and quietly change what is being tested.
    private var now: Date!
    private var cacheRoot: URL!

    private let uwcId = "nc26test"

    override func setUpWithError() throws {
        now = Date()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimetableRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
    }

    // MARK: Demo

    func testDemoSessionReturnsDemoWeekAndNeverFetches() async throws {
        let loader = StubTimetableLoader()
        let repository = makeRepository(loader: loader, isDemo: true)

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(loaded.value.days.count, 7)
        XCTAssertTrue(loaded.value.hasEvents, "the demo week must look like a real week")
        let calls = await loader.calls()
        XCTAssertTrue(calls.isEmpty, "demo mode must branch before any network call")
    }

    // MARK: Cold store

    func testColdStoreRendersFromNetworkAndMergesExtraAcademics() async throws {
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsWeekHTML()))
        ])
        let repository = makeRepository(loader: loader)

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.days.count, 7)
        let ids = loaded.value.allEvents.map(\.id)
        XCTAssertTrue(ids.contains("ac-w4-42"), "Academics lesson missing: \(ids)")
        XCTAssertTrue(ids.contains("ea-w4-42"), "Extra Academics lesson missing: \(ids)")
        XCTAssertEqual(
            Set(loaded.value.allEvents.map(\.source)),
            [.academics, .extraAcademics],
            "the two grids must be merged, not replaced"
        )
    }

    func testAcademicsIsImportantAndExtraAcademicsIsOpportunistic() async throws {
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsWeekHTML()))
        ])
        let repository = makeRepository(loader: loader)

        _ = try await repository.week(containing: now, policy: .alwaysRefresh)

        let calls = await loader.calls()
        XCTAssertEqual(calls.count, 2)
        let byRoute = Dictionary(uniqueKeysWithValues: calls.map { ($0.route, $0.priority) })
        // One serial gate for all W4 traffic: EA must never queue ahead of the grid on screen.
        XCTAssertEqual(byRoute[W4Routes.R.myTimetable], "important")
        XCTAssertEqual(byRoute[W4Routes.R.eaTimetable], "opportunistic")
    }

    /// D-18: the current week is the bare route. `?year=&week=` is unverified and is only used
    /// for navigation, behind the probe.
    func testCurrentWeekIsFetchedFromTheBareRoute() async throws {
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsWeekHTML()))
        ])
        let repository = makeRepository(loader: loader)

        _ = try await repository.week(containing: now, policy: .alwaysRefresh)

        let calls = await loader.calls()
        XCTAssertTrue(calls.allSatisfy { $0.query.isEmpty }, "no week parameters for the current week")
    }

    // MARK: Warm cache

    func testWarmCacheRendersOfflineWithoutFetching() async throws {
        let cache = makeCache()
        await seedTimetablePages(in: cache, fetchedAt: now)

        // A loader that answers nothing: if the repository touches it, the test fails loudly.
        let loader = StubTimetableLoader()
        let repository = makeRepository(loader: loader, cache: cache)

        let loaded = try await repository.week(containing: now, policy: .refreshWhenStale)

        assertCached(loaded.freshness, at: now, isStale: false)
        XCTAssertTrue(loaded.value.allEvents.map(\.id).contains("ac-w4-42"))
        let calls = await loader.calls()
        XCTAssertTrue(calls.isEmpty, "a fresh cached week must render with no request at all")
    }

    func testCachedWeekIsAvailableBeforeAnyRefresh() async throws {
        let cache = makeCache()
        await seedTimetablePages(in: cache, fetchedAt: now)
        let repository = makeRepository(loader: StubTimetableLoader(), cache: cache)

        let cached = await repository.cachedWeek(containing: now)

        XCTAssertNotNil(cached, "the screen must be able to paint before the refresh starts")
        assertCached(try XCTUnwrap(cached).freshness, at: now, isStale: false)
    }

    func testFailedRefreshKeepsTheCachedWeek() async throws {
        let cache = makeCache()
        let stampedAt = now.addingTimeInterval(-2 * 60 * 60) // past the 30-minute timetable TTL
        await seedTimetablePages(in: cache, fetchedAt: stampedAt)

        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .failure(URLError(.notConnectedToInternet)),
            W4Routes.R.eaTimetable: .failure(URLError(.notConnectedToInternet))
        ])
        let repository = makeRepository(loader: loader, cache: cache)

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)

        assertCached(loaded.freshness, at: stampedAt, isStale: true)
        XCTAssertTrue(loaded.value.allEvents.map(\.id).contains("ac-w4-42"))
    }

    /// The one error that must never be swallowed: the app has to send the student back to login.
    func testSessionExpiredPropagatesEvenWhenACachedWeekExists() async throws {
        let cache = makeCache()
        await seedTimetablePages(in: cache, fetchedAt: now.addingTimeInterval(-2 * 60 * 60))

        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .failure(W4Error.sessionExpired),
            W4Routes.R.eaTimetable: .failure(W4Error.sessionExpired)
        ])
        let repository = makeRepository(loader: loader, cache: cache)

        do {
            _ = try await repository.week(containing: now, policy: .alwaysRefresh)
            XCTFail("sessionExpired must propagate rather than resolve to the cached week")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// D-21: a 403 without "Login Required" means wrong role, not dead session. The student keeps
    /// their timetable and stays signed in.
    func testForbiddenIsNotADeadSessionAndFallsBackToTheCache() async throws {
        let cache = makeCache()
        let stampedAt = now.addingTimeInterval(-2 * 60 * 60)
        await seedTimetablePages(in: cache, fetchedAt: stampedAt)

        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .failure(W4Error.forbidden),
            W4Routes.R.eaTimetable: .failure(W4Error.forbidden)
        ])
        let repository = makeRepository(loader: loader, cache: cache)

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)
        assertCached(loaded.freshness, at: stampedAt, isStale: true)
    }

    func testFailureWithNothingCachedThrows() async throws {
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .failure(W4Error.httpError(status: 500, route: W4Routes.R.myTimetable)),
            W4Routes.R.eaTimetable: .failure(W4Error.httpError(status: 500, route: W4Routes.R.eaTimetable))
        ])
        let repository = makeRepository(loader: loader)

        do {
            _ = try await repository.week(containing: now, policy: .alwaysRefresh)
            XCTFail("with no cache and no store there is nothing honest to return")
        } catch {
            // expected
        }
    }

    // MARK: Store fallback

    func testStoredLessonsRebuildTheWeekWhenThePageCacheIsEmpty() async throws {
        let store = FakeTimetableStore()
        let monday = startOfCurrentWeek()
        let weekKey = ScheduleIdentity.weekKey(for: now)
        await store.seed(
            TimetableWeekSnapshot(
                weekKey: weekKey,
                events: [
                    TimetableEvent(
                        id: "ac-w4-42",
                        title: "Biology HL",
                        source: .academics,
                        start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
                        end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
                        date: monday
                    )
                ],
                rotationDays: [monday: "Day 1"],
                updatedAt: now.addingTimeInterval(-45 * 60)
            )
        )

        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .failure(URLError(.timedOut)),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader, store: store.bridge())

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)

        XCTAssertEqual(loaded.value.days.count, 7, "a rebuilt week is still seven days")
        XCTAssertEqual(loaded.value.allEvents.map(\.id), ["ac-w4-42"])
        XCTAssertEqual(loaded.value.days.first?.rotationDay, "Day 1")
        XCTAssertTrue(loaded.freshness.isFromCache)
    }

    // MARK: D-22 — delete-on-successful-parse

    func testFullGridAuthorisesDeletingBothSources() async throws {
        let store = FakeTimetableStore()
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsWeekHTML()))
        ])
        let repository = makeRepository(loader: loader, store: store.bridge())

        _ = try await repository.week(containing: now, policy: .alwaysRefresh)

        let calls = await store.persistCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.replacingSources, [.academics, .extraAcademics])
        XCTAssertEqual(calls.first?.weekKey, ScheduleIdentity.weekKey(for: now))
        XCTAssertEqual(calls.first?.eventIDs.sorted(), ["ac-w4-42", "ea-w4-42"])
    }

    /// The whole point of D-22: a page that rendered two columns instead of eight must be stored,
    /// but must never be allowed to delete the week it failed to render.
    func testHalfRenderedGridNeverAuthorisesDeletes() async throws {
        let store = FakeTimetableStore()
        let truncated = academicsWeekHTML(dayColumns: 2)
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(truncated)),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader, store: store.bridge())

        _ = try await repository.week(containing: now, policy: .alwaysRefresh)

        let calls = await store.persistCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.replacingSources, Set<EventSource>(), "a truncated grid deletes nothing")
        XCTAssertLessThan(TimetableGridGuard.columnCount(in: truncated), TimetableGridGuard.minimumColumns)
    }

    /// EA failed, AC succeeded: the week renders, and nothing authorises deleting EA lessons we
    /// simply did not fetch.
    func testExtraAcademicsFailureDegradesToAcademicsOnly() async throws {
        let store = FakeTimetableStore()
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader, store: store.bridge())

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.allEvents.map(\.id), ["ac-w4-42"])
        let calls = await store.persistCalls()
        XCTAssertEqual(calls.first?.replacingSources, [.academics])
    }

    // MARK: Home reuse

    func testCurrentWeekReusesACachedHomeGridInsteadOfRefetchingAcademics() async throws {
        let cache = makeCache()
        let homeFetchedAt = now.addingTimeInterval(-60) // inside Home's 15-minute TTL
        await cache.store(
            html: academicsWeekHTML(),
            surface: .home,
            key: W4Routes.R.home,
            uwcId: uwcId,
            fetchedAt: homeFetchedAt
        )

        let loader = StubTimetableLoader(responses: [
            W4Routes.R.eaTimetable: .success(response(extraAcademicsWeekHTML()))
        ])
        let repository = makeRepository(loader: loader, cache: cache)

        let loaded = try await repository.week(containing: now, policy: .alwaysRefresh)

        let routes = await loader.routes()
        XCTAssertEqual(routes, [W4Routes.R.eaTimetable], "Home already holds the Academics grid")
        // A grid borrowed from Home is cached data, not a fresh fetch.
        assertCached(loaded.freshness, at: homeFetchedAt, isStale: false)
        let ids = loaded.value.allEvents.map(\.id)
        XCTAssertTrue(ids.contains("ac-w4-42"))
        XCTAssertTrue(ids.contains("ea-w4-42"))
    }

    func testNonCurrentWeekDoesNotBorrowTheHomeGrid() async throws {
        let cache = makeCache()
        await cache.store(
            html: academicsWeekHTML(),
            surface: .home,
            key: W4Routes.R.home,
            uwcId: uwcId,
            fetchedAt: now
        )
        let nextWeek = W4Dates.adding(days: 7, to: now)
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML(monday: startOfWeek(offsetWeeks: 1)))),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader, cache: cache)

        _ = try await repository.week(containing: nextWeek, policy: .alwaysRefresh)

        let routes = await loader.routes()
        XCTAssertTrue(
            routes.contains(W4Routes.R.myTimetable),
            "Home only ever carries the current week, so another week must be fetched"
        )
    }

    // MARK: D-18 — week parameter probe

    func testWeekParametersAreSentForOtherWeeksAndMarkedSupportedWhenHonoured() async throws {
        let nextMonday = startOfWeek(offsetWeeks: 1)
        let nextWeek = W4Dates.adding(days: 7, to: now)
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML(monday: nextMonday))),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader)

        let loaded = try await repository.week(containing: nextWeek, policy: .alwaysRefresh)

        let iso = W4Dates.isoWeek(of: nextWeek)
        let calls = await loader.calls()
        let academicsCall = calls.first { $0.route == W4Routes.R.myTimetable }
        XCTAssertEqual(academicsCall?.query["week"], String(iso.week))
        XCTAssertEqual(academicsCall?.query["year"], String(iso.year))
        XCTAssertEqual(loaded.value.week, iso.week)

        let support = await repository.weekParamSupport
        XCTAssertEqual(support, .supported)
        let canNavigate = await repository.supportsWeekNavigation
        XCTAssertTrue(canNavigate)
    }

    /// The self-verifying half of D-18: if W4 answers with the current week no matter what we ask
    /// for, week navigation is switched off instead of mislabelling every lesson.
    func testIgnoredWeekParametersDisableNavigation() async throws {
        let loader = StubTimetableLoader(responses: [
            // W4 answers with the CURRENT week regardless of the requested one.
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader)
        let nextWeek = W4Dates.adding(days: 7, to: now)

        let loaded = try await repository.week(containing: nextWeek, policy: .alwaysRefresh)

        // The week is returned with its *honest* identity — the one W4 actually rendered.
        XCTAssertEqual(loaded.value.week, W4Dates.isoWeek(of: now).week)
        let support = await repository.weekParamSupport
        XCTAssertEqual(support, .unsupported)
        let canNavigate = await repository.supportsWeekNavigation
        XCTAssertFalse(canNavigate)

        // And a second attempt does not waste a request on a parameter we know is ignored.
        let callsBefore = await loader.calls().count
        do {
            _ = try await repository.week(
                containing: W4Dates.adding(days: 14, to: now),
                policy: .alwaysRefresh
            )
            XCTFail("navigation is disabled; the repository must say so rather than lie")
        } catch {
            let callsAfter = await loader.calls().count
            XCTAssertEqual(callsBefore, callsAfter, "no request should be issued once the probe failed")
        }
    }

    /// A grid answered for the wrong week is cached under the week it really describes, so the
    /// cache can never hand back a week under a key it does not belong to.
    func testAWeekIsCachedUnderTheWeekW4ActuallyReturned() async throws {
        let cache = makeCache()
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .failure(URLError(.timedOut))
        ])
        let repository = makeRepository(loader: loader, cache: cache)
        let nextWeek = W4Dates.adding(days: 7, to: now)

        _ = try await repository.week(containing: nextWeek, policy: .alwaysRefresh)

        let currentKey = ScheduleIdentity.weekKey(for: now)
        let nextKey = ScheduleIdentity.weekKey(for: nextWeek)
        let underCurrent = await cache.page(
            surface: .timetableAcademics,
            key: "\(W4Routes.R.myTimetable)|\(currentKey)",
            uwcId: uwcId
        )
        let underNext = await cache.page(
            surface: .timetableAcademics,
            key: "\(W4Routes.R.myTimetable)|\(nextKey)",
            uwcId: uwcId
        )
        XCTAssertNotNil(underCurrent, "stored under the week the header dates describe")
        XCTAssertNil(underNext, "never stored under the week we merely asked for")
    }

    // MARK: Round trip

    func testFetchedWeekIsServedFromTheCacheOnTheNextLoad() async throws {
        let cache = makeCache()
        let loader = StubTimetableLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsWeekHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsWeekHTML()))
        ])
        let repository = makeRepository(loader: loader, cache: cache)
        _ = try await repository.week(containing: now, policy: .alwaysRefresh)

        // A brand-new repository, a loader that answers nothing: only the cache can satisfy this.
        let offline = makeRepository(loader: StubTimetableLoader(), cache: cache)
        let loaded = try await offline.week(containing: now, policy: .refreshWhenStale)

        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(
            Set(loaded.value.allEvents.map(\.id)),
            ["ac-w4-42", "ea-w4-42"],
            "both cached pages must survive the round trip"
        )
    }

    // MARK: Grid guard

    func testGridGuardCountsTheHourGutterPlusSevenDays() {
        XCTAssertEqual(TimetableGridGuard.columnCount(in: academicsWeekHTML()), 8)
        XCTAssertTrue(TimetableGridGuard.hasFullGrid(html: academicsWeekHTML()))
        XCTAssertEqual(TimetableGridGuard.columnCount(in: academicsWeekHTML(dayColumns: 2)), 3)
        XCTAssertFalse(TimetableGridGuard.hasFullGrid(html: academicsWeekHTML(dayColumns: 2)))
        XCTAssertEqual(TimetableGridGuard.columnCount(in: "<html><body>nope</body></html>"), 0)
    }

    // MARK: Week identity

    func testWeekKeyIsTheISOWeekInOslo() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        XCTAssertEqual(ScheduleIdentity.weekKey(for: monday), "2026-W33")
        // Sunday of the same ISO week — a Sunday-first calendar would call this week 34.
        let sunday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 16))
        XCTAssertEqual(ScheduleIdentity.weekKey(for: sunday), "2026-W33")
    }

    func testWeekKeyRoundTrips() throws {
        let parsed = try XCTUnwrap(ScheduleIdentity.week(forKey: "2026-W33"))
        XCTAssertEqual(parsed.year, 2026)
        XCTAssertEqual(parsed.week, 33)
        XCTAssertEqual(
            ScheduleIdentity.startOfWeek(forKey: "2026-W33"),
            W4Dates.date(year: 2026, month: 8, day: 10)
        )
        XCTAssertNil(ScheduleIdentity.week(forKey: "garbage"))
        XCTAssertNil(ScheduleIdentity.week(forKey: "2026-W99"))
    }

    func testLessonKeyIsTheSourcePrefixedEventID() {
        let event = TimetableEvent(id: "ea-w4-42", title: "Kayaking", source: .extraAcademics, date: now)
        XCTAssertEqual(ScheduleIdentity.lessonKey(for: event), "ea-w4-42")
        XCTAssertEqual(
            ScheduleIdentity.uniqueKey(uwcId: uwcId, lessonKey: "ea-w4-42"),
            "nc26test|ea-w4-42"
        )
    }

    // MARK: - Fixtures and helpers

    private func makeCache() -> W4PageCache {
        W4PageCache(root: cacheRoot)
    }

    private func makeRepository(
        loader: StubTimetableLoader,
        cache: W4PageCache? = nil,
        store: TimetableStoreBridge = .disabled,
        isDemo: Bool = false
    ) -> TimetableRepository {
        let student = Student(
            studentId: isDemo ? Student.demoStudentId : uwcId,
            name: "Test Student",
            pictureId: nil,
            classLabel: nil
        )
        let context = W4RequestContext(
            student: student,
            credentials: isDemo ? .empty : W4Credentials(sessionId: "PHPSESSID-test")
        )
        let fixedNow = now!
        return TimetableRepository(
            loader: loader,
            cache: cache ?? makeCache(),
            store: store,
            context: { context },
            clock: { fixedNow }
        )
    }

    private func response(_ html: String) -> TimetablePageResponse {
        TimetablePageResponse(html: html, finalURL: W4Routes.url(W4Routes.R.myTimetable))
    }

    private func startOfCurrentWeek() -> Date {
        startOfWeek(offsetWeeks: 0)
    }

    private func startOfWeek(offsetWeeks: Int) -> Date {
        let iso = W4Dates.isoWeek(of: W4Dates.adding(days: offsetWeeks * 7, to: now))
        return W4Dates.startOfISOWeek(year: iso.year, week: iso.week) ?? W4Dates.startOfDay(now)
    }

    /// `W4Freshness` carries a `Date` that has round-tripped through the cache's JSON sidecar, so
    /// it is compared with a tolerance rather than for bit equality.
    private func assertCached(
        _ freshness: W4Freshness,
        at expected: Date,
        isStale expectedIsStale: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .cached(let fetchedAt, let isStale) = freshness else {
            return XCTFail("expected cached freshness, got \(freshness)", file: file, line: line)
        }
        XCTAssertEqual(
            fetchedAt.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 0.001,
            file: file,
            line: line
        )
        XCTAssertEqual(isStale, expectedIsStale, file: file, line: line)
    }

    /// Writes an Academics + Extra Academics pair into the page cache for the current week.
    private func seedTimetablePages(in cache: W4PageCache, fetchedAt: Date) async {
        let weekKey = ScheduleIdentity.weekKey(for: now)
        await cache.store(
            html: academicsWeekHTML(),
            surface: .timetableAcademics,
            key: "\(W4Routes.R.myTimetable)|\(weekKey)",
            uwcId: uwcId,
            fetchedAt: fetchedAt
        )
        await cache.store(
            html: extraAcademicsWeekHTML(),
            surface: .timetableExtraAcademics,
            key: "\(W4Routes.R.eaTimetable)|\(weekKey)",
            uwcId: uwcId,
            fetchedAt: fetchedAt
        )
    }

    private func academicsWeekHTML(monday: Date? = nil, dayColumns: Int = 7) -> String {
        Self.gridHTML(
            monday: monday ?? startOfCurrentWeek(),
            dayColumns: dayColumns,
            periodsByDay: [0: Self.lessonHTML(id: "42", title: "Biology HL", from: "8:00", to: "9:00", top: 60)]
        )
    }

    private func extraAcademicsWeekHTML(monday: Date? = nil) -> String {
        Self.gridHTML(
            monday: monday ?? startOfCurrentWeek(),
            dayColumns: 7,
            // The same numeric id as the Academics class on purpose: without the source prefix
            // (D-9 / bug B20) the merge would collapse the two into one lesson.
            periodsByDay: [0: Self.lessonHTML(id: "42", title: "Sea Kayaking", from: "17:00", to: "18:30", top: 600)]
        )
    }

    /// Mirrors the captured page: two nested `#timetable` elements (bug B1), a header whose first
    /// cell is the empty gutter, an hour-gutter column of `.cell` labels, then one column per day.
    private static func gridHTML(
        monday: Date,
        dayColumns: Int,
        periodsByDay: [Int: String]
    ) -> String {
        var header = #"<div class="header-cell first">&nbsp;</div>"#
        for offset in 0..<7 {
            let day = W4Dates.adding(days: offset, to: monday)
            let isWeekend = offset >= 5
            let rotationClass = isWeekend ? "rotation-day no-classes" : "rotation-day"
            let rotationLabel = isWeekend ? "Weekend" : "Day " + String(offset + 1)
            header += """
            <div class="header-cell">
              <div class="day-name">\(W4Dates.weekdayName(of: day))</div>
              <div>\(W4Dates.format(day))</div>
              <div class="\(rotationClass)">\(rotationLabel)</div>
              <div>No EA</div>
            </div>
            """
        }

        var columns = #"<div class="column" style="height: 900px"><div class="cell">7:00 &#8212; 8:00</div></div>"#
        for index in 0..<dayColumns {
            columns += #"<div class="column" style="height: 900px">"#
                + (periodsByDay[index] ?? "")
                + "</div>"
        }

        return """
        <html><body>
        <script>tt_start_hour = 7; tt_end_hour = 22;</script>
        <div id="timetable">
          <h3>Week grid</h3>
          <div id="timetable-header"><div class="header-row">\(header)</div></div>
          <div id="timetable">\(columns)</div>
        </div>
        </body></html>
        """
    }

    /// **[I]** Invented from the Android port's selectors — no real `.period` has been captured.
    private static func lessonHTML(id: String, title: String, from: String, to: String, top: Int) -> String {
        """
        <div class="period" style="top: \(top)px; height: 60px;" title="\(title)">
          <div class="inner"><a href="index.php?r=academics/classes/class&amp;id=\(id)">\(title)</a>
            <div class="datetime">\(from) &#8212; \(to)</div><div class="room">R1</div>
          </div>
        </div>
        """
    }
}
