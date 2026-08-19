//
//  W4SurfaceViewModelTests.swift
//  BetterW4Tests
//
//  Wave 6, vertical 6 — the view models behind the W4-only surfaces: Home, campus status, the
//  notification bell, the Documents CMS, trips/travel and Extra Academics.
//
//  WHAT THESE TESTS ARE FOR. The parsers and the repositories have their own suites; this file
//  asserts the *view model* contract, which is where a screen quietly stops behaving:
//
//    1. a demo session renders real demo content and makes **zero** requests — every demo case runs
//       against a stub armed to throw, so a missed demo branch fails loudly;
//    2. a failed refresh never blanks what is already on screen, and the error surfaces only when
//       the screen would otherwise be empty (features.md §3 rules 3 and 4);
//    3. `W4Error.sessionExpired` reaches the app (it is the one error that logs the user out) and
//       `W4Error.forbidden` never does — a student opening a staff-only page must stay signed in;
//    4. the campus write posts W4's own option **value**, never its label; "On campus" posts no
//       location key at all; "Other" is capped at twenty characters and refused when empty
//       (plan D-12, bug B6 — the two rules that break two of the eleven options when got wrong).
//
//  NO TEST HERE TOUCHES THE NETWORK, THE KEYCHAIN OR THE SHARED PAGE CACHE. Every repository is
//  built with a stub transport, an injected session and a page cache rooted in a temporary
//  directory.
//

import XCTest
@testable import BetterW4

// MARK: - Stub transports

/// `W4RouteFetching` — the seam `HomeRepository` and `ExtraAcademicsRepository` fetch through.
private actor SurfaceRouteStub: W4RouteFetching {

    struct Unexpected: Error { let route: String }

    private(set) var routes: [String] = []
    private var htmlByRoute: [String: String] = [:]
    private var failure: Error?

    func setHTML(_ html: String, forRoute route: String) {
        htmlByRoute[route] = html
    }

    /// Arms every request to fail. `nil` disarms.
    func setFailure(_ error: Error?) {
        failure = error
    }

    var callCount: Int { routes.count }

    func fetchRoute(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4RouteResponse {
        routes.append(route)
        if let failure { throw failure }
        guard let html = htmlByRoute[route] else { throw Unexpected(route: route) }
        return W4RouteResponse(html: html, finalURL: W4Routes.url(route), contentType: "text/html")
    }
}

/// `W4SecondaryFetching` — documents, trips and travel.
private actor SurfaceSecondaryStub: W4SecondaryFetching {

    struct Unexpected: Error { let route: String }

    private(set) var routes: [String] = []
    private var htmlByRoute: [String: String] = [:]
    private var failureByRoute: [String: Error] = [:]
    private var failure: Error?

    func setHTML(_ html: String, forRoute route: String) {
        htmlByRoute[route] = html
    }

    func setFailure(_ error: Error?, forRoute route: String) {
        failureByRoute[route] = error
    }

    func setFailure(_ error: Error?) {
        failure = error
    }

    var callCount: Int { routes.count }

    func fetchSecondaryPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4SecondaryPage {
        routes.append(route)
        if let failure { throw failure }
        if let routeFailure = failureByRoute[route] { throw routeFailure }
        guard let html = htmlByRoute[route] else { throw Unexpected(route: route) }
        return W4SecondaryPage(html: html, finalURL: W4Routes.url(route), contentType: "text/html")
    }
}

/// `W4ChromeTransport` — the campus chip and the bell. Records every posted body, because the body
/// *is* the contract for `site/setstatus`.
private actor SurfaceChromeStub: W4ChromeTransport {

    struct Post: Equatable {
        let route: String
        let fields: [String: String]
    }

    struct Unexpected: Error { let route: String }

    private(set) var posts: [Post] = []
    private(set) var pageRoutes: [String] = []
    private var pageHTML: String?
    private var postHTML: String = ""
    private var failure: Error?

    func setPageHTML(_ html: String?) { pageHTML = html }
    func setPostHTML(_ html: String) { postHTML = html }
    func setFailure(_ error: Error?) { failure = error }

    var callCount: Int { posts.count + pageRoutes.count }
    var lastPost: Post? { posts.last }

    func fetchPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse {
        pageRoutes.append(route)
        if let failure { throw failure }
        guard let pageHTML else { throw Unexpected(route: route) }
        return ChromePageResponse(html: pageHTML, finalURL: W4Routes.url(route))
    }

    func postAjax(
        route: String,
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse {
        posts.append(Post(route: route, fields: fields))
        if let failure { throw failure }
        return ChromePageResponse(html: postHTML, finalURL: W4Routes.url(route))
    }
}

// MARK: - Tests

@MainActor
final class W4SurfaceViewModelTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("W4SurfaceViewModelTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Sessions

    private static let student = Student(
        studentId: "nc26abcd",
        name: "Alex Andersen",
        pictureId: nil,
        classLabel: nil
    )

    private var signedIn: W4RequestContext {
        W4RequestContext(
            student: Self.student,
            credentials: W4Credentials(sessionId: "phpsessid-for-tests")
        )
    }

    private var demo: W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func resolver(_ context: W4RequestContext) -> @Sendable () throws -> W4RequestContext {
        { context }
    }

    // MARK: Fixtures

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

    // MARK: - Home

    func testHomeDemoRendersWithoutTouchingTheNetwork() async throws {
        let stub = SurfaceRouteStub()
        // Armed to fail: a missed demo branch must break this test, not pass by luck.
        await stub.setFailure(W4Error.noResponse)
        let repository = HomeRepository(client: stub, cache: cache, context: resolver(demo))
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load(student: .demo)

        XCTAssertEqual(viewModel.greeting, "Hello, Demo Student")
        XCTAssertTrue(viewModel.isDemo)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.meters.academic?.absences, 1)
        XCTAssertEqual(viewModel.meters.extraAcademic?.latenesses, 0)
        XCTAssertEqual(viewModel.announcementsEmptyText, "No announcements...")
        XCTAssertFalse(viewModel.links.isEmpty)
        let calls = await stub.callCount
        XCTAssertEqual(calls, 0, "a demo session must never reach the network")
    }

    func testHomeRendersTheRealCapture() async throws {
        let html = try fixture("home")
        let stub = SurfaceRouteStub()
        await stub.setHTML(html, forRoute: W4Routes.R.home)
        let repository = HomeRepository(client: stub, cache: cache, context: resolver(signedIn))
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load(student: Self.student)

        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.greeting, "Hello, Alex Andersen")
        XCTAssertEqual(viewModel.uwcId, "nc26abcd")
        // The capture's `#links` block: ten entries, configuration rather than code.
        XCTAssertEqual(viewModel.links.count, 10)
        XCTAssertEqual(viewModel.announcementsEmptyText, "No announcements...")
        XCTAssertEqual(viewModel.birthdaysToday.map(\.uwcId), ["nc16efgh", "nc19ijkl", "nc25mnop"])
        XCTAssertFalse(viewModel.isLoading)
    }

    func testHomeKeepsCachedContentWhenTheRefreshFails() async throws {
        let html = try fixture("home")
        let stub = SurfaceRouteStub()
        await stub.setHTML(html, forRoute: W4Routes.R.home)
        let repository = HomeRepository(client: stub, cache: cache, context: resolver(signedIn))
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load(student: Self.student)
        XCTAssertNotNil(viewModel.snapshot)

        // Everything now fails. The screen must not blank, and must not shout.
        await stub.setFailure(W4Error.httpError(status: 500, route: W4Routes.R.home))
        await viewModel.refresh(student: Self.student)

        XCTAssertNotNil(viewModel.snapshot, "a failed refresh must never wipe cached content")
        XCTAssertNil(viewModel.errorMessage, "offline with a warm cache is a working app")
        XCTAssertTrue(viewModel.freshness?.isFromCache ?? false)
    }

    func testHomeShowsAnErrorOnlyWhenThereIsNothingToShow() async throws {
        let stub = SurfaceRouteStub()
        await stub.setFailure(W4Error.httpError(status: 500, route: W4Routes.R.home))
        let repository = HomeRepository(client: stub, cache: cache, context: resolver(signedIn))
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load(student: Self.student)

        XCTAssertNil(viewModel.snapshot)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testHomeSessionExpiryReachesTheApp() async throws {
        let expectation = XCTNSNotificationExpectation(name: .w4SessionExpired)
        let stub = SurfaceRouteStub()
        await stub.setFailure(W4Error.sessionExpired)
        let repository = HomeRepository(client: stub, cache: cache, context: resolver(signedIn))
        let viewModel = HomeViewModel(repository: repository)

        await viewModel.load(student: Self.student)

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testHomeLinksRouteInternallyAndExternally() async throws {
        let viewModel = HomeViewModel(
            repository: HomeRepository(client: SurfaceRouteStub(), cache: cache, context: resolver(demo))
        )

        let cms = HomeLink(
            title: "Bakehus",
            url: W4Routes.url("documents/index", ["page_id": "870"]),
            route: "documents/index&page_id=870"
        )
        let eaCMS = HomeLink(
            title: "Haugland times",
            url: W4Routes.url("extraacademics/documents/index", ["page_id": "79"]),
            route: "extraacademics/documents/index&page_id=79"
        )
        let trips = HomeLink(
            title: "Trip Form",
            url: W4Routes.url(W4Routes.R.trips),
            route: W4Routes.R.trips
        )
        let profile = HomeLink(
            title: "My profile",
            url: W4Routes.url(W4Routes.R.profile),
            route: W4Routes.R.profile
        )
        let manageBac = HomeLink(
            title: "ManageBac",
            url: URL(string: "https://uwcrcn.managebac.com/")!,
            route: nil
        )

        XCTAssertEqual(
            viewModel.destination(for: cms),
            .documents(library: .school, route: "documents/index&page_id=870")
        )
        XCTAssertEqual(
            viewModel.destination(for: eaCMS),
            .documents(library: .extraAcademics, route: "extraacademics/documents/index&page_id=79")
        )
        XCTAssertEqual(viewModel.destination(for: trips), .trips)
        XCTAssertEqual(viewModel.destination(for: profile), .w4Page(profile.url))
        XCTAssertEqual(viewModel.destination(for: manageBac), .external(manageBac.url))
    }

    // MARK: - Campus status

    private func campusRepository(
        _ stub: SurfaceChromeStub,
        context: W4RequestContext
    ) -> CampusStatusRepository {
        // `broadcast: nil` keeps the shared `ChromeObserver` (and the real notification
        // repository behind it) out of these tests entirely.
        CampusStatusRepository(
            client: stub,
            cache: cache,
            resolveContext: resolver(context),
            broadcast: nil
        )
    }

    func testOnCampusPostsStatusOnAndNoLocationKey() async throws {
        let stub = SurfaceChromeStub()
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        let option = try XCTUnwrap(CampusStatus.defaultOptions.first { $0.isOnCampus })
        await viewModel.setStatus(option)

        let post = await stub.lastPost
        XCTAssertEqual(post?.route, W4Routes.R.setStatus)
        XCTAssertEqual(post?.fields, ["status": "on"])
        XCTAssertNil(post?.fields["location"], "on campus must post no location key at all")
        XCTAssertTrue(viewModel.isOnCampus)
    }

    func testAnOptionPostsItsValueNeverItsLabel() async throws {
        let stub = SurfaceChromeStub()
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        // A label that differs from the POST value is exactly the case bug B6 gets wrong.
        let option = CampusLocationOption(id: "location_2", value: "At Raudbua", label: "Raudbua hut")
        await viewModel.setStatus(option)

        let post = await stub.lastPost
        XCTAssertEqual(post?.fields, ["status": "off", "location": "At Raudbua"])
        XCTAssertFalse(viewModel.isOnCampus)
        XCTAssertEqual(viewModel.status?.location, "At Raudbua")
    }

    func testOtherPostsTheFreeTextCappedAtTwentyCharacters() async throws {
        let stub = SurfaceChromeStub()
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        viewModel.freeText = "In the boathouse down by the fjord"
        XCTAssertEqual(
            viewModel.freeText.count,
            CampusStatus.freeTextMaxLength,
            "the field enforces input#other[maxlength=20]"
        )

        let option = try XCTUnwrap(CampusStatus.defaultOptions.first { $0.isFreeText })
        await viewModel.setStatus(option)

        let post = await stub.lastPost
        XCTAssertEqual(post?.fields["status"], "off")
        XCTAssertEqual(post?.fields["location"]?.count, CampusStatus.freeTextMaxLength)
        // "In the boathouse down by the fjord" clipped to W4's input#other[maxlength=20].
        // The first 20 characters land mid-word, which is what a browser would post too.
        XCTAssertEqual(post?.fields["location"], "In the boathouse dow")
    }

    func testOtherWithNoTextIsRefusedBeforeAnythingIsPosted() async throws {
        let stub = SurfaceChromeStub()
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        viewModel.freeText = "   "
        let option = try XCTUnwrap(CampusStatus.defaultOptions.first { $0.isFreeText })
        await viewModel.setStatus(option)

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0, "an empty location must never be posted")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testAFailedWriteRevertsTheChip() async throws {
        let stub = SurfaceChromeStub()
        await stub.setFailure(W4Error.httpError(status: 500, route: W4Routes.R.setStatus))
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        let option = CampusLocationOption(id: "location_6", value: "In Dale", label: "In Dale")
        await viewModel.setStatus(option)

        XCTAssertNil(viewModel.status, "an optimistic chip must be rolled back when W4 refuses")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testTheServersAnswerWinsOverOurProjection() async throws {
        let stub = SurfaceChromeStub()
        // W4 usually answers a `$.post` with an empty body, but when it does echo the widget the
        // server is right and the projection is a guess.
        await stub.setPostHTML("""
        <div class="status-dropdown">
          <div class="status offcampus">
            <div class="status-value">off campus</div>
            <div class="location">(On a walk)</div>
          </div>
        </div>
        """)
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        await viewModel.setStatus(
            CampusLocationOption(id: "location_6", value: "In Dale", label: "In Dale")
        )

        XCTAssertEqual(viewModel.status?.location, "On a walk")
        XCTAssertFalse(viewModel.isOnCampus)
    }

    func testAFailedCampusReadNeverInterruptsAnybody() async throws {
        let stub = SurfaceChromeStub()
        await stub.setFailure(W4Error.httpError(status: 500, route: W4Routes.R.home))
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: signedIn))

        await viewModel.load()

        // A chip in a toolbar has no error surface: it stays quiet and shows what it last knew.
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.status)
        XCTAssertEqual(viewModel.label, "Campus status")
    }

    func testCampusDemoWritesNeverReachTheNetwork() async throws {
        let stub = SurfaceChromeStub()
        await stub.setFailure(W4Error.noResponse)
        let viewModel = CampusStatusViewModel(repository: campusRepository(stub, context: demo))

        let option = CampusLocationOption(id: "location_5", value: "In Flekke", label: "In Flekke")
        await viewModel.setStatus(option)

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(viewModel.status?.location, "In Flekke")
        XCTAssertTrue(viewModel.isDemo)
        XCTAssertEqual(viewModel.options.count, 11, "all eleven captured options stay selectable")
    }

    // MARK: - Notifications

    func testNotificationsDemoHasRowsAndMarkAllReadClearsTheBadge() async throws {
        let stub = SurfaceChromeStub()
        await stub.setFailure(W4Error.noResponse)
        let repository = NotificationRepository(
            client: stub,
            cache: cache,
            resolveContext: resolver(demo)
        )
        let viewModel = NotificationsViewModel(repository: repository)

        await viewModel.refresh()
        XCTAssertTrue(viewModel.hasUnread)
        XCTAssertFalse(viewModel.taskGroups.isEmpty)
        if MailFeatureFlags.visible {
            XCTAssertFalse(viewModel.emailGroups.isEmpty)
        } else {
            XCTAssertTrue(viewModel.emailGroups.isEmpty)
        }

        await viewModel.markAllRead()
        XCTAssertEqual(viewModel.unreadCount, 0)

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0, "a demo session must never post a notification action")
    }

    func testAnEmptyBellIsASuccessNotAnError() async throws {
        let stub = SurfaceChromeStub()
        // Bug B8: this school's real chrome ships an empty `div.notifications`.
        await stub.setPostHTML("<div><div class=\"notifications\"></div></div>")
        let repository = NotificationRepository(
            client: stub,
            cache: cache,
            resolveContext: resolver(signedIn)
        )
        let viewModel = NotificationsViewModel(repository: repository)

        await viewModel.refresh()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertEqual(viewModel.unreadCount, 0)
        XCTAssertNil(viewModel.errorMessage, "zero notifications is the normal state at this school")
    }

    func testAFailedBellReadIsReportedInlineRatherThanAsAFailedWrite() async throws {
        let stub = SurfaceChromeStub()
        await stub.setFailure(W4Error.httpError(status: 500, route: W4Routes.R.notificationsRefresh))
        let repository = NotificationRepository(
            client: stub,
            cache: cache,
            resolveContext: resolver(signedIn)
        )
        let viewModel = NotificationsViewModel(repository: repository)

        await viewModel.refresh()

        // The alert is reserved for writes that silently did not happen.
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.loadErrorMessage)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testTheAnsweringFragmentBecomesTheSnapshot() async throws {
        let stub = SurfaceChromeStub()
        // [I] The wrapper shape `notifications.js:65` swaps in — the same synthesized fragment the
        // chrome repository suite uses, because no populated bell has ever been captured.
        await stub.setPostHTML("""
        <div><div class="btn-group">
          <div class="alert new">1</div>
          <div class="dropdown-menu">
            <h3 class="tasks">Tasks</h3>
            <dl>
              <dt class="new">Assessments<a class="read" data-notification-type="assessment">read</a></dt>
              <dd><ul>
                <li class="new"><a href="/index.php?r=academics/deadlines&amp;id=13">History essay</a>
                <a class="read" data-notification-id="13">read</a></li>
              </ul></dd>
            </dl>
          </div>
        </div></div>
        """)
        let repository = NotificationRepository(
            client: stub,
            cache: cache,
            resolveContext: resolver(signedIn)
        )
        let viewModel = NotificationsViewModel(repository: repository)

        await viewModel.refresh()

        // Whatever the fragment says is now the snapshot — we never assume a write did what we asked.
        XCTAssertEqual(viewModel.unreadCount, 1)
        XCTAssertEqual(viewModel.snapshot.items.map(\.id), ["13"])
        XCTAssertFalse(viewModel.isEmpty)

        let posts = await stub.posts
        XCTAssertEqual(posts.first?.route, W4Routes.R.notificationsRefresh)
    }

    // MARK: - Documents

    func testDocumentsDemoWalksTheTree() async throws {
        let stub = SurfaceSecondaryStub()
        await stub.setFailure(W4Error.noResponse)
        let repository = DocumentRepository(client: stub, cache: cache, resolveContext: resolver(demo))

        let root = DocumentsViewModel(route: nil, repository: repository)
        await root.load()
        XCTAssertEqual(root.folders.count, 2)
        XCTAssertTrue(root.pages.isEmpty)
        XCTAssertFalse(root.isPage)

        let folderRoute = try XCTUnwrap(root.folders.first?.route)
        let folder = DocumentsViewModel(route: folderRoute, repository: repository)
        await folder.load()
        XCTAssertEqual(folder.pages.count, 2)
        XCTAssertNotNil(folder.parentRoute)
        XCTAssertNotNil(folder.breadcrumbText)

        let pageRoute = try XCTUnwrap(folder.pages.first?.route)
        let leaf = DocumentsViewModel(route: pageRoute, repository: repository)
        await leaf.load()
        XCTAssertTrue(leaf.isPage)
        XCTAssertFalse(leaf.contentBlocks.isEmpty, "a leaf page renders its TinyMCE body")
        XCTAssertEqual(leaf.title, "Fire Drill Procedure")

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0)
    }

    func testDocumentsUsesTheRouteToPickTheLibrary() async throws {
        let stub = SurfaceSecondaryStub()
        let viewModel = DocumentsViewModel(
            library: .school,
            route: "extraacademics/documents&folder_id=4",
            repository: DocumentRepository(client: stub, cache: cache, resolveContext: resolver(demo))
        )
        XCTAssertEqual(viewModel.library, .extraAcademics)
        XCTAssertFalse(viewModel.isRoot)
    }

    func testDocumentsReportsAnErrorOnlyWhenEmpty() async throws {
        let stub = SurfaceSecondaryStub()
        await stub.setFailure(W4Error.forbidden)
        let viewModel = DocumentsViewModel(
            route: nil,
            repository: DocumentRepository(client: stub, cache: cache, resolveContext: resolver(signedIn))
        )

        // `.forbidden` must NOT log the student out — it means wrong role, not a dead session.
        let logout = XCTNSNotificationExpectation(name: .w4SessionExpired)
        logout.isInverted = true

        await viewModel.load()

        await fulfillment(of: [logout], timeout: 0.5)
        XCTAssertNil(viewModel.listing)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Trips and travel

    func testTripsDemoShowsTheTripAndTheFourJourneys() async throws {
        let stub = SurfaceSecondaryStub()
        await stub.setFailure(W4Error.noResponse)
        let viewModel = TripsViewModel(
            trips: TripRepository(client: stub, cache: cache, resolveContext: resolver(demo)),
            travel: TravelRepository(client: stub, cache: cache, resolveContext: resolver(demo))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.trips.count, 1)
        XCTAssertEqual(viewModel.trips.first?.name, "Bergen weekend")
        XCTAssertEqual(viewModel.trips.first?.status, .planning)
        XCTAssertEqual(viewModel.trips.first?.statusDisplay, "Planning")
        XCTAssertNotNil(TripsViewModel.dateRange(for: try XCTUnwrap(viewModel.trips.first)))
        XCTAssertEqual(viewModel.travelForms.count, TravelJourney.allCases.count)
        XCTAssertEqual(viewModel.travelForms.first?.journey, .toSchoolAutumn)
        XCTAssertEqual(viewModel.contacts.count, 2)
        XCTAssertNil(viewModel.errorMessage)

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0)
    }

    func testAFailedTravelFetchDoesNotBlankTheTripGrid() async throws {
        let stub = SurfaceSecondaryStub()
        await stub.setHTML(
            "<html><body><div id=\"content_inner\"><h2>My trips</h2></div></body></html>",
            forRoute: W4Routes.R.trips
        )
        await stub.setFailure(
            W4Error.httpError(status: 500, route: W4Routes.R.travel),
            forRoute: W4Routes.R.travel
        )
        let viewModel = TripsViewModel(
            trips: TripRepository(client: stub, cache: cache, resolveContext: resolver(signedIn)),
            travel: TravelRepository(client: stub, cache: cache, resolveContext: resolver(signedIn))
        )

        await viewModel.load()

        XCTAssertNotNil(viewModel.tripList, "the half that succeeded must still render")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.travelPage)
        XCTAssertFalse(viewModel.tripsEmptyMessage.isEmpty)
    }

    // MARK: - Extra Academics

    func testExtraAcademicsDemoRendersTheContentWell() async throws {
        let stub = SurfaceRouteStub()
        await stub.setFailure(W4Error.noResponse)
        let repository = ExtraAcademicsRepository(client: stub, cache: cache, context: resolver(demo))
        let viewModel = ExtraAcademicsViewModel(page: .myActivities, repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.title, "My activities")
        XCTAssertTrue(viewModel.hasContent)
        // The `<h2>` the navigation bar already shows is dropped from the body exactly once.
        if case .heading? = viewModel.blocks.first {
            XCTFail("the duplicate page heading should not be rendered twice")
        }
        let calls = await stub.callCount
        XCTAssertEqual(calls, 0)
    }

    func testExtraAcademicsForbiddenDoesNotSignTheStudentOut() async throws {
        let stub = SurfaceRouteStub()
        await stub.setFailure(W4Error.forbidden)
        let repository = ExtraAcademicsRepository(client: stub, cache: cache, context: resolver(signedIn))
        let viewModel = ExtraAcademicsViewModel(page: .safetyNet, repository: repository)

        let logout = XCTNSNotificationExpectation(name: .w4SessionExpired)
        logout.isInverted = true

        await viewModel.load()

        await fulfillment(of: [logout], timeout: 0.5)
        XCTAssertFalse(viewModel.hasContent)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.title, "My SafetyNet")
    }

    func testExtraAcademicsRendersARealPageBody() async throws {
        let stub = SurfaceRouteStub()
        await stub.setHTML(
            """
            <html><body><div id="content_inner">
            <h2>My portfolio</h2>
            <p>Kayaking &mdash; 12 sessions</p>
            <p>Outcome: <a href="/index.php?r=extraacademics/activities/myportfolio">Perseverance</a></p>
            </div></body></html>
            """,
            forRoute: ExtraAcademicsPage.portfolio.route
        )
        let repository = ExtraAcademicsRepository(client: stub, cache: cache, context: resolver(signedIn))
        let viewModel = ExtraAcademicsViewModel(page: .portfolio, repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.title, "My portfolio")
        XCTAssertEqual(viewModel.blocks.count, 2)
        XCTAssertNil(viewModel.errorMessage)
    }
}
