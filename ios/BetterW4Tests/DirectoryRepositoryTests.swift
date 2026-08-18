//
//  DirectoryRepositoryTests.swift
//  BetterW4Tests
//
//  Unit tests for `DirectoryRepository`, `ProfileRepository`, `DirectoryPinStore` and the
//  `DirectoryStore` legacy bridge (plan Wave 5 item 5.5).
//
//  SEAM. Nothing here touches the network. Both repositories take four injectables — a
//  `W4PeopleFetching` transport, a `W4PageCache` pointed at a temp directory, a `W4PeopleStoring`
//  persistence seam, and a `() throws -> W4RequestContext` provider — so a whole repository can be
//  stood up without a Keychain, a SwiftData container, a `URLSession`, or `W4HTTPClient` having
//  been modified to accommodate a test.
//
//  FIXTURE PROVENANCE. `people-list.html` is **[I] SYNTHESIZED** (see its own header) and the
//  sweep pages below are generated in this file. No assertion here is evidence about W4's markup;
//  they all verify this port's repository behaviour. The one thing that *is* verified —
//  `{uwc_id}_thumb.jpg` and per-anchor kind detection — comes from the Home capture and is already
//  covered by `W4PeopleParserTests`.
//
//  IDENTITIES. Invented `nc00…` / `nc99…` ids and made-up names (`reviewer-notes.md` §8).
//

import XCTest
@testable import BetterW4

// MARK: - Stub transport

private final class StubPeopleFetcher: W4PeopleFetching, @unchecked Sendable {

    struct Call: Sendable {
        let route: String
        let query: [String: String]
        let priority: FetchPriority

        var isOpportunistic: Bool {
            if case .opportunistic = priority { return true }
            return false
        }

        var isImportant: Bool {
            if case .important = priority { return true }
            return false
        }
    }

    /// Answers a request; throw to simulate a failure.
    private let responder: @Sendable (String, [String: String]) async throws -> String

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _inFlight = 0
    private var _peakInFlight = 0
    private var _finished = 0

    init(responder: @escaping @Sendable (String, [String: String]) async throws -> String) {
        self.responder = responder
    }

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    /// The highest number of requests this stub ever had in flight at once.
    var peakInFlight: Int {
        lock.lock(); defer { lock.unlock() }
        return _peakInFlight
    }

    var finishedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _finished
    }

    func fetchPage(
        route: String,
        query: [String: String],
        priority: FetchPriority,
        credentials: W4Credentials,
        uwcId: String
    ) async throws -> W4PeopleFetchResult {
        lock.lock()
        _calls.append(Call(route: route, query: query, priority: priority))
        _inFlight += 1
        _peakInFlight = max(_peakInFlight, _inFlight)
        lock.unlock()

        defer {
            lock.lock()
            _inFlight -= 1
            _finished += 1
            lock.unlock()
        }

        let html = try await responder(route, query)
        return W4PeopleFetchResult(html: html, finalURL: W4Routes.url(route, query))
    }
}

/// A latch a stubbed request can park on, so "this request was still in flight when that one
/// finished" is a fact rather than a race against a sleep.
private actor RequestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var waitingCount: Int { waiters.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let parked = waiters
        waiters.removeAll()
        for continuation in parked { continuation.resume() }
    }
}

// MARK: - Stub store

private actor SpyPeopleStore: W4PeopleStoring {
    private(set) var people: [DirectoryPerson] = []
    private(set) var replaceCallCount = 0
    private(set) var upsertCallCount = 0

    func replaceAll(_ incoming: [DirectoryPerson]) async {
        replaceCallCount += 1
        guard !incoming.isEmpty else { return }
        people = incoming
    }

    func upsert(_ incoming: [DirectoryPerson]) async {
        upsertCallCount += 1
        var byId = Dictionary(people.map { ($0.uwcId, $0) }, uniquingKeysWith: { _, new in new })
        for person in incoming { byId[person.uwcId] = person }
        people = byId.values.sorted { $0.uwcId < $1.uwcId }
    }

    func allPeople() async -> [DirectoryPerson] { people }

    func person(uwcId: String) async -> DirectoryPerson? {
        people.first { $0.uwcId == uwcId }
    }

    func seed(_ incoming: [DirectoryPerson]) { people = incoming }
}

// MARK: - Tests

final class DirectoryRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    private static func context(uwcId: String, session: String) -> W4RequestContext {
        W4RequestContext(
            student: Student(
                studentId: uwcId,
                name: "Test Person",
                pictureId: nil,
                classLabel: nil
            ),
            credentials: W4Credentials(sessionId: session)
        )
    }

    private let signedIn = DirectoryRepositoryTests.context(uwcId: "nc99zzz", session: "stub-session")
    private let otherStudent = DirectoryRepositoryTests.context(uwcId: "nc99yyy", session: "stub-session-2")
    private let demoContext = W4RequestContext(student: .demo, credentials: .empty)

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("W4PagesTests-\(UUID().uuidString)", isDirectory: true)
        cache = W4PageCache(root: cacheRoot)
        defaultsSuiteName = "DirectoryRepositoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheRoot)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        cache = nil
        cacheRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A synthesized `ul.user-list` page. **[I]** — no W4 people list has ever been captured; this
    /// exercises the repository's paging and identity handling, nothing about W4's markup.
    private static func listPage(ids: [String], kind: DirectoryPersonKind, hasNext: Bool) -> String {
        let route = kind == .staff ? "people/staff/staff" : "people/students/student"
        let rows = ids.map { id in
            """
            <li>
              <a href="/index.php?r=\(route)&amp;uwc_id=\(id)"><img class="photo" src="/files/user_photos/\(id)_thumb.jpg" alt="Photo of \(id)" /></a>
              <a href="/index.php?r=\(route)&amp;uwc_id=\(id)">Person \(id.uppercased())</a>
              <br />Neverland<br />
            </li>
            """
        }.joined(separator: "\n")

        let pager = hasNext
            ? #"<div class="pager"><ul><li class="next"><a href="/index.php?r=people/students/all&amp;page=2">Next</a></li></ul></div>"#
            : ""

        return """
        <html><body><div id="content_inner">
          <h2>People</h2>
          <ul class="user-list">
          \(rows)
          </ul>
          \(pager)
        </div></body></html>
        """
    }

    /// 200 distinct, obviously-invented uwc ids.
    private static func makeIds(_ marker: String, _ count: Int) -> [String] {
        let letters = ["a", "b", "c", "d", "e", "f", "g", "h", "j", "k"]
        return (0..<count).map { index in
            let first = letters[(index / 100) % letters.count]
            let second = letters[(index / 10) % letters.count]
            let third = letters[index % letters.count]
            return "nc00\(marker)\(first)\(second)\(third)"
        }
    }

    /// The default sweep's five pages: four of 50 students plus one of 20 staff.
    private static func sweepPages() -> [String: String] {
        let studentIds = makeIds("s", 200)
        return [
            "people/students/all|1": listPage(ids: Array(studentIds[0..<50]), kind: .student, hasNext: true),
            "people/students/all|2": listPage(ids: Array(studentIds[50..<100]), kind: .student, hasNext: true),
            "people/students/all|3": listPage(ids: Array(studentIds[100..<150]), kind: .student, hasNext: true),
            "people/students/all|4": listPage(ids: Array(studentIds[150..<200]), kind: .student, hasNext: false),
            "people/staff/current|1": listPage(ids: makeIds("t", 20), kind: .staff, hasNext: false)
        ]
    }

    private func makeRepository(
        fetcher: W4PeopleFetching,
        store: W4PeopleStoring,
        context: W4RequestContext
    ) -> DirectoryRepository {
        DirectoryRepository(
            fetcher: fetcher,
            cache: cache,
            store: store,
            pins: DirectoryPinStore(defaults: defaults),
            context: { context }
        )
    }

    private func makeProfileRepository(
        fetcher: W4PeopleFetching,
        store: W4PeopleStoring,
        context: W4RequestContext
    ) -> ProfileRepository {
        ProfileRepository(
            fetcher: fetcher,
            cache: cache,
            store: store,
            context: { context }
        )
    }

    private func primeCache(
        source: PeopleDirectorySource,
        page: Int = 1,
        html: String,
        uwcId: String,
        fetchedAt: Date
    ) async {
        await cache.store(
            html: html,
            surface: .people,
            key: DirectoryRepository.cacheKey(source: source, page: page),
            uwcId: uwcId,
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Demo never touches the network

    func testDemoSessionReturnsDemoPeopleAndMakesNoRequest() async throws {
        let fetcher = StubPeopleFetcher { _, _ in
            XCTFail("Demo mode must never fetch")
            return ""
        }
        let store = SpyPeopleStore()
        let repository = makeRepository(fetcher: fetcher, store: store, context: demoContext)

        let page = try await repository.people(source: .allStudents)
        XCTAssertEqual(page.freshness, .demo)
        XCTAssertFalse(page.value.people.isEmpty)
        XCTAssertTrue(page.value.people.allSatisfy { $0.kind == .student })

        let swept = try await repository.syncFullDirectory()
        XCTAssertEqual(swept.freshness, .demo)
        XCTAssertFalse(swept.value.isEmpty)
        XCTAssertEqual(fetcher.calls.count, 0, "A demo session must make zero W4 requests")
    }

    // MARK: - One list page

    func testFetchesParsesCachesAndStoresAListPage() async throws {
        let html = try fixture("people-list")
        let fetcher = StubPeopleFetcher { _, _ in html }
        let store = SpyPeopleStore()
        let repository = makeRepository(fetcher: fetcher, store: store, context: signedIn)

        let loaded = try await repository.people(source: .allStudents)

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.people.map(\.uwcId), ["nc00aaa", "nc00bbb", "nc00ccc"])
        // Kind is decided per row href, so the staff row on a page of students stays staff.
        XCTAssertEqual(loaded.value.people.last?.kind, .staff)
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertEqual(fetcher.calls.first?.route, W4Routes.R.studentsAll)
        XCTAssertTrue(fetcher.calls.first?.isImportant == true, "A screen the student is waiting on is .important")

        let stored = await store.allPeople()
        XCTAssertEqual(stored.count, 3)

        let cached = await cache.page(
            surface: .people,
            key: DirectoryRepository.cacheKey(source: .allStudents, page: 1),
            uwcId: signedIn.uwcId
        )
        XCTAssertNotNil(cached, "A fetched page must land in W4PageCache")
    }

    func testFreshCachedPageIsServedWithoutAFetch() async throws {
        let html = try fixture("people-list")
        await primeCache(source: .allStudents, html: html, uwcId: signedIn.uwcId, fetchedAt: Date())

        let fetcher = StubPeopleFetcher { _, _ in
            XCTFail("A fresh cached page must not be refetched")
            return ""
        }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let loaded = try await repository.people(source: .allStudents)
        XCTAssertEqual(loaded.value.people.count, 3)
        XCTAssertEqual(fetcher.calls.count, 0)
        guard case .cached(_, let isStale) = loaded.freshness else {
            return XCTFail("Expected a cached freshness, got \(loaded.freshness)")
        }
        XCTAssertFalse(isStale)
    }

    func testCachedPageIsServedBeforeAnyFetchForInstantRender() async throws {
        let html = try fixture("people-list")
        // Well past the 7-day people TTL, so this also proves a stale page still renders.
        await primeCache(
            source: .allStudents,
            html: html,
            uwcId: signedIn.uwcId,
            fetchedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60)
        )
        let fetcher = StubPeopleFetcher { _, _ in
            XCTFail("cachedPeople(source:) must never fetch")
            return ""
        }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let loaded = await repository.cachedPeople(source: .allStudents)
        XCTAssertEqual(loaded?.value.people.count, 3)
        XCTAssertTrue(loaded?.freshness.isFromCache == true)
        XCTAssertEqual(fetcher.calls.count, 0)
    }

    // MARK: - Failure policy

    func testFailedRefreshFallsBackToTheStaleCachedCopy() async throws {
        let html = try fixture("people-list")
        await primeCache(
            source: .allStudents,
            html: html,
            uwcId: signedIn.uwcId,
            fetchedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60)
        )
        let fetcher = StubPeopleFetcher { _, _ in
            throw W4Error.httpError(status: 500, route: W4Routes.R.studentsAll)
        }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let loaded = try await repository.people(source: .allStudents)
        XCTAssertEqual(loaded.value.people.count, 3)
        guard case .cached(_, let isStale) = loaded.freshness else {
            return XCTFail("Expected the cached copy, got \(loaded.freshness)")
        }
        XCTAssertTrue(isStale, "A cache fallback after a failed fetch must be reported as stale")
    }

    func testFailedFetchWithNoCacheRethrows() async throws {
        let fetcher = StubPeopleFetcher { _, _ in
            throw W4Error.httpError(status: 500, route: W4Routes.R.studentsAll)
        }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        do {
            _ = try await repository.people(source: .allStudents)
            XCTFail("Expected the fetch failure to surface")
        } catch let error as W4Error {
            guard case .httpError(let status, _) = error else {
                return XCTFail("Expected the original httpError, got \(error)")
            }
            XCTAssertEqual(status, 500)
        }
    }

    func testSessionExpiredIsNeverSwallowedByTheCache() async throws {
        let html = try fixture("people-list")
        await primeCache(
            source: .allStudents,
            html: html,
            uwcId: signedIn.uwcId,
            fetchedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60)
        )
        let fetcher = StubPeopleFetcher { _, _ in throw W4Error.sessionExpired }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        do {
            _ = try await repository.people(source: .allStudents)
            XCTFail("sessionExpired must propagate even when a cached copy exists")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("Expected .sessionExpired, got \(error)")
            }
        }
    }

    func testForbiddenIsNotTreatedAsADeadSession() async throws {
        let fetcher = StubPeopleFetcher { _, _ in throw W4Error.forbidden }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        do {
            _ = try await repository.people(source: .staffOnLeave)
            XCTFail("Expected the forbidden error to surface")
        } catch let error as W4Error {
            guard case .forbidden = error else {
                return XCTFail("A wrong-role 403 must stay .forbidden, got \(error)")
            }
        }
    }

    func testSweepThatFailsEverywhereDoesNotWipeTheStore() async throws {
        let store = SpyPeopleStore()
        await store.seed([DirectoryPerson(uwcId: "nc00aaa", name: "Alex Andersen", kind: .student)])
        let fetcher = StubPeopleFetcher { _, _ in
            throw W4Error.httpError(status: 503, route: "people/students/all")
        }
        let repository = makeRepository(fetcher: fetcher, store: store, context: signedIn)

        let loaded = try await repository.syncFullDirectory()
        XCTAssertEqual(loaded.value.map(\.uwcId), ["nc00aaa"])
        let replaceCalls = await store.replaceCallCount
        XCTAssertEqual(replaceCalls, 0, "A sweep that produced nothing must not replace the table")
    }

    // MARK: - The ~200-person sweep

    /// The wave's acceptance criterion, first half: the sweep is serial and `.opportunistic`.
    func testTwoHundredPersonSweepIsSerialAndOpportunistic() async throws {
        let pages = Self.sweepPages()
        let fetcher = StubPeopleFetcher { route, query in
            let page = query["page"] ?? "1"
            guard let html = pages["\(route)|\(page)"] else {
                throw W4Error.httpError(status: 404, route: route)
            }
            return html
        }
        let store = SpyPeopleStore()
        let repository = makeRepository(fetcher: fetcher, store: store, context: signedIn)

        let loaded = try await repository.syncFullDirectory()

        XCTAssertEqual(loaded.value.count, 220)
        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(fetcher.calls.count, 5, "Four student pages plus one staff page")
        XCTAssertEqual(fetcher.peakInFlight, 1, "The sweep must never have two requests in flight")
        XCTAssertTrue(
            fetcher.calls.allSatisfy(\.isOpportunistic),
            "Every sweep request must be .opportunistic so it cannot starve the screen the student is on"
        )
        XCTAssertEqual(fetcher.calls.map { $0.query["page"] ?? "1" }, ["1", "2", "3", "4", "1"])

        let stored = await store.allPeople()
        XCTAssertEqual(stored.count, 220)
        XCTAssertEqual(stored.filter { $0.kind == .staff }.count, 20)
    }

    /// Second half: an `.important` fetch issued while the sweep is running is served *during*
    /// it, not queued behind all 220 people.
    ///
    /// The sweep's first page is parked on a latch, so this is a fact about ordering rather than
    /// a race against a sleep.
    func testImportantFetchIsNotStarvedByARunningSweep() async throws {
        let pages = Self.sweepPages()
        let teachersPage = Self.listPage(ids: ["nc00tzz"], kind: .staff, hasNext: false)
        let latch = RequestLatch()

        let fetcher = StubPeopleFetcher { route, query in
            // Anything the student is waiting on answers immediately; the sweep parks.
            if route.hasPrefix("people/students/staff") { return teachersPage }
            await latch.wait()
            let page = query["page"] ?? "1"
            guard let html = pages["\(route)|\(page)"] else {
                throw W4Error.httpError(status: 404, route: route)
            }
            return html
        }

        let sweeper = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)
        let screen = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let sweep = Task { try await sweeper.syncFullDirectory() }

        // Wait until the sweep's first page is genuinely parked inside the transport.
        var parked = await latch.waitingCount
        while parked == 0 {
            try? await Task.sleep(nanoseconds: 200_000)
            parked = await latch.waitingCount
        }

        let urgent = try await screen.people(source: .myTeachers, priority: .important)
        XCTAssertEqual(urgent.value.people.count, 1, "The important fetch completed while the sweep was still parked")

        let stillParked = await latch.waitingCount
        XCTAssertEqual(stillParked, 1, "The sweep was still waiting when the important fetch returned")

        await latch.open()
        let swept = try await sweep.value
        XCTAssertEqual(swept.value.count, 220)

        let important = fetcher.calls.filter(\.isImportant)
        XCTAssertEqual(important.count, 1)
        XCTAssertEqual(important.first?.route, PeopleDirectorySource.myTeachers.route)
        XCTAssertEqual(fetcher.calls.filter(\.isOpportunistic).count, 5)
    }

    func testSweepUsesCachedPagesAndReportsThemAsCached() async throws {
        let pages: [String: String] = [
            "people/students/all|1": Self.listPage(ids: Self.makeIds("s", 10), kind: .student, hasNext: false),
            "people/staff/current|1": Self.listPage(ids: Self.makeIds("t", 3), kind: .staff, hasNext: false)
        ]
        let fetcher = StubPeopleFetcher { route, query in
            let page = query["page"] ?? "1"
            guard let html = pages["\(route)|\(page)"] else {
                throw W4Error.httpError(status: 404, route: route)
            }
            return html
        }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        _ = try await repository.syncFullDirectory()
        XCTAssertEqual(fetcher.calls.count, 2)

        // Second sweep inside the 7-day TTL: everything comes off disk.
        let second = try await repository.syncFullDirectory()
        XCTAssertEqual(fetcher.calls.count, 2, "A sweep inside the TTL must not refetch")
        XCTAssertTrue(second.freshness.isFromCache)
        XCTAssertEqual(second.value.count, 13)
    }

    // MARK: - Pins

    func testPinsSurviveAResyncAndResolveToPeople() async throws {
        let pages: [String: String] = [
            "people/students/all|1": Self.listPage(ids: Self.makeIds("s", 10), kind: .student, hasNext: false),
            "people/staff/current|1": Self.listPage(ids: Self.makeIds("t", 3), kind: .staff, hasNext: false)
        ]
        let fetcher = StubPeopleFetcher { route, query in
            let page = query["page"] ?? "1"
            guard let html = pages["\(route)|\(page)"] else {
                throw W4Error.httpError(status: 404, route: route)
            }
            return html
        }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        _ = try await repository.syncFullDirectory()
        let people = await repository.storedPeople()
        let target = try XCTUnwrap(people.first)
        await repository.setPinned(true, uwcId: target.uwcId)

        let pinnedBefore = await repository.isPinned(target.uwcId)
        XCTAssertTrue(pinnedBefore)

        _ = try await repository.syncFullDirectory(forceRefresh: true)

        let pinnedAfter = await repository.isPinned(target.uwcId)
        XCTAssertTrue(pinnedAfter, "A re-sync must not drop pins")
        let pinnedPeople = await repository.pinnedPeople()
        XCTAssertEqual(pinnedPeople.map(\.uwcId), [target.uwcId])
    }

    func testPinsAreScopedToTheSignedInUwcId() async throws {
        let fetcher = StubPeopleFetcher { _, _ in "" }
        let mine = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)
        let theirs = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: otherStudent)

        await mine.setPinned(true, uwcId: "nc00aaa")

        let minePins = await mine.pinnedUwcIds()
        let theirPins = await theirs.pinnedUwcIds()
        XCTAssertEqual(minePins, ["nc00aaa"])
        XCTAssertTrue(theirPins.isEmpty, "A different account must never inherit the previous student's pins")
    }

    func testPinStoreReadsLegacyCompositeIds() {
        let store = DirectoryPinStore(defaults: defaults)
        defaults.set(
            ["131|student|nc00aaa", "NC00BBB", "  "],
            forKey: DirectoryPinStore.key(forOwner: "nc99zzz")
        )

        XCTAssertEqual(store.pinned(owner: "nc99zzz"), ["nc00aaa", "nc00bbb"])
    }

    func testTogglePinRoundTrips() async {
        let fetcher = StubPeopleFetcher { _, _ in "" }
        let repository = makeRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let pinned = await repository.togglePin(uwcId: "NC00AAA")
        XCTAssertTrue(pinned)
        let isPinned = await repository.isPinned("nc00aaa")
        XCTAssertTrue(isPinned, "Pins are keyed on the lowercased uwc id")

        let unpinned = await repository.togglePin(uwcId: "nc00aaa")
        XCTAssertFalse(unpinned)
        let remaining = await repository.pinnedUwcIds()
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Search

    func testSearchMatchesNamePrefixCountryAndUwcId() async throws {
        let store = SpyPeopleStore()
        await store.seed([
            DirectoryPerson(uwcId: "nc00aaa", name: "Alex Andersen", kind: .student, country: "Denmark"),
            DirectoryPerson(uwcId: "nc00bbb", name: "Bea Beltrán", kind: .student, country: "Italy"),
            DirectoryPerson(uwcId: "nc00ccc", name: "Chris Chen", kind: .staff)
        ])
        let fetcher = StubPeopleFetcher { _, _ in "" }
        let repository = makeRepository(fetcher: fetcher, store: store, context: signedIn)

        let byName = await repository.search("bel")
        XCTAssertEqual(byName.map(\.uwcId), ["nc00bbb"])

        let folded = await repository.search("beltran")
        XCTAssertEqual(folded.map(\.uwcId), ["nc00bbb"], "Diacritics must fold")

        let byCountry = await repository.search("denmark")
        XCTAssertEqual(byCountry.map(\.uwcId), ["nc00aaa"])

        let byId = await repository.search("nc00ccc")
        XCTAssertEqual(byId.map(\.uwcId), ["nc00ccc"])

        let blank = await repository.search("   ")
        XCTAssertTrue(blank.isEmpty)
    }

    // MARK: - Profiles

    private static func profileHTML(uwcId: String, name: String, extra: String = "") -> String {
        let parts = name.split(separator: " ").map(String.init)
        return """
        <html><body><div id="content_inner">
          <table class="detail-view">
            <tr><th>UWC id</th><td>\(uwcId)</td></tr>
            <tr><th>First name</th><td>\(parts.first ?? name)</td></tr>
            <tr><th>Last name</th><td>\(parts.count > 1 ? parts[parts.count - 1] : "")</td></tr>
            \(extra)
          </table>
        </div></body></html>
        """
    }

    func testProfileResolvesByUwcIdOnTheStudentRoute() async throws {
        let html = Self.profileHTML(
            uwcId: "nc00aaa",
            name: "Alex Andersen",
            extra: "<tr><th>Country</th><td>Denmark</td></tr>"
        )
        let fetcher = StubPeopleFetcher { _, _ in html }
        let store = SpyPeopleStore()
        let repository = makeProfileRepository(fetcher: fetcher, store: store, context: signedIn)

        let loaded = try await repository.profile(uwcId: "NC00AAA", kind: .student)

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.uwcId, "nc00aaa", "An upper-case id resolves to the same person")
        XCTAssertEqual(loaded.value.person.name, "Alex Andersen")
        XCTAssertEqual(loaded.value.person.country, "Denmark")
        XCTAssertEqual(loaded.value.person.email, "nc00aaa@uwcrcn.no")
        XCTAssertEqual(fetcher.calls.count, 1)
        XCTAssertEqual(fetcher.calls.first?.route, W4Routes.R.studentProfile)
        XCTAssertEqual(
            fetcher.calls.first?.query["uwc_id"],
            "nc00aaa",
            "The uwc id is a sibling query key, never part of r="
        )

        let stored = await store.allPeople()
        XCTAssertEqual(stored.map(\.uwcId), ["nc00aaa"])
    }

    func testProfileFallsBackFromTheStudentRouteToTheStaffRoute() async throws {
        let staffHTML = Self.profileHTML(uwcId: "nc00ccc", name: "Chris Chen")
        let fetcher = StubPeopleFetcher { route, _ in
            if route == W4Routes.R.studentProfile { throw W4Error.forbidden }
            return staffHTML
        }
        let repository = makeProfileRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let loaded = try await repository.profile(uwcId: "nc00ccc")

        XCTAssertEqual(loaded.value.uwcId, "nc00ccc")
        XCTAssertEqual(loaded.value.person.kind, .staff)
        XCTAssertEqual(fetcher.calls.map(\.route), [W4Routes.R.studentProfile, W4Routes.R.staffProfile])
    }

    func testProfileUsesTheKindTheStoreAlreadyKnows() async throws {
        let store = SpyPeopleStore()
        await store.seed([DirectoryPerson(uwcId: "nc00ccc", name: "Chris Chen", kind: .staff)])
        let html = Self.profileHTML(uwcId: "nc00ccc", name: "Chris Chen")
        let fetcher = StubPeopleFetcher { _, _ in html }
        let repository = makeProfileRepository(fetcher: fetcher, store: store, context: signedIn)

        _ = try await repository.profile(uwcId: "nc00ccc")

        XCTAssertEqual(
            fetcher.calls.map(\.route),
            [W4Routes.R.staffProfile],
            "A kind the directory already recorded must not cost a wasted request"
        )
    }

    func testProfileSessionExpiredStopsTheRouteLadderImmediately() async throws {
        let fetcher = StubPeopleFetcher { _, _ in throw W4Error.sessionExpired }
        let repository = makeProfileRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        do {
            _ = try await repository.profile(uwcId: "nc00aaa")
            XCTFail("sessionExpired must propagate")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("Expected .sessionExpired, got \(error)")
            }
        }
        XCTAssertEqual(fetcher.calls.count, 1, "A dead session must not be retried on the staff route")
    }

    func testMyProfileUsesSiteProfile() async throws {
        let html = Self.profileHTML(uwcId: "nc99zzz", name: "Test Student")
        let fetcher = StubPeopleFetcher { _, _ in html }
        let repository = makeProfileRepository(fetcher: fetcher, store: SpyPeopleStore(), context: signedIn)

        let loaded = try await repository.myProfile()
        XCTAssertEqual(loaded.value.uwcId, "nc99zzz")
        XCTAssertEqual(fetcher.calls.map(\.route), [W4Routes.R.profile])
        XCTAssertTrue(fetcher.calls.first?.query.isEmpty == true)
    }

    func testDemoProfileMakesNoRequest() async throws {
        let fetcher = StubPeopleFetcher { _, _ in
            XCTFail("Demo mode must never fetch")
            return ""
        }
        let repository = makeProfileRepository(fetcher: fetcher, store: SpyPeopleStore(), context: demoContext)

        let loaded = try await repository.myProfile()
        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(loaded.value.uwcId, ProfileRepository.demoOwnUwcId)
        XCTAssertEqual(fetcher.calls.count, 0)
    }

    // MARK: - Search text + legacy bridge

    func testNormalizedSearchTextFoldsDiacriticsAndPunctuation() {
        XCTAssertEqual(DirectorySearchText.normalize("Bea  Beltrán-Ruiz"), "bea beltran ruiz")
        XCTAssertEqual(DirectorySearchText.normalize("   "), "")
    }

    func testLegacyEntityBridgeCarriesTheUwcIdAndNoLectioURL() {
        let person = DirectoryPerson(
            uwcId: "nc00aaa",
            name: "Alex Andersen",
            kind: .staff,
            year: "1",
            country: "Denmark",
            subtitle: "Year 1 · Denmark"
        )
        let entity = DirectoryStore.legacyEntity(person)

        XCTAssertEqual(entity.numericID, "nc00aaa", "The UWC id is the only id W4 has")
        XCTAssertEqual(entity.rawPrefixedID, "nc00aaa")
        XCTAssertEqual(
            entity.entityID.key,
            "teacher|nc00aaa",
            "The entity key is kind + UWC id — W4 is one college, so nothing scopes it by school"
        )
        XCTAssertEqual(entity.kind, .teacher)
        XCTAssertEqual(entity.normalizedName, "alex andersen")
        XCTAssertTrue(entity.searchTokens.contains("nc00aaa"))
        XCTAssertEqual(
            W4PeopleParser.photoURL(forUWCId: entity.numericID)?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_thumb.jpg"
        )
    }
}
