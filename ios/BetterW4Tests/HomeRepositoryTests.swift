//
//  HomeRepositoryTests.swift
//  BetterW4Tests
//
//  Tests for the four repositories of plan Wave 5 item 5.8 part B — `HomeRepository`,
//  `FeedsRepository`, `ExtraAcademicsRepository`, `ResourceRepository` — plus the page seam they
//  share (`W4PageLoader`, `W4PageTarget`, `W4PageSnapshot`).
//
//  EVIDENCE MAP — read this before adding an assertion.
//
//    [V] `Fixtures/W4/home.html` is a REAL capture of `index.php?r=site/index` (sanitized: names and
//        UWC ids replaced). Every value asserted about the composed `HomeSnapshot` — the greeting,
//        the signed-in UWC id, both 0/0 attendance meters, the ten `#links` entries, the on-campus
//        chip, ISO week 33 of 2026 with seven days — comes straight off it, and each is already
//        pinned independently by the Wave 4 parser suites. The point here is not to re-test the
//        parsers: it is to prove that **one** response reaches all five of them.
//
//    [V] `Fixtures/W4/extraacademics-menu.html` and `academics-menu.html` are real captures too,
//        used here as "some W4 page" — these two repositories deliberately do not parse their
//        contents (see `ExtraAcademicsRepository`'s header for why).
//
//    [I] The `academics/feeds` markup is SYNTHESIZED. That page has never been captured, and it is
//        the one page that must never become a fixture — it carries password-equivalent tokens
//        (features.md §1.14, §2.5). The feed HTML below is written inline with an obviously fake
//        token so the secret-handling assertions have something to chase.
//
//  Nothing here touches the network: every repository is built on a stub `W4RouteFetching`, a
//  `W4PageCache` rooted in a fresh temporary directory, and an injected `W4RequestContext`.
//

import XCTest
@testable import BetterW4

// MARK: - Stub transport

/// Records every route asked for and answers with canned HTML or a canned error.
///
/// An actor because the coalescing test hits it from eight concurrent callers and the call count
/// has to be trustworthy.
private actor StubRouteFetcher: W4RouteFetching {

    /// Route → HTML.
    private var responses: [String: String]
    /// Thrown instead of answering, when set.
    private var failure: Error?
    /// Artificial latency, so concurrent callers actually overlap.
    private var delayNanoseconds: UInt64 = 0

    private(set) var requestedRoutes: [String] = []

    var callCount: Int { requestedRoutes.count }

    init(responses: [String: String] = [:]) {
        self.responses = responses
    }

    func setResponse(_ html: String, for route: String) {
        responses[route] = html
    }

    func setFailure(_ error: Error?) {
        failure = error
    }

    func setDelay(nanoseconds: UInt64) {
        delayNanoseconds = nanoseconds
    }

    func fetchRoute(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4RouteResponse {
        requestedRoutes.append(route)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let failure { throw failure }
        guard let html = responses[route] else {
            throw W4Error.httpError(status: 404, route: route)
        }
        return W4RouteResponse(html: html, finalURL: W4Routes.url(route), contentType: "text/html")
    }
}

/// Feed tokens in memory instead of the Keychain, so the suite needs no Keychain entitlement and
/// leaves nothing behind on the machine that runs it.
private final class InMemoryFeedStore: PersonalFeedStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: PersonalFeedSnapshot] = [:]

    func loadFeeds(for uwcId: String) -> PersonalFeedSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return storage[uwcId]
    }

    func saveFeeds(_ snapshot: PersonalFeedSnapshot, for uwcId: String) {
        lock.lock(); defer { lock.unlock() }
        storage[uwcId] = snapshot
    }

    func deleteFeeds(for uwcId: String) {
        lock.lock(); defer { lock.unlock() }
        storage[uwcId] = nil
    }
}

// MARK: - Tests

final class HomeRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    private static let uwcId = "nc26abcd"

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        cache = W4PageCache(root: cacheRoot)
    }

    override func tearDownWithError() throws {
        if let cacheRoot { try? FileManager.default.removeItem(at: cacheRoot) }
        cache = nil
        cacheRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures and contexts

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/\(name).html")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: source, encoding: .utf8)
    }

    private var signedInContext: W4RequestContext {
        W4RequestContext(
            student: Student(
                studentId: Self.uwcId,
                name: "Alex Andersen",
                pictureId: nil,
                classLabel: nil
            ),
            credentials: W4Credentials(sessionId: "test-session")
        )
    }

    private var demoContext: W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func makeHomeRepository(_ stub: StubRouteFetcher, demo: Bool = false) -> HomeRepository {
        let context = demo ? demoContext : signedInContext
        return HomeRepository(client: stub, cache: cache, context: { context })
    }

    // MARK: - HomeRepository: demo

    /// Rule 3a of the wave: branch on demo **before** any fetch. A demo build that quietly opens a
    /// socket is the failure mode this whole gate exists to prevent.
    func testDemoSessionReturnsDemoDataAndNeverFetches() async throws {
        let stub = StubRouteFetcher()
        let repository = makeHomeRepository(stub, demo: true)

        let loaded = try await repository.snapshot()
        let calls = await stub.callCount

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(loaded.value.page.greetingName, "Demo Student")
        XCTAssertEqual(calls, 0, "demo mode must never reach the transport")
    }

    /// The raw-HTML seam has no demo answer, and says so with a typed error rather than handing a
    /// fabricated page to the real parsers.
    func testHomePageRefusesToInventHTMLInDemo() async throws {
        let stub = StubRouteFetcher()
        let repository = makeHomeRepository(stub, demo: true)

        do {
            _ = try await repository.homePage()
            XCTFail("homePage() must not succeed in demo mode")
        } catch let error as HomeRepositoryError {
            XCTAssertEqual(error, .demoSessionHasNoHTML)
        }

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0)
    }

    // MARK: - HomeRepository: one fetch, five parsers

    /// The item's headline claim: **one** `site/index` response fills the Home screen, the two
    /// attendance meters, the timetable week and the page chrome.
    func testOneFetchFillsHomeMetersTimetableAndChrome() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        let loaded = try await repository.snapshot()
        let snapshot = loaded.value
        let routes = await stub.requestedRoutes

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(routes, [W4Routes.R.home], "exactly one request, to site/index")

        // Home proper [V]
        XCTAssertEqual(snapshot.page.greetingName, "Alex Andersen")
        XCTAssertEqual(snapshot.page.uwcId, "nc26abcd")
        XCTAssertEqual(snapshot.page.links.count, 10)
        XCTAssertEqual(snapshot.page.serverVersion, "25.9.1")

        // Attendance meters [V] — no second request to people/students/absences
        XCTAssertEqual(snapshot.meters.academic, AttendanceMeter(absences: 0, latenesses: 0))
        XCTAssertEqual(snapshot.meters.extraAcademic, AttendanceMeter(absences: 0, latenesses: 0))

        // Timetable week [V] — ISO week 33 of 2026, seven days
        let week = try XCTUnwrap(snapshot.week)
        XCTAssertEqual(week.year, 2026)
        XCTAssertEqual(week.week, 33)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.source, HomeRepository.homeWeekSource)
        let weekFetchedAt = try XCTUnwrap(week.fetchedAt)
        XCTAssertEqual(weekFetchedAt, snapshot.fetchedAt, "the repository stamps the clock, not the parser")

        // Chrome [V]
        XCTAssertEqual(snapshot.campus?.isOnCampus, true)
        XCTAssertTrue(snapshot.notifications.isEmpty, "the real capture ships an empty bell (bug B8)")

        XCTAssertFalse(snapshot.isEmpty)
    }

    /// The response is on disk afterwards, under the key siblings are told to read.
    func testFetchStoresThePageUnderTheAdvertisedCacheKey() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])

        _ = try await makeHomeRepository(stub).snapshot()

        let stored = await cache.page(surface: .home, key: HomeRepository.cacheKey, uwcId: Self.uwcId)
        XCTAssertNotNil(stored, "siblings read this exact entry")
        XCTAssertEqual(stored?.isStale, false)
    }

    // MARK: - HomeRepository: cache policy

    func testCachedPageInsideItsTTLIsServedWithoutARequest() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        let second = try await repository.snapshot()
        let calls = await stub.callCount

        XCTAssertEqual(calls, 1, "a page inside CachePolicy.ttl(for: .home) must not refetch")
        XCTAssertTrue(second.freshness.isFromCache)
        XCTAssertEqual(second.value.page.greetingName, "Alex Andersen")
    }

    func testForceRefreshBypassesAFreshCache() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        let second = try await repository.snapshot(forceRefresh: true)
        let calls = await stub.callCount

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(second.freshness, .fresh)
    }

    func testCachedSnapshotNeverFetches() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        let cold = await repository.cachedSnapshot()
        let callsWhileCold = await stub.callCount
        XCTAssertNil(cold, "nothing cached yet is nil, not a fetch")
        XCTAssertEqual(callsWhileCold, 0)

        _ = try await repository.snapshot()
        let warm = await repository.cachedSnapshot()
        let callsWhileWarm = await stub.callCount

        XCTAssertNotNil(warm)
        XCTAssertEqual(callsWhileWarm, 1)
    }

    /// The donation door: the login flow and the D-23 chrome hook already hold a Home response.
    func testIngestSeedsTheCacheSoTheNextReadIsFree() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        await repository.ingest(html: home, finalURL: W4Routes.url(W4Routes.R.home))
        let loaded = try await repository.snapshot()
        let calls = await stub.callCount

        XCTAssertEqual(calls, 0, "a donated Home page must not be refetched")
        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(loaded.value.page.greetingName, "Alex Andersen")
    }

    func testInvalidateForcesTheNextReadBackToTheNetwork() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        await repository.invalidate()
        _ = try await repository.snapshot()
        let calls = await stub.callCount

        XCTAssertEqual(calls, 2)
    }

    // MARK: - HomeRepository: coalescing

    /// Several screens wake at once on a cold cache. W4 runs on one small Apache box behind a serial
    /// request gate; they get **one** request between them.
    func testConcurrentCallersShareASingleFetch() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        await stub.setDelay(nanoseconds: 40_000_000)
        let repository = makeHomeRepository(stub)

        let snapshots = try await withThrowingTaskGroup(of: HomeSnapshot.self) { group -> [HomeSnapshot] in
            for _ in 0..<8 {
                group.addTask { try await repository.snapshot().value }
            }
            var collected: [HomeSnapshot] = []
            for try await snapshot in group { collected.append(snapshot) }
            return collected
        }
        let calls = await stub.callCount

        XCTAssertEqual(snapshots.count, 8)
        XCTAssertEqual(calls, 1, "eight readers, one site/index request")
        XCTAssertTrue(snapshots.allSatisfy { $0.page.uwcId == "nc26abcd" })
    }

    // MARK: - HomeRepository: failure behaviour

    /// Offline with a warm cache is a working app, not an error screen (features.md §3 rule 4).
    func testFetchFailureFallsBackToTheCachedCopy() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        await stub.setFailure(URLError(.notConnectedToInternet))

        let loaded = try await repository.snapshot(forceRefresh: true)

        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(loaded.value.page.greetingName, "Alex Andersen")
    }

    /// Even a stale copy beats an empty screen — and it is reported as stale, not as fresh.
    func testStaleCachedCopyIsServedAndFlaggedWhenTheFetchFails() async throws {
        let home = try fixture("home")
        let ancient = TimeProvider.now.addingTimeInterval(-CachePolicy.ttl(for: .home) - 600)
        await cache.store(
            html: home,
            surface: .home,
            key: HomeRepository.cacheKey,
            uwcId: Self.uwcId,
            finalURL: nil,
            contentType: nil,
            fetchedAt: ancient
        )

        let stub = StubRouteFetcher()
        await stub.setFailure(W4Error.httpError(status: 500, route: W4Routes.R.home))
        let repository = makeHomeRepository(stub)

        let loaded = try await repository.snapshot()
        let calls = await stub.callCount

        switch loaded.freshness {
        case .cached(_, let isStale):
            XCTAssertTrue(isStale, "a copy past its TTL must say so")
        default:
            XCTFail("expected the stale cached copy, got \(loaded.freshness)")
        }
        XCTAssertEqual(loaded.value.page.greetingName, "Alex Andersen")
        XCTAssertEqual(calls, 1, "a stale copy still triggers exactly one refresh attempt")
    }

    /// The one error a repository may never hide. Swallowing it behind yesterday's HTML strands the
    /// app in a dead session with no way back to the login screen.
    func testSessionExpiredPropagatesEvenWithAWarmCache() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        await stub.setFailure(W4Error.sessionExpired)

        do {
            _ = try await repository.snapshot(forceRefresh: true)
            XCTFail("sessionExpired must propagate")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// 403 without `Login Required` means "signed in, wrong role". Treating it as session death
    /// ejects a student who opened a staff-only page (features.md §3 rule 6).
    func testForbiddenIsNotTreatedAsADeadSession() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        await stub.setFailure(W4Error.forbidden)

        // With a warm cache: served from cache, no throw at all.
        let loaded = try await repository.snapshot(forceRefresh: true)
        XCTAssertTrue(loaded.freshness.isFromCache)

        // With a cold cache: the error surfaces as .forbidden, never rewritten to .sessionExpired.
        await cache.clear(uwcId: Self.uwcId)
        do {
            _ = try await repository.snapshot(forceRefresh: true)
            XCTFail("a forbidden page with no cached copy must fail")
        } catch let error as W4Error {
            guard case .forbidden = error else {
                return XCTFail("expected .forbidden, got \(error)")
            }
        }
    }

    /// Cancellation belongs to the caller; it must not be laundered into a cached result.
    func testCancellationPropagates() async throws {
        let home = try fixture("home")
        let stub = StubRouteFetcher(responses: [W4Routes.R.home: home])
        let repository = makeHomeRepository(stub)

        _ = try await repository.snapshot()
        await stub.setFailure(CancellationError())

        do {
            _ = try await repository.snapshot(forceRefresh: true)
            XCTFail("CancellationError must propagate")
        } catch is CancellationError {
            // expected
        }
    }

    // MARK: - The shared page seam

    /// `#content_inner` is [V] on every full-page fixture; it is what the uncaptured surfaces render
    /// until someone captures them.
    func testPageSnapshotExposesTheContentWell() throws {
        let snapshot = W4PageSnapshot(html: try fixture("extraacademics-menu"), fetchedAt: Date())

        XCTAssertEqual(snapshot.heading, "Extra Academics")
        let fragment = try XCTUnwrap(snapshot.contentFragmentHTML)
        XCTAssertTrue(fragment.contains("Extra Academics"))
    }

    // MARK: - FeedsRepository

    /// **[I]** — synthesized. `academics/feeds` has never been captured and must never become a
    /// fixture; the token below is fake and exists only so the leak assertions have a needle.
    private static let feedToken = "ZZFAKETOKEN00000ZZ"

    private static func feedsHTML(token: String = feedToken) -> String {
        let entries = PersonalFeedKind.allCases.map { kind in
            "<li><a href=\"https://w4.uwcrcn.no/index.php?r=\(kind.route)&amp;token=\(token)\">"
                + "\(kind.displayName)</a></li>"
        }.joined()
        return """
        <html><body><div id="content_inner"><h2>Feeds</h2><ul>\(entries)</ul>
        <a href="https://calendar.google.com/calendar/ical/school/public/basic.ics">School calendar</a>
        <a href="https://w4.uwcrcn.no/index.php?r=academics/feeds">Feeds</a>
        </div></body></html>
        """
    }

    private func makeFeedsRepository(
        _ stub: StubRouteFetcher,
        store: PersonalFeedStoring,
        demo: Bool = false
    ) -> FeedsRepository {
        let context = demo ? demoContext : signedInContext
        return FeedsRepository(client: stub, cache: cache, store: store, context: { context })
    }

    func testFeedsAreParsedFromTheirRoutesAndKeptInDeclarationOrder() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()

        let loaded = try await makeFeedsRepository(stub, store: store).feeds()

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.map(\.kind), PersonalFeedKind.allCases)
        XCTAssertEqual(loaded.value.count, 8)
    }

    /// The whole reason this repository is different: the response holds eight live secrets, so it
    /// never reaches the on-disk page cache, and nothing reaches `UserDefaults`.
    func testFeedTokenNeverReachesDiskCacheOrUserDefaults() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()

        let loaded = try await makeFeedsRepository(stub, store: store).feeds()
        XCTAssertFalse(loaded.value.isEmpty, "the leak assertions below only mean something if we got feeds")

        // 1. Nothing under Caches/W4Pages — not under the feeds key, not under any key.
        let cachedFeedPage = await cache.page(surface: .feeds, key: W4Routes.R.feeds, uwcId: Self.uwcId)
        let bytesOnDisk = await cache.sizeInBytes()
        XCTAssertNil(cachedFeedPage)
        XCTAssertEqual(bytesOnDisk, 0, "academics/feeds must not be written to disk at all")
        for file in Self.files(under: cacheRoot) {
            let contents = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            XCTAssertFalse(contents.contains(Self.feedToken), "a feed token reached \(file.lastPathComponent)")
        }

        // 2. Nothing in UserDefaults, which is an unencrypted plist inside every backup.
        for (_, value) in UserDefaults.standard.dictionaryRepresentation() {
            XCTAssertFalse(String(describing: value).contains(Self.feedToken), "a feed token reached UserDefaults")
        }

        // 3. Anything a human or a log line could see is redacted.
        for feed in loaded.value {
            XCTAssertTrue(feed.url.absoluteString.contains(Self.feedToken), "the live URL still works")
            XCTAssertFalse(feed.redactedURLText.contains(Self.feedToken))
            XCTAssertFalse("\(feed)".contains(Self.feedToken), "string interpolation must not leak it")
            XCTAssertFalse(String(reflecting: feed).contains(Self.feedToken))
        }
        let snapshotDescription = "\(PersonalFeedSnapshot(feeds: loaded.value, fetchedAt: Date()))"
        XCTAssertFalse(snapshotDescription.contains(Self.feedToken))
    }

    func testStoredFeedsInsideTheirTTLDoNotRefetch() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()
        let repository = makeFeedsRepository(stub, store: store)

        _ = try await repository.feeds()
        let second = try await repository.feeds()
        let calls = await stub.callCount

        XCTAssertEqual(calls, 1)
        XCTAssertTrue(second.freshness.isFromCache)
        XCTAssertEqual(second.value.count, 8)
    }

    func testFeedsFallBackToTheStoredCopyWhenTheRefreshFails() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()
        let repository = makeFeedsRepository(stub, store: store)

        _ = try await repository.feeds()
        await stub.setFailure(URLError(.timedOut))

        let loaded = try await repository.feeds(forceRefresh: true)

        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(loaded.value.count, 8)
    }

    func testFeedsSessionExpiredStillPropagates() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()
        let repository = makeFeedsRepository(stub, store: store)

        _ = try await repository.feeds()
        await stub.setFailure(W4Error.sessionExpired)

        do {
            _ = try await repository.feeds(forceRefresh: true)
            XCTFail("sessionExpired must propagate from FeedsRepository too")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// An unrecognisable page must not wipe good tokens.
    func testAnEmptyFeedPageKeepsThePreviouslyStoredFeeds() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()
        let repository = makeFeedsRepository(stub, store: store)

        _ = try await repository.feeds()
        await stub.setResponse("<html><body><div id=\"content_inner\"></div></body></html>", for: W4Routes.R.feeds)

        let loaded = try await repository.feeds(forceRefresh: true)

        XCTAssertEqual(loaded.value.count, 8)
        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(store.loadFeeds(for: Self.uwcId)?.feeds.count, 8)
    }

    /// Off-host URLs and W4 routes that are not feeds are discarded, not guessed at.
    func testFeedExtractionIgnoresOffHostAndUnrelatedRoutes() {
        let html = """
        <html><body>
        <a href="https://evil.example.com/index.php?r=academics/feeds/acttical&token=x">not W4</a>
        <a href="https://w4.uwcrcn.no/index.php?r=academics/feeds">the page itself</a>
        <a href="https://w4.uwcrcn.no/index.php?r=site/rss">announcements rss</a>
        <a href="/index.php?r=academics/feeds/combottical&amp;token=abc">combined calendar</a>
        </body></html>
        """

        let feeds = FeedsRepository.feeds(in: html)

        XCTAssertEqual(feeds.count, 1)
        XCTAssertEqual(feeds.first?.kind, .combinedICS)
        XCTAssertEqual(feeds.first?.url.host, W4Routes.host)
    }

    func testDemoFeedsCarryNoTokenAndNeverFetch() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()

        let loaded = try await makeFeedsRepository(stub, store: store, demo: true).feeds()
        let calls = await stub.callCount

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(loaded.value.isEmpty)
        for feed in loaded.value {
            XCTAssertFalse(feed.url.absoluteString.lowercased().contains("token"))
        }
        XCTAssertNil(store.loadFeeds(for: Student.demoStudentId), "demo must not write a feed store entry")
    }

    func testClearDropsTheStoredFeeds() async throws {
        let stub = StubRouteFetcher(responses: [W4Routes.R.feeds: Self.feedsHTML()])
        let store = InMemoryFeedStore()
        let repository = makeFeedsRepository(stub, store: store)

        _ = try await repository.feeds()
        XCTAssertNotNil(store.loadFeeds(for: Self.uwcId))

        await repository.clear()
        let stored = await repository.storedFeeds()

        XCTAssertNil(store.loadFeeds(for: Self.uwcId))
        XCTAssertNil(stored)
    }

    // MARK: - ExtraAcademicsRepository

    private func makeExtraAcademicsRepository(
        _ stub: StubRouteFetcher,
        demo: Bool = false
    ) -> ExtraAcademicsRepository {
        let context = demo ? demoContext : signedInContext
        return ExtraAcademicsRepository(client: stub, cache: cache, context: { context })
    }

    func testExtraAcademicsRoutesMatchTheCapturedMenu() {
        // [V] every one of these appears in `#dynamic_menu_extraacademics` of the EA capture.
        XCTAssertEqual(ExtraAcademicsPage.myActivities.route, "extraacademics/activities/myactivities")
        XCTAssertEqual(ExtraAcademicsPage.diary.route, "extraacademics/activities/myactivities/diary")
        XCTAssertEqual(ExtraAcademicsPage.portfolio.route, "extraacademics/activities/myportfolio")
        XCTAssertEqual(ExtraAcademicsPage.interviews.route, "extraacademics/activities/interviews")
        XCTAssertEqual(ExtraAcademicsPage.safetyNet.route, "extraacademics/safetynet/mysafetynet")
    }

    func testExtraAcademicsCachesEachPageSeparately() async throws {
        let menu = try fixture("extraacademics-menu")
        let stub = StubRouteFetcher(responses: [
            ExtraAcademicsPage.myActivities.route: menu,
            ExtraAcademicsPage.diary.route: menu
        ])
        let repository = makeExtraAcademicsRepository(stub)

        _ = try await repository.page(.myActivities)
        _ = try await repository.page(.diary)
        let again = try await repository.page(.myActivities)
        let routes = await stub.requestedRoutes

        XCTAssertEqual(
            routes,
            [ExtraAcademicsPage.myActivities.route, ExtraAcademicsPage.diary.route],
            "two pages, two requests — and no third for the repeat"
        )
        XCTAssertTrue(again.freshness.isFromCache)
    }

    func testExtraAcademicsDemoNeverFetchesAndStillRenders() async throws {
        let stub = StubRouteFetcher()
        let loaded = try await makeExtraAcademicsRepository(stub, demo: true).page(.safetyNet)
        let calls = await stub.callCount

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(loaded.value.heading, "My SafetyNet")
        XCTAssertNotNil(loaded.value.contentFragmentHTML)
    }

    func testExtraAcademicsFallsBackToCacheAndPropagatesSessionExpiry() async throws {
        let menu = try fixture("extraacademics-menu")
        let stub = StubRouteFetcher(responses: [ExtraAcademicsPage.portfolio.route: menu])
        let repository = makeExtraAcademicsRepository(stub)

        _ = try await repository.page(.portfolio)

        await stub.setFailure(W4Error.httpError(status: 503, route: ExtraAcademicsPage.portfolio.route))
        let cached = try await repository.page(.portfolio, forceRefresh: true)
        XCTAssertTrue(cached.freshness.isFromCache)

        await stub.setFailure(W4Error.sessionExpired)
        do {
            _ = try await repository.page(.portfolio, forceRefresh: true)
            XCTFail("sessionExpired must propagate")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    func testExtraAcademicsInvalidateClearsEveryPage() async throws {
        let menu = try fixture("extraacademics-menu")
        let stub = StubRouteFetcher(responses: [ExtraAcademicsPage.interviews.route: menu])
        let repository = makeExtraAcademicsRepository(stub)

        _ = try await repository.page(.interviews)
        await repository.invalidate()
        _ = try await repository.page(.interviews)
        let calls = await stub.callCount

        XCTAssertEqual(calls, 2)
    }

    // MARK: - ResourceRepository

    private func makeResourceRepository(
        _ stub: StubRouteFetcher,
        demo: Bool = false
    ) -> ResourceRepository {
        let context = demo ? demoContext : signedInContext
        return ResourceRepository(client: stub, cache: cache, context: { context })
    }

    func testResourcesAreCacheFirstAndSurviveAFailedRefresh() async throws {
        let page = try fixture("academics-menu")
        let stub = StubRouteFetcher(responses: [W4Routes.R.resources: page])
        let repository = makeResourceRepository(stub)

        let first = try await repository.resources()
        XCTAssertEqual(first.freshness, .fresh)

        let second = try await repository.resources()
        let callsAfterSecond = await stub.callCount
        XCTAssertEqual(callsAfterSecond, 1)
        XCTAssertTrue(second.freshness.isFromCache)

        await stub.setFailure(URLError(.networkConnectionLost))
        let third = try await repository.resources(forceRefresh: true)
        XCTAssertTrue(third.freshness.isFromCache)
    }

    func testResourcesDemoNeverFetches() async throws {
        let stub = StubRouteFetcher()
        let loaded = try await makeResourceRepository(stub, demo: true).resources()
        let calls = await stub.callCount

        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(loaded.value.heading, "Resources")
    }

    func testResourcesUseTheVerifiedRoute() async throws {
        let page = try fixture("academics-menu")
        let stub = StubRouteFetcher(responses: [W4Routes.R.resources: page])

        _ = try await makeResourceRepository(stub).resources()
        let routes = await stub.requestedRoutes

        XCTAssertEqual(routes, ["academics/resources/resources"])
    }

    // MARK: - Helpers

    private static func files(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
    }
}
