//
//  AttendanceRepositoryTests.swift
//  BetterW4Tests
//
//  Tests for `AttendanceRepository` (plan Wave 5 item 5.4).
//
//  Nothing here touches the network. The repository takes its transport as
//  `any AttendancePageFetching`, so every test drives a `StubFetcher` that records the routes and
//  priorities it was asked for and answers with fixture bytes — which is also how "the meters cost
//  zero requests" is *proved* rather than asserted by inspection: the stub simply is not called.
//
//  The page cache is a real `W4PageCache` rooted in a per-test temporary directory, so cache
//  scoping, TTL and eviction are exercised for real. The clock is injected, so "stale" is a
//  deterministic fact rather than a race with the wall clock.
//
//  FIXTURE PROVENANCE (unchanged from `W4AbsenceParserTests`):
//    [V] `Fixtures/W4/home.html` is a real, sanitized capture; both meters read
//        "You have 0 absences and 0 latenesses so far".
//    [I] `Fixtures/W4/absences.html` is hand-written — the absence list page has never been
//        captured. Assertions about its *rows* prove the repository plumbs the parser correctly;
//        they prove nothing about W4's markup.
//

import XCTest
@testable import BetterW4

final class AttendanceRepositoryTests: XCTestCase {

    // MARK: - Test rig

    /// Records every request and answers from a route → result table.
    private actor StubFetcher: AttendancePageFetching {

        struct Request {
            let route: String
            let priority: FetchPriority
            let studentId: String?
            let sessionId: String
        }

        private var responses: [String: Result<String, Error>] = [:]
        private(set) var requests: [Request] = []

        func stub(_ route: String, html: String) {
            responses[route] = .success(html)
        }

        func stub(_ route: String, error: Error) {
            responses[route] = .failure(error)
        }

        var routes: [String] { requests.map(\.route) }
        var callCount: Int { requests.count }

        func fetchPage(
            route: String,
            query: [String: String],
            credentials: W4Credentials,
            studentId: String?,
            priority: FetchPriority
        ) async throws -> AttendancePageResponse {
            requests.append(
                Request(
                    route: route,
                    priority: priority,
                    studentId: studentId,
                    sessionId: credentials.sessionId
                )
            )
            // An unstubbed route is a test bug, not a scenario: fail loudly.
            guard let response = responses[route] else {
                throw W4Error.httpError(status: 599, route: route)
            }
            switch response {
            case .success(let html):
                return AttendancePageResponse(html: html, finalURL: W4Routes.url(route))
            case .failure(let error):
                throw error
            }
        }
    }

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    /// A fixed "now". Every cached page below is seeded relative to it, so freshness is decided by
    /// arithmetic instead of by how long the test took to run.
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private let uwcId = "nc26abcd"

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttendanceRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        cache = W4PageCache(root: cacheRoot)
    }

    override func tearDownWithError() throws {
        if let cacheRoot { try? FileManager.default.removeItem(at: cacheRoot) }
        cache = nil
        cacheRoot = nil
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func signedInContext() -> W4RequestContext {
        W4RequestContext(
            student: Student(
                studentId: uwcId,
                name: "Alex Andersen",
                pictureId: nil,
                classLabel: nil
            ),
            credentials: W4Credentials(sessionId: "phpsessid-test")
        )
    }

    private func demoContext() -> W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func makeRepository(
        fetcher: any AttendancePageFetching,
        context: W4RequestContext?
    ) -> AttendanceRepository {
        let clock = self.clock
        return AttendanceRepository(
            fetcher: fetcher,
            cache: cache,
            resolveContext: {
                guard let context else { throw W4Error.missingCookies }
                return context
            },
            now: { clock }
        )
    }

    /// Writes a page into the real cache `secondsOld` seconds before the injected `now`.
    private func seed(
        _ html: String,
        surface: W4Surface,
        key: String,
        secondsOld: TimeInterval,
        uwcId: String? = nil
    ) async {
        await cache.store(
            html: html,
            surface: surface,
            key: key,
            uwcId: uwcId ?? self.uwcId,
            finalURL: nil,
            contentType: nil,
            fetchedAt: clock.addingTimeInterval(-secondsOld)
        )
    }

    private func cachedPage(surface: W4Surface, key: String) async -> CachedPage? {
        await cache.page(surface: surface, key: key, uwcId: uwcId)
    }

    /// A minimal Yii empty-state list page.
    private func emptyListPage(_ message: String) -> String {
        """
        <html><body><div id="content_inner">
          <h2>My Absences</h2>
          <div class="grid-view" id="yw0"><table class="items">
            <thead><tr><th>Date</th><th>Period</th><th>Class</th><th>Type</th><th>Status</th></tr></thead>
            <tbody><tr><td colspan="5" class="empty">\(message)</td></tr></tbody>
          </table></div>
        </div></body></html>
        """
    }

    /// A hand-written register-absence form. **[I]** — the real page has never been captured
    /// (OQ-10); this exercises the scraper, not W4.
    private func registerFormPage() -> String {
        """
        <html><body><div id="content_inner">
          <h2>Register an absence</h2>
          <form id="student-absence-form" action="index.php?r=people/students/absences/register" method="post">
            <input type="hidden" name="StudentAbsenceForm[student_id]" value="nc26abcd" />
            <input type="text" name="StudentAbsenceForm[absence_date]" value="14-Aug-2026" />
            <textarea name="StudentAbsenceForm[comment]"></textarea>
            <input type="submit" name="yt0" value="Register" />
          </form>
        </div></body></html>
        """
    }

    // MARK: - Demo mode: zero network, zero persistence

    /// Demo must branch *before* any fetch (plan rule 3a) and before any cache write
    /// (features.md §4: zero persistence).
    func testDemoMetersTouchNeitherTheNetworkNorTheCache() async throws {
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: demoContext())

        let loaded = try await repository.loadMeters()

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(loaded.value.academic, AttendanceMeter(absences: 2, latenesses: 1))
        XCTAssertEqual(loaded.value.extraAcademic, .zero)
        XCTAssertNil(loaded.value.failure)
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0, "demo must never reach the network")
        let stored = await cache.page(
            surface: .attendanceMeters,
            key: AttendanceRepository.CacheKey.meters,
            uwcId: Student.demoStudentId
        )
        XCTAssertNil(stored, "demo must never write to the page cache")
    }

    /// The reviewer script (features.md §4): AC shows 3 rows — 2 absences and 1 lateness — and EA
    /// is an empty state.
    func testDemoListsMatchTheReviewerScript() async throws {
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: demoContext())

        let academic = try await repository.loadList(for: .academics)
        let extra = try await repository.loadList(for: .extraAcademics)

        XCTAssertEqual(academic.freshness, .demo)
        XCTAssertEqual(academic.value.records.count, 3)
        XCTAssertEqual(academic.value.records.filter { $0.kind == .absence }.count, 2)
        XCTAssertEqual(academic.value.records.filter { $0.kind == .lateness }.count, 1)
        XCTAssertTrue(academic.value.records.allSatisfy { $0.source == .academics })
        XCTAssertTrue(academic.value.records.allSatisfy { $0.subject?.isEmpty == false })
        XCTAssertTrue(academic.value.records.allSatisfy { $0.period?.isEmpty == false })
        XCTAssertEqual(Set(academic.value.records.map(\.id)).count, 3, "demo ids must be unique")

        XCTAssertTrue(extra.value.records.isEmpty)
        XCTAssertEqual(extra.value.list.emptyMessage, "No results found.")
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)
    }

    /// D-13 in demo too: the meter numbers are the meter's, and they happen to agree with the rows
    /// only because the demo data was written that way — nothing counts rows.
    func testDemoSnapshotIsSelfConsistentAndOffline() async throws {
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: demoContext())

        let loaded = try await repository.loadSnapshot()
        let overview = loaded.value.overview(fetchedAt: clock)

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertTrue(loaded.value.failures.isEmpty)
        XCTAssertEqual(overview.academic, AttendanceMeter(absences: 2, latenesses: 1))
        XCTAssertEqual(overview.extraAcademic, .zero)
        XCTAssertEqual(overview.records.count, 3)
        XCTAssertEqual(overview.records(for: .extraAcademics).count, 0)
        XCTAssertEqual(loaded.value.subjectBreakdown.count, 3)
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)
    }

    /// The register form opens read-only in demo, with copy that says so.
    func testDemoRegistrationFormIsReadOnlyAndExplainsItself() async throws {
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: demoContext())

        let loaded = try await repository.loadRegistrationForm()

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertFalse(loaded.value.canSubmit)
        XCTAssertEqual(loaded.value.route, "people/students/absences/register")
        XCTAssertEqual(loaded.value.dateField?.name, "StudentAbsenceForm[absence_date]")
        XCTAssertNotNil(loaded.value.note)
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)
    }

    // MARK: - Meters from a cached Home page (the point of item 5.4)

    /// **The done criterion.** A Home page already in the cache and inside its TTL yields both
    /// meters with ZERO additional network traffic.
    func testFreshHomeSnapshotProducesMetersWithoutASingleRequest() async throws {
        let homeHTML = try fixture("home")
        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 60)
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadMeters()

        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0, "the Home snapshot must not be refetched")
        XCTAssertEqual(loaded.value.academic, AttendanceMeter.zero)
        XCTAssertEqual(loaded.value.extraAcademic, AttendanceMeter.zero)
        XCTAssertNil(loaded.value.failure)
        XCTAssertEqual(
            loaded.freshness,
            .cached(fetchedAt: clock.addingTimeInterval(-60), isStale: false)
        )
    }

    /// The Home page belongs to another repository, so its cache key is not ours to dictate. The
    /// zero-request path probes the plausible key shapes rather than assuming one.
    func testHomeSnapshotStoredUnderAnAlternativeKeyIsStillUsed() async throws {
        let homeHTML = try fixture("home")
        await seed(homeHTML, surface: .home, key: "", secondsOld: 120)
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadMeters()

        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)
        XCTAssertEqual(loaded.value.academic, AttendanceMeter.zero)
    }

    /// A Home snapshot past its TTL is not good enough for a plain load: fetch `site/index`, store
    /// our own copy, and leave the borrowed Home page exactly as it was.
    func testStaleHomeSnapshotIsRefetchedIntoOurOwnCacheSlot() async throws {
        let homeHTML = try fixture("home")
        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 3_600)
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.home, html: homeHTML)
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadMeters()

        let observedRoutes = await fetcher.routes
        XCTAssertEqual(observedRoutes, [W4Routes.R.home])
        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.academic, AttendanceMeter.zero)

        let ourPage = await cachedPage(
            surface: .attendanceMeters,
            key: AttendanceRepository.CacheKey.meters
        )
        let ours = try XCTUnwrap(ourPage, "the fetched Home page is stored under our own surface")
        XCTAssertEqual(ours.fetchedAt, clock)

        let borrowedPage = await cachedPage(surface: .home, key: W4Routes.R.home)
        let borrowed = try XCTUnwrap(borrowedPage)
        XCTAssertEqual(
            borrowed.fetchedAt,
            clock.addingTimeInterval(-3_600),
            "the Home repository's page must not be rewritten by this repository"
        )
    }

    /// And once we have our own copy, the next load inside the TTL is free again.
    func testASecondMeterLoadInsideTheTTLIssuesNoRequest() async throws {
        let homeHTML = try fixture("home")
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.home, html: homeHTML)
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        _ = try await repository.loadMeters()
        let second = try await repository.loadMeters()

        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 1)
        XCTAssertEqual(second.freshness, .cached(fetchedAt: clock, isStale: false))
        XCTAssertEqual(second.value.academic, AttendanceMeter.zero)
    }

    /// `cachedMeters()` is the "render instantly" half of cache-first: never a request, `nil` when
    /// there is nothing on disk.
    func testCachedMetersNeverFetchAndReportStaleness() async throws {
        let homeHTML = try fixture("home")
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let cold = await repository.cachedMeters()
        XCTAssertNil(cold)

        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 3_600)
        let warm = await repository.cachedMeters()

        XCTAssertEqual(warm?.value.academic, AttendanceMeter.zero)
        XCTAssertEqual(
            warm?.freshness,
            .cached(fetchedAt: clock.addingTimeInterval(-3_600), isStale: true)
        )
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)
    }

    // MARK: - Lists

    /// AC: fetch the right route, parse every row, take the meter from the prose (D-13), and cache
    /// the page so the next load is free.
    func testAcademicListFetchesParsesAndCaches() async throws {
        let absencesHTML = try fixture("absences")
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, html: absencesHTML)
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadList(for: .academics)

        let observedRoutes = await fetcher.routes
        XCTAssertEqual(observedRoutes, ["people/students/absences"])
        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.records.count, 4)
        XCTAssertEqual(loaded.value.list.meter, AttendanceMeter(absences: 3, latenesses: 1),
                       "the meter is the page's sentence, not the row count")
        XCTAssertNil(loaded.value.failure)
        let storedACPage = await cachedPage(surface: .attendanceAcademics, key: W4Routes.R.absences)
        XCTAssertNotNil(storedACPage)

        let second = try await repository.loadList(for: .academics)
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 1, "a fresh cached page is not refetched")
        XCTAssertEqual(second.freshness, .cached(fetchedAt: clock, isStale: false))
        XCTAssertEqual(second.value.records.count, 4)
    }

    /// EA is a separate ledger with a separate route and a separate cache slot; loading it must not
    /// populate — or read — the AC slot.
    func testExtraAcademicListIsAnIndependentSurface() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.eaAbsences, html: emptyListPage("No results found."))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadList(for: .extraAcademics)

        let observedRoutes = await fetcher.routes
        XCTAssertEqual(observedRoutes, ["people/students/eaabsences"])
        XCTAssertEqual(loaded.value.source, .extraAcademics)
        XCTAssertTrue(loaded.value.records.isEmpty)
        XCTAssertEqual(loaded.value.list.emptyMessage, "No results found.")
        let storedEAPage = await cachedPage(
            surface: .attendanceExtraAcademics,
            key: W4Routes.R.eaAbsences
        )
        let untouchedACPage = await cachedPage(
            surface: .attendanceAcademics,
            key: W4Routes.R.absences
        )
        XCTAssertNotNil(storedEAPage)
        XCTAssertNil(untouchedACPage, "EA must not write into the AC slot")
    }

    /// Pull-to-refresh: `forceRefresh` ignores a page that is still inside its TTL.
    func testForceRefreshBypassesAFreshCachedPage() async throws {
        let absencesHTML = try fixture("absences")
        await seed(absencesHTML, surface: .attendanceAcademics,
                   key: W4Routes.R.absences, secondsOld: 60)
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, html: absencesHTML)
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let cached = try await repository.loadList(for: .academics)
        XCTAssertEqual(cached.freshness, .cached(fetchedAt: clock.addingTimeInterval(-60), isStale: false))
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)

        let refreshed = try await repository.loadList(for: .academics, forceRefresh: true)
        XCTAssertEqual(refreshed.freshness, .fresh)
        let observedCalls2 = await fetcher.callCount
        XCTAssertEqual(observedCalls2, 1)
    }

    // MARK: - Degradation (plan rule 3d)

    /// Offline with a warm cache is a working app: the stale copy is served, and the failure rides
    /// along so the UI can say why the timestamp is old.
    func testListFailureFallsBackToTheStaleCachedCopy() async throws {
        let absencesHTML = try fixture("absences")
        await seed(absencesHTML, surface: .attendanceAcademics,
                   key: W4Routes.R.absences, secondsOld: 7_200)
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, error: URLError(.notConnectedToInternet))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadList(for: .academics)

        XCTAssertEqual(loaded.value.records.count, 4, "the cached rows still render")
        XCTAssertEqual(
            loaded.freshness,
            .cached(fetchedAt: clock.addingTimeInterval(-7_200), isStale: true)
        )
        XCTAssertEqual(loaded.value.failure?.kind, .offline)
        XCTAssertEqual(loaded.value.failure?.target, .list(.academics))
        XCTAssertTrue(loaded.value.failure?.isOffline ?? false)
    }

    /// **The done criterion for the lists.** With nothing cached, a failed fetch degrades to an
    /// empty list plus an error — it does not throw.
    func testListFailureWithNoCacheDegradesToAnEmptyListPlusAnError() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, error: URLError(.timedOut))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadList(for: .academics)

        XCTAssertTrue(loaded.value.records.isEmpty)
        XCTAssertEqual(loaded.value.list.source, .academics)
        XCTAssertFalse(loaded.value.list.hasMorePages)
        XCTAssertNotNil(loaded.value.failure)
        XCTAssertFalse(loaded.value.failure?.message.isEmpty ?? true)
        XCTAssertEqual(loaded.freshness, .cached(fetchedAt: .distantPast, isStale: true))
    }

    /// The same contract for the meters: empty meters plus a failure, never a thrown error.
    func testMeterFailureWithNoCacheDegradesToEmptyMetersPlusAnError() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.home, error: URLError(.networkConnectionLost))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadMeters()

        XCTAssertTrue(loaded.value.meters.isEmpty)
        XCTAssertNil(loaded.value.academic, "an absent meter is nil, never a fabricated zero")
        XCTAssertEqual(loaded.value.failure?.kind, .offline)
        XCTAssertEqual(loaded.value.failure?.target, .meters)
    }

    /// 403 without "Login Required" means *wrong role*, not dead session (reviewer-notes §3). It
    /// must degrade like any other failure and must never surface as `sessionExpired`.
    func testForbiddenIsNeverTreatedAsASessionDeath() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, error: W4Error.forbidden)
        await fetcher.stub(W4Routes.R.home, error: W4Error.forbidden)
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let list = try await repository.loadList(for: .academics)
        let meters = try await repository.loadMeters()

        XCTAssertEqual(list.value.failure?.kind, .forbidden)
        XCTAssertTrue(list.value.failure?.isForbidden ?? false)
        XCTAssertTrue(list.value.records.isEmpty)
        XCTAssertEqual(meters.value.failure?.kind, .forbidden)
    }

    /// `sessionExpired` is the one failure that must never be swallowed — not even when a perfectly
    /// good cached copy is sitting right there.
    func testSessionExpiredPropagatesEvenWithAUsableCachedCopy() async throws {
        let homeHTML = try fixture("home")
        let absencesHTML = try fixture("absences")
        await seed(absencesHTML, surface: .attendanceAcademics,
                   key: W4Routes.R.absences, secondsOld: 7_200)
        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 7_200)
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, error: W4Error.sessionExpired)
        await fetcher.stub(W4Routes.R.home, error: W4Error.sessionExpired)
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        do {
            let loaded = try await repository.loadList(for: .academics)
            XCTFail("a dead session must propagate, got \(loaded.value.records.count) cached rows")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }

        do {
            _ = try await repository.loadMeters()
            XCTFail("a dead session must propagate from the meters too")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// Cancellation is not a failure to report: it propagates rather than overwriting a screen with
    /// an empty list and an error banner.
    func testCancellationPropagatesInsteadOfDegrading() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, error: CancellationError())
        await fetcher.stub(W4Routes.R.eaAbsences, error: URLError(.cancelled))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        do {
            _ = try await repository.loadList(for: .academics)
            XCTFail("CancellationError must propagate")
        } catch is CancellationError {
            // expected
        }

        do {
            _ = try await repository.loadList(for: .extraAcademics)
            XCTFail("URLError.cancelled must propagate")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
    }

    // MARK: - The aggregate

    /// The screen model: meters off the cached Home page (no request) plus exactly two list
    /// requests, with EA queued opportunistically behind the list the student is looking at.
    func testSnapshotBorrowsTheHomeMetersAndFetchesOnlyTheTwoLists() async throws {
        let homeHTML = try fixture("home")
        let absencesHTML = try fixture("absences")
        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 60)
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, html: absencesHTML)
        await fetcher.stub(W4Routes.R.eaAbsences, html: emptyListPage("No results found."))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadSnapshot()
        let requests = await fetcher.requests

        XCTAssertEqual(requests.map(\.route), ["people/students/absences", "people/students/eaabsences"])
        XCTAssertEqual(requests.first?.priority, .important)
        XCTAssertEqual(requests.last?.priority, .opportunistic,
                       "EA must not starve the list on screen")
        XCTAssertEqual(requests.first?.studentId, uwcId)
        XCTAssertEqual(requests.first?.sessionId, "phpsessid-test")

        let overview = loaded.value.overview(fetchedAt: clock)
        XCTAssertEqual(overview.academic, AttendanceMeter.zero, "meters come from the Home prose")
        XCTAssertEqual(overview.records.count, 4)
        XCTAssertEqual(overview.records(for: .academics).count, 4)
        XCTAssertTrue(loaded.value.failures.isEmpty)
        XCTAssertEqual(
            loaded.freshness,
            .cached(fetchedAt: clock.addingTimeInterval(-60), isStale: false),
            "one part came off disk, so the whole is honestly 'cached'"
        )
    }

    /// One ledger failing does not take the screen down with it.
    func testSnapshotSurvivesOneLedgerFailing() async throws {
        let homeHTML = try fixture("home")
        let absencesHTML = try fixture("absences")
        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 60)
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, html: absencesHTML)
        await fetcher.stub(W4Routes.R.eaAbsences, error: W4Error.httpError(status: 500, route: W4Routes.R.eaAbsences))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadSnapshot()

        XCTAssertEqual(loaded.value.academic.records.count, 4)
        XCTAssertTrue(loaded.value.extraAcademic.records.isEmpty)
        XCTAssertEqual(loaded.value.failures.count, 1)
        XCTAssertEqual(loaded.value.failures.first?.target, .list(.extraAcademics))
        XCTAssertEqual(loaded.value.failures.first?.kind, .server)
    }

    // MARK: - Register absence (read-only, OQ-10)

    /// The form is scraped into a model and marked unsubmittable. It also lives in its own cache
    /// slot — the AC list slot must stay untouched.
    func testRegistrationFormIsScrapedButNeverSubmittable() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absencesRegister, html: registerFormPage())
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadRegistrationForm()
        let form = loaded.value

        let observedRoutes = await fetcher.routes
        XCTAssertEqual(observedRoutes, ["people/students/absences/register"])
        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertFalse(form.canSubmit, "OQ-10: the payload is unverified, so we never POST it")
        XCTAssertEqual(form.dateField?.name, "StudentAbsenceForm[absence_date]")
        XCTAssertEqual(form.dateField?.value, "14-Aug-2026")
        XCTAssertTrue(form.fields.contains { $0.name == "StudentAbsenceForm[student_id]" })
        XCTAssertEqual(form.submitButtons.map(\.name), ["yt0"])
        XCTAssertEqual(form.action, "index.php?r=people/students/absences/register")

        let storedFormPage = await cachedPage(
            surface: .attendanceAcademics,
            key: AttendanceRepository.CacheKey.registrationForm
        )
        let untouchedListPage = await cachedPage(
            surface: .attendanceAcademics,
            key: W4Routes.R.absences
        )
        XCTAssertNotNil(storedFormPage)
        XCTAssertNil(untouchedListPage, "the form must not occupy the AC list slot")
    }

    /// A form has no degraded shape — an empty form is a broken screen, not a working one — so this
    /// surface throws when there is nothing cached.
    func testRegistrationFormThrowsWhenThereIsNothingToShow() async throws {
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absencesRegister, error: URLError(.timedOut))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        do {
            _ = try await repository.loadRegistrationForm()
            XCTFail("with no cached copy the form surface must surface the error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
    }

    // MARK: - Signed out

    /// No context, no uwc id, no cache scope: the loads throw and the cache-only accessors answer
    /// `nil` rather than inventing a scope.
    func testSignedOutLoadsThrowAndCachedAccessorsReturnNil() async throws {
        let fetcher = StubFetcher()
        let repository = makeRepository(fetcher: fetcher, context: nil)

        do {
            _ = try await repository.loadMeters()
            XCTFail("a signed-out meter load must throw")
        } catch let error as W4Error {
            guard case .missingCookies = error else {
                return XCTFail("expected .missingCookies, got \(error)")
            }
        }

        do {
            _ = try await repository.loadList(for: .academics)
            XCTFail("a signed-out list load must throw")
        } catch is W4Error {
            // expected
        }

        let cachedMeters = await repository.cachedMeters()
        let cachedList = await repository.cachedList(for: .academics)
        let cachedSnapshot = await repository.cachedSnapshot()
        XCTAssertNil(cachedMeters)
        XCTAssertNil(cachedList)
        XCTAssertNil(cachedSnapshot)
        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 0)
    }

    // MARK: - Cache maintenance

    /// "Clear cache" drops what this repository owns and leaves the Home page — which it borrows
    /// but does not own — to its owner.
    func testInvalidateDropsOurPagesAndLeavesTheBorrowedHomePage() async throws {
        let homeHTML = try fixture("home")
        let absencesHTML = try fixture("absences")
        await seed(homeHTML, surface: .home, key: W4Routes.R.home, secondsOld: 60)
        await seed(homeHTML, surface: .attendanceMeters,
                   key: AttendanceRepository.CacheKey.meters, secondsOld: 60)
        await seed(absencesHTML, surface: .attendanceAcademics,
                   key: W4Routes.R.absences, secondsOld: 60)
        await seed(emptyListPage("No results found."), surface: .attendanceExtraAcademics,
                   key: W4Routes.R.eaAbsences, secondsOld: 60)
        await seed(registerFormPage(), surface: .attendanceAcademics,
                   key: AttendanceRepository.CacheKey.registrationForm, secondsOld: 60)

        let repository = makeRepository(fetcher: StubFetcher(), context: signedInContext())
        await repository.invalidateCaches()

        let metersPage = await cachedPage(
            surface: .attendanceMeters,
            key: AttendanceRepository.CacheKey.meters
        )
        let academicPage = await cachedPage(surface: .attendanceAcademics, key: W4Routes.R.absences)
        let extraPage = await cachedPage(
            surface: .attendanceExtraAcademics,
            key: W4Routes.R.eaAbsences
        )
        let formPage = await cachedPage(
            surface: .attendanceAcademics,
            key: AttendanceRepository.CacheKey.registrationForm
        )
        let homePage = await cachedPage(surface: .home, key: W4Routes.R.home)

        XCTAssertNil(metersPage)
        XCTAssertNil(academicPage)
        XCTAssertNil(extraPage)
        XCTAssertNil(formPage)
        XCTAssertNotNil(homePage, "the Home page belongs to HomeRepository")
    }

    // MARK: - Cache scoping

    /// Pages are scoped per uwc id by `W4PageCache`; a different student must never see them.
    func testAnotherStudentsCachedPagesAreInvisible() async throws {
        let absencesHTML = try fixture("absences")
        await seed(absencesHTML, surface: .attendanceAcademics,
                   key: W4Routes.R.absences, secondsOld: 60, uwcId: "nc26zzzz")
        let fetcher = StubFetcher()
        await fetcher.stub(W4Routes.R.absences, html: emptyListPage("No results found."))
        let repository = makeRepository(fetcher: fetcher, context: signedInContext())

        let loaded = try await repository.loadList(for: .academics)

        let observedCalls = await fetcher.callCount
        XCTAssertEqual(observedCalls, 1, "the other student's page is not ours")
        XCTAssertTrue(loaded.value.records.isEmpty)
    }

    // MARK: - Freshness arithmetic

    /// The aggregate's freshness is the coarsest honest answer, not the nicest one.
    func testCombinedFreshnessIsTheCoarsestHonestAnswer() {
        let older = clock.addingTimeInterval(-600)
        let newer = clock.addingTimeInterval(-60)

        XCTAssertEqual(AttendanceRepository.combine([.demo, .demo], now: clock), .demo)
        XCTAssertEqual(AttendanceRepository.combine([.fresh, .fresh], now: clock), .fresh)
        XCTAssertEqual(
            AttendanceRepository.combine(
                [.fresh, .cached(fetchedAt: newer, isStale: false)],
                now: clock
            ),
            .cached(fetchedAt: newer, isStale: false)
        )
        XCTAssertEqual(
            AttendanceRepository.combine(
                [.cached(fetchedAt: newer, isStale: false), .cached(fetchedAt: older, isStale: true)],
                now: clock
            ),
            .cached(fetchedAt: older, isStale: true),
            "one stale part makes the whole stale, and the oldest timestamp wins"
        )
    }
}

