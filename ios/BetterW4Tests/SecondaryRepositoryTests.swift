//
//  SecondaryRepositoryTests.swift
//  BetterW4Tests
//
//  Wave 5 item 5.8a — `DocumentRepository`, `TripRepository`, `TravelRepository`,
//  `GradeRepository`.
//
//  WHAT THESE TESTS ARE FOR. The parsers already have their own suites, and this file does not
//  re-test them: it asserts the *repository* contract, which is the part that is easy to get
//  quietly wrong and impossible to notice in the simulator.
//
//    1. Demo never touches the network. Every demo case runs against a stub client that is armed
//       to throw — so a missed demo branch fails loudly instead of passing on a lucky response.
//    2. A node inside its TTL is served from the page cache with **no request**. That is the
//       stated Done criterion for this item: navigating back into a folder must be free.
//    3. Each folder and each page is cached under its own key, so a tree stays a tree.
//    4. A failed fetch with a usable cached copy returns the cached copy, honestly flagged stale.
//    5. `W4Error.sessionExpired` is never swallowed by rule 4, and `W4Error.forbidden` is never
//       mistaken for it — a student opening a staff-only page must not be logged out.
//
//  THE SEAM. `W4SecondaryFetching` (declared in `DocumentRepository.swift`) is stubbed here, and
//  the session is injected through each repository's `resolveContext` closure. No test touches
//  `URLSession`, the Keychain, or `W4PageCache.shared`: every case gets a throwaway page cache
//  rooted in its own temporary directory.
//
//  A NOTE ON `await` AND `XCTAssert…`. Every read of the stub is hoisted into a `let` before the
//  assertion, because XCTest's autoclosure parameters are not async.
//
//  FIXTURES keep their existing provenance: `documents.html` is a real capture;
//  `documents-folder.html`, `documents-page.html`, `trips.html` and `grades.html` are synthesized
//  ([I]) and say so in their own headers, as does the travel markup at the bottom of this file. An
//  assertion about their contents is an assertion about this pipeline, never about W4.
//

import XCTest
@testable import BetterW4

// MARK: - Stub transport

/// Records every request and answers from a canned table. An `actor` so the repositories (also
/// actors) can call it without a lock.
private actor StubW4SecondaryClient: W4SecondaryFetching {

    struct Call {
        let route: String
        let query: [String: String]
        let priority: FetchPriority
    }

    private(set) var calls: [Call] = []
    private var htmlByRoute: [String: String] = [:]
    private var defaultHTML = "<html><body><div id=\"content_inner\"></div></body></html>"
    private var failure: Error?

    func setHTML(_ html: String, forRoute route: String) {
        htmlByRoute[route] = html
    }

    /// Arms the stub to fail every request. `nil` disarms it.
    func setFailure(_ error: Error?) {
        failure = error
    }

    var callCount: Int { calls.count }
    var requestedRoutes: [String] { calls.map(\.route) }
    var requestedPriorities: [FetchPriority] { calls.map(\.priority) }

    func fetchSecondaryPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4SecondaryPage {
        calls.append(Call(route: route, query: query, priority: priority))
        if let failure { throw failure }
        return W4SecondaryPage(
            html: htmlByRoute[route] ?? defaultHTML,
            finalURL: W4Routes.url(route, query),
            contentType: "text/html"
        )
    }
}

// MARK: - Tests

final class SecondaryRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecondaryRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        cache = W4PageCache(root: cacheRoot)
    }

    override func tearDownWithError() throws {
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        cache = nil
        cacheRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Sessions

    private static let signedInStudent = Student(
        studentId: "nc26abcd",
        name: "Alex Andersen",
        pictureId: nil,
        classLabel: nil
    )

    private var signedIn: W4RequestContext {
        W4RequestContext(
            student: Self.signedInStudent,
            credentials: W4Credentials(sessionId: "phpsessid-for-tests")
        )
    }

    private var demo: W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func resolver(_ context: W4RequestContext) -> @Sendable () throws -> W4RequestContext {
        { context }
    }

    /// Captures nothing, so it stays trivially `@Sendable`.
    private var signedOutResolver: @Sendable () throws -> W4RequestContext {
        { throw W4Error.sessionExpired }
    }

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let bundled = [
            bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4"),
            bundle.url(forResource: name, withExtension: "html", subdirectory: "W4"),
            bundle.url(forResource: name, withExtension: "html")
        ].compactMap { $0 }.first
        if let bundled {
            return try String(contentsOf: bundled, encoding: .utf8)
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/\(name).html")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: source, encoding: .utf8)
    }

    // MARK: - Builders

    private func documentRepository(
        client: StubW4SecondaryClient,
        context: W4RequestContext
    ) -> DocumentRepository {
        DocumentRepository(client: client, cache: cache, resolveContext: resolver(context))
    }

    private func tripRepository(
        client: StubW4SecondaryClient,
        context: W4RequestContext
    ) -> TripRepository {
        TripRepository(client: client, cache: cache, resolveContext: resolver(context))
    }

    private func travelRepository(
        client: StubW4SecondaryClient,
        context: W4RequestContext
    ) -> TravelRepository {
        TravelRepository(client: client, cache: cache, resolveContext: resolver(context))
    }

    private func gradeRepository(
        client: StubW4SecondaryClient,
        context: W4RequestContext
    ) -> GradeRepository {
        GradeRepository(client: client, cache: cache, resolveContext: resolver(context))
    }

    /// A `fetchedAt` comfortably past a surface's TTL.
    private func expired(for surface: W4Surface) -> Date {
        TimeProvider.now.addingTimeInterval(-(CachePolicy.ttl(for: surface) + 3600))
    }

    // MARK: - Documents: the Done criterion

    /// The stated Done criterion for item 5.8: **navigating into a cached folder issues no
    /// request.** The second `loadFolder` must not reach the stub at all.
    func testCachedFolderIsServedWithoutASecondRequest() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("documents-folder"), forRoute: "documents/index&folder_id=27")
        let repository = documentRepository(client: client, context: signedIn)

        let first = try await repository.loadFolder(id: "27")
        let afterFirst = await client.callCount
        XCTAssertEqual(first.freshness, .fresh)
        XCTAssertEqual(first.value.title, "Internal Information")
        XCTAssertEqual(afterFirst, 1)

        let second = try await repository.loadFolder(id: "27")
        let afterSecond = await client.callCount
        XCTAssertEqual(afterSecond, 1, "a folder inside its TTL must not be refetched")
        XCTAssertEqual(second.value.items.map(\.title), ["Houses", "Bakehus", "Lavvo"])

        guard case .cached(_, let isStale) = second.freshness else {
            return XCTFail("the second load should report itself as cached, got \(second.freshness)")
        }
        XCTAssertFalse(isStale, "a page inside its TTL is cached but not stale")
    }

    /// Each node in the tree gets its own cache entry, so walking root → folder → page and back
    /// costs three requests and never five.
    func testEachNodeIsCachedUnderItsOwnKey() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("documents"), forRoute: W4Routes.R.documents)
        await client.setHTML(try fixture("documents-folder"), forRoute: "documents/index&folder_id=27")
        await client.setHTML(try fixture("documents-page"), forRoute: "documents/index&page_id=870")
        let repository = documentRepository(client: client, context: signedIn)

        _ = try await repository.loadRoot()
        _ = try await repository.loadFolder(id: "27")
        let page = try await repository.loadPage(id: "870")
        let afterWalkDown = await client.callCount
        XCTAssertEqual(afterWalkDown, 3, "three distinct nodes, three requests")
        XCTAssertTrue(page.value.isPage)
        XCTAssertEqual(page.value.title, "Fire Drill Procedure")

        _ = try await repository.loadFolder(id: "27")
        _ = try await repository.loadRoot()
        let afterWalkBack = await client.callCount
        let routes = await client.requestedRoutes
        XCTAssertEqual(afterWalkBack, 3, "navigating back must be served entirely from the cache")
        XCTAssertEqual(
            routes,
            [W4Routes.R.documents, "documents/index&folder_id=27", "documents/index&page_id=870"]
        )
    }

    func testCacheKeyIsCanonicalAndDistinguishesNodes() {
        XCTAssertEqual(
            DocumentRepository.cacheKey(forRoute: "documents/index&folder_id=27"),
            DocumentRepository.cacheKey(forRoute: "documents/index&folder_id=27")
        )
        XCTAssertNotEqual(
            DocumentRepository.cacheKey(forRoute: "documents/index&folder_id=27"),
            DocumentRepository.cacheKey(forRoute: "documents/index&page_id=27"),
            "folder 27 and page 27 are different nodes"
        )
        XCTAssertNotEqual(
            DocumentRepository.cacheKey(forRoute: "documents/index&folder_id=27"),
            DocumentRepository.cacheKey(forRoute: W4Routes.R.documents),
            "a folder must not overwrite the root"
        )
        // Sibling order is not identity: the same node reached through two differently ordered
        // links has to hit one cache entry.
        XCTAssertEqual(
            DocumentRepository.cacheKey(forRoute: "documents/index&folder_id=27&mode=list"),
            DocumentRepository.cacheKey(forRoute: "documents/index&mode=list&folder_id=27")
        )
        XCTAssertNotEqual(
            DocumentRepository.cacheKey(forRoute: "documents/index&folder_id=27"),
            DocumentRepository.cacheKey(forRoute: "extraacademics/documents&folder_id=27"),
            "the two CMS roots are separate trees"
        )
    }

    func testForceRefreshRefetchesAndUpdatesTheCache() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("documents"), forRoute: W4Routes.R.documents)
        let repository = documentRepository(client: client, context: signedIn)

        _ = try await repository.loadRoot()
        let refreshed = try await repository.loadRoot(forceRefresh: true)
        let count = await client.callCount

        XCTAssertEqual(count, 2)
        XCTAssertEqual(refreshed.freshness, .fresh)
    }

    func testExtraAcademicsLibraryUsesItsOwnRoute() async throws {
        let client = StubW4SecondaryClient()
        let repository = documentRepository(client: client, context: signedIn)

        _ = try await repository.loadRoot(library: .extraAcademics)
        let routes = await client.requestedRoutes

        XCTAssertEqual(routes, [W4Routes.R.eaDocuments])
        XCTAssertEqual(
            DocumentLibrary.library(forRoute: "extraacademics/documents&page_id=79"), .extraAcademics
        )
        XCTAssertEqual(DocumentLibrary.library(forRoute: "documents/index&page_id=870"), .school)
    }

    func testFollowingAParsedNodeUsesTheRouteW4Linked() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("documents"), forRoute: W4Routes.R.documents)
        await client.setHTML(try fixture("documents-folder"), forRoute: "documents/index&folder_id=27")
        let repository = documentRepository(client: client, context: signedIn)

        let root = try await repository.loadRoot()
        let node = try XCTUnwrap(root.value.items.first)
        XCTAssertEqual(node.title, "Internal Information")

        let opened = try await repository.load(node: node)
        let lastRoute = await client.requestedRoutes.last

        XCTAssertEqual(opened.value.title, "Internal Information")
        XCTAssertEqual(lastRoute, "documents/index&folder_id=27")
    }

    // MARK: - Documents: cache fallback and error classification

    func testStaleCacheIsReturnedWhenTheFetchFails() async throws {
        let client = StubW4SecondaryClient()
        let repository = documentRepository(client: client, context: signedIn)

        // Seed a copy that is past the `.documents` TTL, then take the network away.
        let ancient = expired(for: .documents)
        await cache.store(
            html: try fixture("documents"),
            surface: .documents,
            key: DocumentRepository.cacheKey(forRoute: W4Routes.R.documents),
            uwcId: signedIn.uwcId,
            fetchedAt: ancient
        )
        await client.setFailure(URLError(.notConnectedToInternet))

        let loaded = try await repository.loadRoot()
        let count = await client.callCount

        XCTAssertEqual(count, 1, "a stale page is refetched — it just falls back when that fails")
        XCTAssertEqual(loaded.value.items.count, 2, "the cached copy is still rendered")
        guard case .cached(let fetchedAt, let isStale) = loaded.freshness else {
            return XCTFail("expected a cached result, got \(loaded.freshness)")
        }
        XCTAssertTrue(isStale, "an out-of-TTL fallback must admit it is stale")
        XCTAssertEqual(fetchedAt.timeIntervalSince1970, ancient.timeIntervalSince1970, accuracy: 1)
    }

    func testFetchFailureWithNoCachedCopyThrows() async throws {
        let client = StubW4SecondaryClient()
        await client.setFailure(URLError(.notConnectedToInternet))
        let repository = documentRepository(client: client, context: signedIn)

        do {
            _ = try await repository.loadRoot()
            XCTFail("with nothing cached there is nothing to fall back to")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }
    }

    /// The rule that protects re-login: a dead session must reach the app even when a perfectly
    /// good cached copy exists.
    func testSessionExpiredIsNeverSwallowedByTheCacheFallback() async throws {
        let client = StubW4SecondaryClient()
        let repository = documentRepository(client: client, context: signedIn)

        await cache.store(
            html: try fixture("documents"),
            surface: .documents,
            key: DocumentRepository.cacheKey(forRoute: W4Routes.R.documents),
            uwcId: signedIn.uwcId,
            fetchedAt: expired(for: .documents)
        )
        await client.setFailure(W4Error.sessionExpired)

        do {
            _ = try await repository.loadRoot()
            XCTFail("sessionExpired must propagate so the app can re-login")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// The mirror-image rule: 403 without "Login Required" means wrong role, not a dead session,
    /// so it is absorbed by the cache fallback like any other failure.
    func testForbiddenIsTreatedAsAnOrdinaryFailureNotADeadSession() async throws {
        let client = StubW4SecondaryClient()
        let repository = documentRepository(client: client, context: signedIn)

        await cache.store(
            html: try fixture("documents"),
            surface: .documents,
            key: DocumentRepository.cacheKey(forRoute: W4Routes.R.documents),
            uwcId: signedIn.uwcId,
            fetchedAt: expired(for: .documents)
        )
        await client.setFailure(W4Error.forbidden)

        let loaded = try await repository.loadRoot()

        XCTAssertEqual(loaded.value.items.count, 2)
        XCTAssertTrue(loaded.freshness.isFromCache)
    }

    func testSignedOutSessionPropagatesAndMakesNoRequest() async throws {
        let client = StubW4SecondaryClient()
        let repository = DocumentRepository(
            client: client,
            cache: cache,
            resolveContext: signedOutResolver
        )

        do {
            _ = try await repository.loadRoot()
            XCTFail("a repository with no session must not silently succeed")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
        let count = await client.callCount
        XCTAssertEqual(count, 0, "the session is resolved before anything touches the network")
    }

    func testCachedListingIsNilWhenNothingIsStored() async throws {
        let client = StubW4SecondaryClient()
        let repository = documentRepository(client: client, context: signedIn)

        let cached = await repository.cachedListing(forRoute: W4Routes.R.documents)
        let count = await client.callCount

        XCTAssertNil(cached)
        XCTAssertEqual(count, 0, "the cache-only path never fetches")
    }

    func testInvalidateForcesTheNextLoadToRefetch() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("documents"), forRoute: W4Routes.R.documents)
        let repository = documentRepository(client: client, context: signedIn)

        _ = try await repository.loadRoot()
        await repository.invalidate(route: W4Routes.R.documents)
        _ = try await repository.loadRoot()
        let count = await client.callCount

        XCTAssertEqual(count, 2)
    }

    // MARK: - Documents: demo

    func testDemoDocumentsNeverTouchTheNetwork() async throws {
        let client = StubW4SecondaryClient()
        // Armed to throw: a missed demo branch fails here rather than passing on a lucky response.
        await client.setFailure(W4Error.notPortedToW4(host: "example.org", context: "demo must not fetch"))
        let repository = documentRepository(client: client, context: demo)

        let root = try await repository.loadRoot()
        let folder = try await repository.loadFolder(id: "27")
        let page = try await repository.loadPage(id: "870")
        let count = await client.callCount

        XCTAssertEqual(count, 0, "demo mode must issue zero requests")
        XCTAssertEqual(root.freshness, .demo)
        XCTAssertEqual(folder.freshness, .demo)
        XCTAssertEqual(page.freshness, .demo)

        XCTAssertEqual(root.value.items.map(\.title), ["Internal Information", "Outdoor Department"])
        XCTAssertEqual(root.value.items.map(\.id), ["27", "34"])
        XCTAssertEqual(root.value.items.map(\.kind), [.folder, .folder])

        XCTAssertEqual(folder.value.items.count, 2, "each demo folder holds two pages")
        XCTAssertEqual(folder.value.items.map(\.kind), [.page, .page])
        XCTAssertEqual(folder.value.parentRoute, W4Routes.R.documents)

        XCTAssertTrue(page.value.isPage)
        XCTAssertEqual(page.value.title, "Fire Drill Procedure")
        XCTAssertFalse(page.value.bodyHTML?.isEmpty ?? true)
    }

    func testDemoDocumentNodesAreFollowable() async throws {
        let client = StubW4SecondaryClient()
        await client.setFailure(W4Error.forbidden)
        let repository = documentRepository(client: client, context: demo)

        let root = try await repository.loadRoot()
        let folderNode = try XCTUnwrap(root.value.items.first)
        let folder = try await repository.load(node: folderNode)
        let pageNode = try XCTUnwrap(folder.value.items.first)
        let page = try await repository.load(node: pageNode)
        let count = await client.callCount

        XCTAssertEqual(folder.value.title, "Internal Information")
        XCTAssertEqual(page.value.page?.title, pageNode.title)
        XCTAssertEqual(count, 0)
    }

    // MARK: - Trips

    func testTripsAreFetchedOnceThenServedFromCache() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("trips"), forRoute: W4Routes.R.trips)
        let repository = tripRepository(client: client, context: signedIn)

        let first = try await repository.loadTrips()
        XCTAssertEqual(first.freshness, .fresh)
        XCTAssertEqual(first.value.trips.count, 1)
        XCTAssertEqual(first.value.trips.first?.name, "Bergen weekend")
        XCTAssertEqual(first.value.trips.first?.status, .planning)

        _ = try await repository.loadTrips()
        let count = await client.callCount
        let routes = await client.requestedRoutes
        XCTAssertEqual(count, 1, "the trip grid is cached for its TTL")
        XCTAssertEqual(routes, [W4Routes.R.trips])
    }

    func testTripsRespectTheRequestedPriority() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("trips"), forRoute: W4Routes.R.trips)
        let repository = tripRepository(client: client, context: signedIn)

        _ = try await repository.loadTrips(priority: .opportunistic)
        let priorities = await client.requestedPriorities

        XCTAssertEqual(priorities, [.opportunistic])
    }

    func testTripsInvalidateDropsTheCachedGrid() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("trips"), forRoute: W4Routes.R.trips)
        let repository = tripRepository(client: client, context: signedIn)

        _ = try await repository.loadTrips()
        await repository.invalidate()
        _ = try await repository.loadTrips()
        let count = await client.callCount

        XCTAssertEqual(count, 2)
    }

    func testCachedTripsReadTheStoreWithoutFetching() async throws {
        let client = StubW4SecondaryClient()
        let repository = tripRepository(client: client, context: signedIn)

        let empty = await repository.cachedTrips()
        XCTAssertNil(empty)

        await cache.store(
            html: try fixture("trips"),
            surface: .trips,
            key: TripRepository.tripsCacheKey,
            uwcId: signedIn.uwcId,
            fetchedAt: TimeProvider.now
        )

        let warm = await repository.cachedTrips()
        let count = await client.callCount
        XCTAssertEqual(warm?.value.trips.first?.name, "Bergen weekend")
        XCTAssertEqual(count, 0)
    }

    func testDemoTripIsTheBergenWeekendAndMakesNoRequest() async throws {
        let client = StubW4SecondaryClient()
        await client.setFailure(W4Error.notPortedToW4(host: "example.org", context: "demo must not fetch"))
        let repository = tripRepository(client: client, context: demo)

        let loaded = try await repository.loadTrips()
        let count = await client.callCount

        XCTAssertEqual(count, 0)
        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertEqual(loaded.value.trips.count, 1)

        let trip = try XCTUnwrap(loaded.value.trips.first)
        XCTAssertEqual(trip.name, "Bergen weekend")
        XCTAssertEqual(trip.destination, "Bergen")
        XCTAssertEqual(trip.status, .planning)
        XCTAssertEqual(trip.statusDisplay, "Planning")
        XCTAssertTrue(loaded.value.canPlanNewTrip)

        // A weekend, in the future, with both ends parsed — the label and the Date must agree.
        let outgoing = try XCTUnwrap(trip.outgoing)
        let returning = try XCTUnwrap(trip.returning)
        XCTAssertLessThan(outgoing, returning)
        XCTAssertTrue(trip.isMultiDay, "a weekend trip spans two Oslo days")
        XCTAssertEqual(trip.outgoingLabel, W4Dates.formatDateTime(outgoing))
        XCTAssertEqual(
            W4Dates.calendar.component(.weekday, from: outgoing), 7,
            "the demo trip leaves on a Saturday"
        )
        XCTAssertGreaterThanOrEqual(
            outgoing, W4Dates.startOfDay(TimeProvider.now),
            "demo data must never look like it happened last year"
        )
    }

    // MARK: - Travel

    func testTravelFormsAreFetchedOnceThenServedFromCache() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(Self.travelFormsHTML, forRoute: W4Routes.R.travel)
        let repository = travelRepository(client: client, context: signedIn)

        let first = try await repository.loadTravelForms()
        XCTAssertEqual(first.freshness, .fresh)
        XCTAssertEqual(first.value.forms.count, 4)
        XCTAssertTrue(first.value.hasContactsLink)

        _ = try await repository.loadTravelForms()
        let count = await client.callCount
        let routes = await client.requestedRoutes
        XCTAssertEqual(count, 1)
        XCTAssertEqual(routes, [W4Routes.R.travel])
    }

    func testTravelContactsAreCachedSeparatelyFromTheFormsPage() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(Self.travelFormsHTML, forRoute: W4Routes.R.travel)
        await client.setHTML(Self.travelContactsHTML, forRoute: Self.contactsRoute)
        let repository = travelRepository(client: client, context: signedIn)

        let bundle = try await repository.loadTravelFormsWithContacts()
        let afterFirst = await client.callCount
        XCTAssertEqual(bundle.forms.value.forms.count, 4)
        let contacts = try XCTUnwrap(bundle.contacts)
        XCTAssertEqual(contacts.value.map(\.name), ["Maria Lindqvist", "Tomas Lindqvist"])
        XCTAssertEqual(afterFirst, 2, "the forms page and the contacts page are two pages")

        _ = try await repository.loadTravelFormsWithContacts()
        let afterSecond = await client.callCount
        XCTAssertEqual(afterSecond, 2, "both pages are inside their TTL")

        XCTAssertNotEqual(
            TravelRepository.contactsCacheKey(forRoute: Self.contactsRoute),
            TravelRepository.contactsCacheKey(forRoute: W4Routes.R.travel)
        )
    }

    /// The contacts fetch is a nicety hanging off the forms page. Failing it must not take the
    /// forms list — the thing the student actually asked for — down with it.
    func testAContactsFailureDoesNotFailTheFormsList() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(Self.travelFormsHTML, forRoute: W4Routes.R.travel)
        let repository = travelRepository(client: client, context: signedIn)

        // Warm the forms page, then take the network away for the contacts hop.
        _ = try await repository.loadTravelForms()
        await client.setFailure(URLError(.timedOut))

        let bundle = try await repository.loadTravelFormsWithContacts()

        XCTAssertEqual(bundle.forms.value.forms.count, 4)
        XCTAssertNil(bundle.contacts, "no contacts is a shrug, not an error")
    }

    /// A dead session on the contacts hop still has to reach the app — the "don't fail the forms
    /// list" rule above must not become a way to hide a logout.
    func testASessionExpiryOnTheContactsHopStillPropagates() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(Self.travelFormsHTML, forRoute: W4Routes.R.travel)
        let repository = travelRepository(client: client, context: signedIn)

        _ = try await repository.loadTravelForms()
        await client.setFailure(W4Error.sessionExpired)

        do {
            _ = try await repository.loadTravelFormsWithContacts()
            XCTFail("a dead session must not be hidden behind an optional contacts list")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    func testContactsIsOpportunisticWhileTheFormsListIsImportant() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(Self.travelFormsHTML, forRoute: W4Routes.R.travel)
        await client.setHTML(Self.travelContactsHTML, forRoute: Self.contactsRoute)
        let repository = travelRepository(client: client, context: signedIn)

        _ = try await repository.loadTravelFormsWithContacts()
        let priorities = await client.requestedPriorities

        XCTAssertEqual(priorities, [.important, .opportunistic])
    }

    func testContactsWithAnEmptyRouteIsRejectedBeforeAnyRequest() async throws {
        let client = StubW4SecondaryClient()
        let repository = travelRepository(client: client, context: signedIn)

        do {
            _ = try await repository.loadContacts(route: "   ")
            XCTFail("an empty route is not a page")
        } catch let error as W4Error {
            guard case .invalidURL = error else {
                return XCTFail("expected .invalidURL, got \(error)")
            }
        }
        let count = await client.callCount
        XCTAssertEqual(count, 0)
    }

    func testDemoTravelHasFourJourneysAndMakesNoRequest() async throws {
        let client = StubW4SecondaryClient()
        await client.setFailure(W4Error.notPortedToW4(host: "example.org", context: "demo must not fetch"))
        let repository = travelRepository(client: client, context: demo)

        let bundle = try await repository.loadTravelFormsWithContacts()
        let count = await client.callCount

        XCTAssertEqual(count, 0)
        XCTAssertEqual(bundle.forms.freshness, .demo)
        XCTAssertEqual(bundle.forms.value.forms.count, 4)
        XCTAssertTrue(
            bundle.forms.value.missingJourneys.isEmpty,
            "demo must render all four fixed journeys"
        )
        XCTAssertEqual(
            bundle.forms.value.sortedForms.map(\.journey),
            [.toSchoolAutumn, .homeWinter, .backAfterWinter, .homeSummer]
        )
        XCTAssertEqual(
            bundle.forms.value.sortedForms.map(\.statusLabel),
            ["Submitted", "Not started", "Not started", "Not started"]
        )
        XCTAssertFalse(
            bundle.forms.value.hasContactsLink,
            "demo exposes no href, so nothing can open an in-app browser"
        )
        XCTAssertEqual(bundle.contacts?.value.count, 2)
        XCTAssertEqual(bundle.contacts?.freshness, .demo)
    }

    // MARK: - Grades

    func testGradesAreFetchedOnceThenServedFromCache() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("grades"), forRoute: W4Routes.R.grades)
        let repository = gradeRepository(client: client, context: signedIn)

        let first = try await repository.loadReport()
        XCTAssertEqual(first.freshness, .fresh)
        XCTAssertEqual(first.value.title, "My Grades")
        XCTAssertEqual(first.value.rows.count, 3)
        XCTAssertNotNil(first.value.fetchedAt, "the repository stamps the report; the parser must not")

        _ = try await repository.loadReport()
        let count = await client.callCount
        XCTAssertEqual(count, 1)
    }

    /// The two grades pages share the `.grades` surface, so a shared cache key would make one
    /// overwrite the other. They must not.
    func testGradesAndSATUseSeparateCacheEntries() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("grades"), forRoute: W4Routes.R.grades)
        let repository = gradeRepository(client: client, context: signedIn)

        _ = try await repository.loadReport(.academic)
        _ = try await repository.loadReport(.satACT)
        let afterFirst = await client.callCount
        let routes = await client.requestedRoutes
        XCTAssertEqual(afterFirst, 2)
        XCTAssertEqual(routes, [W4Routes.R.grades, W4Routes.R.satACT])

        // And neither evicted the other.
        _ = try await repository.loadReport(.academic)
        _ = try await repository.loadReport(.satACT)
        let afterSecond = await client.callCount
        XCTAssertEqual(afterSecond, 2)

        XCTAssertNotEqual(GradeReportKind.academic.cacheKey, GradeReportKind.satACT.cacheKey)
    }

    /// After a relaunch the report must carry the moment W4 produced it, not the moment the app
    /// read the file — otherwise "Updated just now" is a lie on top of a week-old cache.
    func testACachedReportIsStampedWithTheCacheTimestamp() async throws {
        let client = StubW4SecondaryClient()
        let repository = gradeRepository(client: client, context: signedIn)

        let stored = TimeProvider.now.addingTimeInterval(-600)
        await cache.store(
            html: try fixture("grades"),
            surface: .grades,
            key: GradeReportKind.academic.cacheKey,
            uwcId: signedIn.uwcId,
            fetchedAt: stored
        )

        let loaded = try await repository.loadReport()
        let count = await client.callCount

        XCTAssertEqual(count, 0, "a cached report inside its TTL is not refetched")
        let fetchedAt = try XCTUnwrap(loaded.value.fetchedAt)
        XCTAssertEqual(fetchedAt.timeIntervalSince1970, stored.timeIntervalSince1970, accuracy: 1)
    }

    func testGradesInvalidateAllDropsBothPages() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("grades"), forRoute: W4Routes.R.grades)
        let repository = gradeRepository(client: client, context: signedIn)

        _ = try await repository.loadReport(.academic)
        _ = try await repository.loadReport(.satACT)
        await repository.invalidateAll()
        _ = try await repository.loadReport(.academic)
        _ = try await repository.loadReport(.satACT)
        let count = await client.callCount

        XCTAssertEqual(count, 4)
    }

    func testDemoGradesAreIBAndMakeNoRequest() async throws {
        let client = StubW4SecondaryClient()
        await client.setFailure(W4Error.notPortedToW4(host: "example.org", context: "demo must not fetch"))
        let repository = gradeRepository(client: client, context: demo)

        let loaded = try await repository.loadReport()
        let count = await client.callCount

        XCTAssertEqual(count, 0)
        XCTAssertEqual(loaded.freshness, .demo)

        let report = loaded.value
        XCTAssertEqual(report.columns.map(\.id), ["predicted", "final"])
        XCTAssertEqual(report.columns.map(\.label), ["Predicted", "Final"])
        XCTAssertEqual(report.anticipatedColumns.map(\.id), ["predicted"])
        XCTAssertEqual(report.defaultColumnID, "final")
        XCTAssertEqual(report.rows.count, 4)
        XCTAssertEqual(report.rows.map(\.level), ["HL", "HL", "SL", "HL"])

        // Every demo grade is a real IB grade, so the progress bars are drawable.
        for row in report.rows {
            let final = try XCTUnwrap(row.cell(for: "final"))
            let grade = try XCTUnwrap(final.ibGrade, "\(row.subject) should carry an IB 1–7 grade")
            XCTAssertTrue((1...7).contains(grade))
            XCTAssertNotNil(final.effort, "D-14: W4 has effort grades where Lectio had weights")
        }
        let average = try XCTUnwrap(report.average(forColumnID: "final"))
        XCTAssertEqual(average, 23.0 / 4.0, accuracy: 0.0001)
    }

    func testDemoSATIsHonestlyEmpty() async throws {
        let client = StubW4SecondaryClient()
        await client.setFailure(W4Error.forbidden)
        let repository = gradeRepository(client: client, context: demo)

        let loaded = try await repository.loadReport(.satACT)
        let count = await client.callCount

        XCTAssertEqual(count, 0)
        XCTAssertTrue(loaded.value.isEmpty)
        XCTAssertNotNil(loaded.value.emptyMessage, "an empty page still says why it is empty")
    }

    // MARK: - Cross-cutting

    /// TTLs belong to `CachePolicy` alone; a repository that hard-coded one would drift from the
    /// table in features.md §2.5 the first time that table changed.
    func testEverySurfaceUsedHereHasAFiniteTTL() {
        for surface in [W4Surface.documents, .trips, .travel, .grades] {
            let ttl = CachePolicy.ttl(for: surface)
            XCTAssertGreaterThan(ttl, 0, "\(surface.rawValue) needs a positive TTL")
            XCTAssertTrue(ttl.isFinite, "\(surface.rawValue) must actually expire")
        }
    }

    /// The page cache is scoped per uwc id. Two students on one device must never see each
    /// other's documents.
    func testCacheIsScopedPerStudent() async throws {
        let client = StubW4SecondaryClient()
        await client.setHTML(try fixture("documents"), forRoute: W4Routes.R.documents)

        let mine = documentRepository(client: client, context: signedIn)
        _ = try await mine.loadRoot()
        let afterMine = await client.callCount
        XCTAssertEqual(afterMine, 1)

        let otherStudent = Student(
            studentId: "nc27wxyz",
            name: "Other Student",
            pictureId: nil,
            classLabel: nil
        )
        let theirs = DocumentRepository(
            client: client,
            cache: cache,
            resolveContext: resolver(
                W4RequestContext(student: otherStudent, credentials: W4Credentials(sessionId: "other"))
            )
        )
        _ = try await theirs.loadRoot()
        let afterTheirs = await client.callCount

        XCTAssertEqual(afterTheirs, 2, "another student's cached page must never be reused")
    }

    // MARK: - Synthesized travel markup

    /// The route the synthesized forms page links its contacts page at. Invented, like the page.
    private static let contactsRoute = "academics/travel/travel.contacts"

    /// [I] SYNTHESIZED. `academics/travel/travel.list` has never been captured; this is the Yii 1
    /// grid convention (parsers.md §0.4) plus the four journeys README §6 describes in prose. It
    /// exercises the repository, and proves nothing whatsoever about W4.
    private static let travelFormsHTML = """
        <!DOCTYPE html>
        <html lang="en"><head><title>My travel forms - UWCRCN W4</title></head>
        <body><div id="content"><div id="content_inner">
          <h2>My travel forms</h2>
          <div class="grid-view"><table class="items">
            <thead><tr><th>Journey</th><th>Status</th></tr></thead>
            <tbody>
              <tr><td><a href="/index.php?r=academics/travel/travel.form&amp;id=1">To school in autumn</a></td><td>Submitted</td></tr>
              <tr><td><a href="/index.php?r=academics/travel/travel.form&amp;id=2">Home for winter</a></td><td>Not started</td></tr>
              <tr><td><a href="/index.php?r=academics/travel/travel.form&amp;id=3">Back to school after winter</a></td><td>Not started</td></tr>
              <tr><td><a href="/index.php?r=academics/travel/travel.form&amp;id=4">Home for summer</a></td><td>Not started</td></tr>
            </tbody>
          </table></div>
          <a href="/index.php?r=academics/travel/travel.contacts">Manage my travel contacts</a>
        </div></div></body></html>
        """

    /// [I] SYNTHESIZED, for the same reason and with the same standing.
    private static let travelContactsHTML = """
        <!DOCTYPE html>
        <html lang="en"><head><title>My travel contacts - UWCRCN W4</title></head>
        <body><div id="content"><div id="content_inner">
          <h2>My travel contacts</h2>
          <div class="grid-view"><table class="items">
            <thead><tr><th>Name</th><th>Relation</th><th>Phone</th><th>Email</th></tr></thead>
            <tbody>
              <tr><td>Maria Lindqvist</td><td>Mother</td><td>+47 55 00 11 22</td><td>maria.lindqvist@example.org</td></tr>
              <tr><td>Tomas Lindqvist</td><td>Father</td><td>+47 55 00 33 44</td><td>tomas.lindqvist@example.org</td></tr>
            </tbody>
          </table></div>
        </div></div></body></html>
        """
}
