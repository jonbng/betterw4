//
//  AssessmentRepositoryTests.swift
//  BetterW4Tests
//
//  Tests for `AssessmentRepository` and `AssessmentOverlayPolicy` (plan Wave 5 item 5.2).
//
//  ⚠️ WHAT THESE TESTS DO AND DO NOT PROVE ⚠️
//
//  They run entirely against a stubbed transport and a temporary page cache — no test here ever
//  touches the network. What they prove is that the repository's *own* rules hold: cache-first
//  reads, honest freshness, demo isolation, the optimistic overlay, and above all the write path.
//
//  What they cannot prove is that W4 accepts any of it. `index.php?r=academics/deadlines` has
//  never been captured (bug B12), so the fixtures are hand-written and every `data-assessment-*`
//  name in them is invented. The one part with independent corroboration is which id field goes
//  on the wire — `assessment_id` for a class item, `student_assessment_id` for a student-created
//  one (README section 5.2) — and that is what `testConfirmDoneOnAClassItemPostsAssessmentId` and
//  `testTogglingAStudentItemPostsStudentAssessmentId` guard. Getting that pair backwards makes
//  the button a silent no-op, which is the single worst outcome this surface has.
//

import XCTest
@testable import BetterW4

// MARK: - Doubles

private struct RecordedAssessmentAction: Sendable {
    let route: String
    let query: [String: String]
    let fields: [String: String]
}

/// A transport that answers from a script and records what it was asked for.
private actor StubAssessmentTransport: AssessmentPageTransport {

    private(set) var pageRequests: [AssessmentMonth] = []
    private(set) var actions: [RecordedAssessmentAction] = []

    private var pageResult: Result<AssessmentPageResponse, Error>
    private var actionResult: Result<AssessmentPageResponse, Error>

    init(
        pageResult: Result<AssessmentPageResponse, Error> = .failure(W4Error.noResponse),
        actionResult: Result<AssessmentPageResponse, Error> = .success(
            AssessmentPageResponse(
                html: "<html><body>ok</body></html>",
                finalURL: URL(string: "https://w4.uwcrcn.no/index.php")!
            )
        )
    ) {
        self.pageResult = pageResult
        self.actionResult = actionResult
    }

    func setPageResult(_ result: Result<AssessmentPageResponse, Error>) {
        pageResult = result
    }

    func setActionResult(_ result: Result<AssessmentPageResponse, Error>) {
        actionResult = result
    }

    func loadAssessmentsPage(
        month: AssessmentMonth,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AssessmentPageResponse {
        pageRequests.append(month)
        return try pageResult.get()
    }

    func submitAssessmentAction(
        route: String,
        query: [String: String],
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?
    ) async throws -> AssessmentPageResponse {
        actions.append(RecordedAssessmentAction(route: route, query: query, fields: fields))
        return try actionResult.get()
    }
}

/// The persistence seam without SwiftData. It deliberately reuses `AssessmentOverlayPolicy`, so
/// this double and `AssessmentStore` cannot drift apart on the rule that actually matters.
private actor InMemoryAssessmentOverlayStore: AssessmentOverlayStoring {

    private struct Stored {
        var item: Assessment
        var observedAt: Date?
    }

    private var server: [String: [String: Stored]] = [:]
    private var overlays: [String: [String: AssessmentLocalStatus]] = [:]

    func persist(
        _ items: [Assessment],
        uwcId: String,
        observedAt: Date?,
        pruning window: DateInterval?
    ) async -> [Assessment] {
        var stored = server[uwcId] ?? [:]
        var live = overlays[uwcId] ?? [:]
        var result: [Assessment] = []

        for item in items {
            stored[item.id] = Stored(item: item, observedAt: observedAt)
            let merged = AssessmentOverlayPolicy.merge(
                item,
                overlay: live[item.id],
                serverObservedAt: observedAt
            )
            if !merged.overlaySurvives { live[item.id] = nil }
            result.append(merged.item)
        }

        if let window {
            let keep = Set(items.map(\.id))
            for (id, entry) in stored where !keep.contains(id) {
                if let due = entry.item.dueDate, due >= window.start, due < window.end {
                    stored[id] = nil
                }
            }
        }

        server[uwcId] = stored
        overlays[uwcId] = live
        return result
    }

    func applyOverlays(to items: [Assessment], uwcId: String, observedAt: Date?) async -> [Assessment] {
        let live = overlays[uwcId] ?? [:]
        guard !live.isEmpty else { return items }
        return items.map {
            AssessmentOverlayPolicy.merge($0, overlay: live[$0.id], serverObservedAt: observedAt).item
        }
    }

    func setOverlay(
        _ status: AssessmentStatus,
        for item: Assessment,
        uwcId: String,
        at writtenAt: Date
    ) async {
        var stored = server[uwcId] ?? [:]
        if stored[item.id] == nil { stored[item.id] = Stored(item: item, observedAt: nil) }
        server[uwcId] = stored

        var live = overlays[uwcId] ?? [:]
        live[item.id] = AssessmentLocalStatus(
            assessmentId: item.id,
            status: status,
            writtenAt: writtenAt
        )
        overlays[uwcId] = live
    }

    func removeOverlay(for assessmentId: String, uwcId: String) async {
        var live = overlays[uwcId] ?? [:]
        live[assessmentId] = nil
        overlays[uwcId] = live
    }

    func cachedItems(uwcId: String, in window: DateInterval?) async -> [Assessment] {
        let live = overlays[uwcId] ?? [:]
        return (server[uwcId] ?? [:]).values.compactMap { entry -> Assessment? in
            if let window {
                guard let due = entry.item.dueDate, due >= window.start, due < window.end else {
                    return nil
                }
            }
            return AssessmentOverlayPolicy.merge(
                entry.item,
                overlay: live[entry.item.id],
                serverObservedAt: entry.observedAt
            ).item
        }
    }

    func clear(uwcId: String?) async {
        if let uwcId {
            server[uwcId] = nil
            overlays[uwcId] = nil
        } else {
            server.removeAll()
            overlays.removeAll()
        }
    }
}

// MARK: - Tests

final class AssessmentRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!
    /// The repository's injected clock. It has to track `TimeProvider` rather than be an
    /// arbitrary fixed date, because `W4PageCache` computes staleness against `TimeProvider.now`:
    /// a page stored "now" has to actually land inside its 15 minute TTL.
    private var referenceNow = TimeProvider.now

    private let uwcId = "nc26abcd"
    private let august = AssessmentMonth(year: 2026, month: 8)
    private let july = AssessmentMonth(year: 2026, month: 7)

    override func setUpWithError() throws {
        try super.setUpWithError()
        referenceNow = TimeProvider.now
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssessmentRepositoryTests-\(UUID().uuidString)", isDirectory: true)
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

    private func response(_ html: String) -> AssessmentPageResponse {
        AssessmentPageResponse(
            html: html,
            finalURL: URL(string: "https://w4.uwcrcn.no/index.php?r=academics/deadlines&month=08&year=2026")!
        )
    }

    private var signedIn: W4RequestContext {
        W4RequestContext(
            student: Student(studentId: uwcId, name: "Alex Andersen"),
            credentials: W4Credentials(sessionId: "PHPSESSID-TEST")
        )
    }

    private var demo: W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func makeRepository(
        transport: StubAssessmentTransport,
        store: InMemoryAssessmentOverlayStore,
        context: W4RequestContext,
        writesEnabled: Bool = true
    ) -> AssessmentRepository {
        let now = referenceNow
        return AssessmentRepository(
            transport: transport,
            cache: cache,
            store: store,
            resolveContext: { context },
            now: { now },
            writesEnabled: writesEnabled
        )
    }

    /// Puts a page in the cache without going near the transport.
    private func seedCache(_ html: String, month: AssessmentMonth, age: TimeInterval = 0) async {
        await cache.store(
            html: html,
            surface: .assessments,
            key: month.key,
            uwcId: uwcId,
            fetchedAt: referenceNow.addingTimeInterval(-age)
        )
    }

    // MARK: The month key

    func testMonthBuildsTheQueryW4Publishes() {
        XCTAssertEqual(august.key, "2026-08")
        XCTAssertEqual(august.query, ["month": "08", "year": "2026"])
        XCTAssertEqual(august.offset(byMonths: -8), AssessmentMonth(year: 2025, month: 12))
        XCTAssertEqual(august.offset(byMonths: 5), AssessmentMonth(year: 2027, month: 1))
        // A repository must never be able to build month=0 or month=13.
        XCTAssertEqual(AssessmentMonth(year: 2026, month: 0).month, 1)
        XCTAssertEqual(AssessmentMonth(year: 2026, month: 13).month, 12)
    }

    func testMonthIntervalIsAHalfOpenOsloMonth() throws {
        let interval = try XCTUnwrap(august.interval)
        XCTAssertEqual(interval.start, try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 1)))
        XCTAssertEqual(interval.end, try XCTUnwrap(W4Dates.date(year: 2026, month: 9, day: 1)))
    }

    // MARK: Reading

    func testFetchParsesTheMonthAndAsksForTheRightOne() async throws {
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.success(response(try fixture("assessments"))))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        let loaded = try await repository.assessments(for: august)

        XCTAssertEqual(loaded.freshness, .fresh)
        // Sorted soonest-first: 10 Aug before 11 Aug.
        XCTAssertEqual(loaded.value.map(\.id), ["class:42", "student:99"])
        XCTAssertEqual(loaded.value.first?.subject, "Biology")

        let requested = await transport.pageRequests
        XCTAssertEqual(requested, [august])
    }

    func testASecondReadIsServedFromTheCacheWithoutARequest() async throws {
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.success(response(try fixture("assessments"))))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        _ = try await repository.assessments(for: august)
        let second = try await repository.assessments(for: august)

        guard case .cached(let fetchedAt, let isStale) = second.freshness else {
            return XCTFail("expected the second read to come from the cache, got \(second.freshness)")
        }
        XCTAssertFalse(isStale)
        XCTAssertEqual(fetchedAt.timeIntervalSince1970, referenceNow.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(second.value.map(\.id), ["class:42", "student:99"])

        let requested = await transport.pageRequests
        XCTAssertEqual(requested.count, 1, "a page inside its TTL must not be refetched")
    }

    func testCachedAssessmentsRenderWithoutTouchingTheTransport() async throws {
        await seedCache(try fixture("assessments"), month: august)
        let transport = StubAssessmentTransport()
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        let loaded = await repository.cachedAssessments(for: august)

        XCTAssertEqual(loaded?.value.count, 2)
        let requested = await transport.pageRequests
        XCTAssertTrue(requested.isEmpty, "the instant-render path must never fetch")
    }

    func testEmptyMonthIsAnEmptyListNotAnError() async throws {
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.success(response(try fixture("assessments-empty"))))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        let loaded = try await repository.assessments(for: july)

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertTrue(loaded.value.isEmpty)
        // An empty month still publishes its write endpoints.
        let urls = await repository.actionURLs(for: july)
        XCTAssertNotNil(urls)
    }

    func testFetchFailureFallsBackToTheStaleCachedCopy() async throws {
        await seedCache(try fixture("assessments"), month: august, age: 3600)
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.failure(W4Error.httpError(status: 500, route: "academics/deadlines")))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        let loaded = try await repository.assessments(for: august)

        guard case .cached(_, let isStale) = loaded.freshness else {
            return XCTFail("expected a cached fallback, got \(loaded.freshness)")
        }
        XCTAssertTrue(isStale, "an hour-old page is past the 15 minute TTL")
        XCTAssertEqual(loaded.value.count, 2)
    }

    func testForbiddenIsNotADeadSessionAndStillFallsBackToTheCache() async throws {
        await seedCache(try fixture("assessments"), month: august, age: 3600)
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.failure(W4Error.forbidden))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        let loaded = try await repository.assessments(for: august)

        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(loaded.value.count, 2)
    }

    func testSessionExpiredPropagatesEvenWhenACachedCopyExists() async throws {
        await seedCache(try fixture("assessments"), month: august, age: 3600)
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.failure(W4Error.sessionExpired))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        do {
            _ = try await repository.assessments(for: august)
            XCTFail("a dead session must never be answered from the cache")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    func testFailureWithNoCacheRethrows() async throws {
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.failure(W4Error.forbidden))
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        do {
            _ = try await repository.assessments(for: august)
            XCTFail("with nothing cached there is nothing to degrade to")
        } catch let error as W4Error {
            guard case .forbidden = error else {
                return XCTFail("expected .forbidden to survive unchanged, got \(error)")
            }
        }
    }

    // MARK: Demo

    func testDemoNeverTouchesTheNetwork() async throws {
        let transport = StubAssessmentTransport()
        let repository = makeRepository(
            transport: transport,
            store: InMemoryAssessmentOverlayStore(),
            context: demo
        )

        let loaded = try await repository.assessments(for: august)

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(loaded.value.count, 6)
        XCTAssertEqual(loaded.value.filter(\.isDone).count, 2)
        XCTAssertEqual(loaded.value.filter(\.isOverdue).count, 1)
        XCTAssertEqual(loaded.value.filter { $0.kind == .studentCreated }.count, 1)

        let requested = await transport.pageRequests
        XCTAssertTrue(requested.isEmpty, "demo must never make a request")
    }

    func testDemoWriteFlipsLocallyAndStaysFlipped() async throws {
        let transport = StubAssessmentTransport()
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: demo)

        let first = try await repository.assessments(for: august)
        let pending = try XCTUnwrap(first.value.first { !$0.isDone })

        let updated = try await repository.apply(.confirmDone, to: pending, in: august)
        XCTAssertEqual(updated.status, .done)

        let second = try await repository.assessments(for: august)
        XCTAssertEqual(second.value.first { $0.id == pending.id }?.status, AssessmentStatus.done)

        let actions = await transport.actions
        XCTAssertTrue(actions.isEmpty, "a demo write must never reach the network")
    }

    // MARK: Writing

    func testConfirmDoneOnAClassItemPostsAssessmentId() async throws {
        await seedCache(try fixture("assessments"), month: august)
        let transport = StubAssessmentTransport()
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: signedIn)

        let loaded = try await repository.assessments(for: august)
        let item = try XCTUnwrap(loaded.value.first { $0.id == "class:42" })
        XCTAssertEqual(item.status, .pending)

        let updated = try await repository.apply(.confirmDone, to: item, in: august)
        XCTAssertEqual(updated.status, .done)

        let actions = await transport.actions
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.route, "academics/deadlines/confirm")
        // The whole point: a class-assigned item posts `assessment_id`, never `student_assessment_id`.
        XCTAssertEqual(action.fields, [AssessmentFieldNames.classAssessmentID: "42"])
        // The scraped endpoint's own query keys survive the round trip.
        XCTAssertEqual(action.query["month"], "08")
        XCTAssertEqual(action.query["year"], "2026")
        XCTAssertEqual(action.query["uwc_id"], "nc26abcd")

        // Optimistic overlay is in place…
        let stored = await store.cachedItems(uwcId: uwcId, in: nil)
        XCTAssertEqual(stored.first { $0.id == "class:42" }?.status, AssessmentStatus.done)

        // …and the pre-write page is gone, so the next read cannot render it.
        let page = await cache.page(surface: .assessments, key: august.key, uwcId: uwcId)
        XCTAssertNil(page, "a successful write must invalidate the cached page immediately")
    }

    func testTogglingAStudentItemPostsStudentAssessmentId() async throws {
        await seedCache(try fixture("assessments"), month: august)
        let transport = StubAssessmentTransport()
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: signedIn)

        let loaded = try await repository.assessments(for: august)
        let item = try XCTUnwrap(loaded.value.first { $0.id == "student:99" })
        XCTAssertEqual(item.status, .done, "the fixture's student item starts done")

        let updated = try await repository.toggle(item, in: august)
        XCTAssertEqual(updated.status, .pending)

        let recorded = await transport.actions
        let action = try XCTUnwrap(recorded.first)
        XCTAssertEqual(action.route, "academics/deadlines/revert")
        XCTAssertEqual(action.fields, [AssessmentFieldNames.studentAssessmentID: "99"])
    }

    func testFailedWriteRevertsTheOptimisticOverlayAndSurfacesTheError() async throws {
        await seedCache(try fixture("assessments"), month: august)
        let transport = StubAssessmentTransport()
        await transport.setActionResult(.failure(W4Error.serverConflict("nope")))
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: signedIn)

        let loaded = try await repository.assessments(for: august)
        let item = try XCTUnwrap(loaded.value.first { $0.id == "class:42" })

        do {
            _ = try await repository.apply(.confirmDone, to: item, in: august)
            XCTFail("a rejected write must not report success")
        } catch let error as W4Error {
            guard case .serverConflict = error else {
                return XCTFail("expected the transport's own error, got \(error)")
            }
        }

        let stored = await store.cachedItems(uwcId: uwcId, in: nil)
        XCTAssertEqual(
            stored.first { $0.id == "class:42" }?.status,
            AssessmentStatus.pending,
            "a failed write must roll the optimistic overlay back"
        )

        let page = await cache.page(surface: .assessments, key: august.key, uwcId: uwcId)
        XCTAssertNotNil(page, "nothing changed on the server, so the cached page is still valid")
    }

    func testDeadSessionDuringAWriteStillRevertsTheOverlay() async throws {
        await seedCache(try fixture("assessments"), month: august)
        let transport = StubAssessmentTransport()
        await transport.setActionResult(.failure(W4Error.sessionExpired))
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: signedIn)

        let loaded = try await repository.assessments(for: august)
        let item = try XCTUnwrap(loaded.value.first { $0.id == "class:42" })

        do {
            _ = try await repository.apply(.confirmDone, to: item, in: august)
            XCTFail("expected the dead session to propagate")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }

        let stored = await store.cachedItems(uwcId: uwcId, in: nil)
        XCTAssertEqual(stored.first { $0.id == "class:42" }?.status, AssessmentStatus.pending)
    }

    func testWriteWithoutAnEndpointIsRefusedRatherThanGuessed() async throws {
        // A page with no `ajax_urls` block at all.
        await seedCache("<html><body><h2>August 2026</h2></body></html>", month: august)
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.failure(W4Error.noResponse))
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: signedIn)

        let item = Assessment(
            id: "class:42",
            rawId: "42",
            kind: .classAssigned,
            rawKind: "class",
            title: "Lab report",
            status: .pending,
            rawStatus: "pending"
        )

        do {
            _ = try await repository.apply(.confirmDone, to: item, in: august)
            XCTFail("with no published endpoint there is nothing safe to POST to")
        } catch let error as W4Error {
            // Recovering the endpoints costs one fetch; the stub refuses it, and that error wins.
            guard case .noResponse = error else {
                return XCTFail("expected the fetch failure, got \(error)")
            }
        } catch let error as AssessmentWriteError {
            XCTAssertEqual(error, .endpointUnavailable(.confirmDone))
        }

        let actions = await transport.actions
        XCTAssertTrue(actions.isEmpty)
    }

    func testWritesTakeTheSharedFeatureGateByDefault() async throws {
        try XCTSkipIf(
            AssessmentFeatureFlags.writesEnabled,
            "OQ-3 has been opened; this test only describes the gate in its closed state."
        )

        await seedCache(try fixture("assessments"), month: august)
        let transport = StubAssessmentTransport()
        let store = InMemoryAssessmentOverlayStore()
        let context = signedIn
        let now = referenceNow
        // No `writesEnabled:` argument — this is exactly how the app builds it.
        let repository = AssessmentRepository(
            transport: transport,
            cache: cache,
            store: store,
            resolveContext: { context },
            now: { now }
        )

        let loaded = try await repository.assessments(for: august)
        let item = try XCTUnwrap(loaded.value.first { $0.id == "class:42" })

        do {
            _ = try await repository.apply(.confirmDone, to: item, in: august)
            XCTFail("writes are gated off until capture C-3 lands")
        } catch let error as AssessmentWriteError {
            XCTAssertEqual(error, .writesDisabled)
        }

        let actions = await transport.actions
        XCTAssertTrue(actions.isEmpty, "a gated-off write must not reach the network")

        let canWrite = await repository.canWrite(in: august)
        XCTAssertFalse(canWrite)
    }

    func testCanWriteIsTrueOnceTheEndpointsAreKnown() async throws {
        await seedCache(try fixture("assessments"), month: august)
        let repository = makeRepository(
            transport: StubAssessmentTransport(),
            store: InMemoryAssessmentOverlayStore(),
            context: signedIn
        )

        let canWrite = await repository.canWrite(in: august)
        XCTAssertTrue(canWrite)
    }

    // MARK: The overlay rule

    func testOverlaySurvivesAPageOlderThanTheTap() {
        let tap = AssessmentLocalStatus(assessmentId: "class:42", status: .done, writtenAt: referenceNow)
        XCTAssertTrue(
            AssessmentOverlayPolicy.survives(
                tap,
                serverStatus: .pending,
                serverObservedAt: referenceNow.addingTimeInterval(-60)
            )
        )
    }

    func testOverlayIsDroppedAsSoonAsANewerServerStatusArrives() {
        let tap = AssessmentLocalStatus(assessmentId: "class:42", status: .done, writtenAt: referenceNow)
        XCTAssertFalse(
            AssessmentOverlayPolicy.survives(
                tap,
                serverStatus: .pending,
                serverObservedAt: referenceNow.addingTimeInterval(60)
            ),
            "a page W4 produced after the tap is the truth, even when it disagrees"
        )
    }

    func testOverlayIsDroppedOnceTheServerAgrees() {
        let tap = AssessmentLocalStatus(assessmentId: "class:42", status: .done, writtenAt: referenceNow)
        XCTAssertFalse(
            AssessmentOverlayPolicy.survives(
                tap,
                serverStatus: .done,
                serverObservedAt: referenceNow.addingTimeInterval(-60)
            )
        )
    }

    func testOverlayWinsWhenThereIsNoServerObservationAtAll() {
        let tap = AssessmentLocalStatus(assessmentId: "class:42", status: .done, writtenAt: referenceNow)
        XCTAssertTrue(
            AssessmentOverlayPolicy.survives(tap, serverStatus: .pending, serverObservedAt: nil)
        )
    }

    func testARefetchAfterAWriteDropsTheOverlayAndShowsServerTruth() async throws {
        let transport = StubAssessmentTransport()
        await transport.setPageResult(.success(response(try fixture("assessments"))))
        let store = InMemoryAssessmentOverlayStore()
        let repository = makeRepository(transport: transport, store: store, context: signedIn)

        let loaded = try await repository.assessments(for: august)
        let item = try XCTUnwrap(loaded.value.first { $0.id == "class:42" })
        _ = try await repository.apply(.confirmDone, to: item, in: august)

        // The write invalidated the page, so this refetch is a real one. Its `observedAt` is
        // `referenceNow`, the same instant as the tap, so the tie-break keeps the overlay…
        let sameInstant = try await repository.assessments(for: august)
        XCTAssertEqual(sameInstant.value.first { $0.id == "class:42" }?.status, AssessmentStatus.done)

        // …but a page W4 produced later wins, and W4 still says pending.
        let merged = await store.persist(
            loaded.value,
            uwcId: uwcId,
            observedAt: referenceNow.addingTimeInterval(300),
            pruning: august.interval
        )
        XCTAssertEqual(
            merged.first { $0.id == "class:42" }?.status,
            AssessmentStatus.pending,
            "a silently ignored write must become visible on the next refresh"
        )
    }
}
