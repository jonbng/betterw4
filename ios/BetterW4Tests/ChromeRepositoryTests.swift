//
//  ChromeRepositoryTests.swift
//  BetterW4Tests
//
//  Tests for the Wave 5.6 chrome layer: `ChromeObserver`, `CampusStatusRepository` and
//  `NotificationRepository`.
//
//  EVIDENCE MAP — read this before adding an assertion.
//
//    [V] `Fixtures/W4/home.html` is a REAL capture of https://w4.uwcrcn.no (sanitized). It carries
//        the campus widget with all eleven options AND an EMPTY `div.notifications` — zero
//        notifications is the normal state at this school (bug B8).
//
//    [I] `Fixtures/W4/notifications-populated.html` and every fragment written inline below are
//        SYNTHESIZED. A populated bell has never been captured, and nobody has ever captured this
//        student off campus. Those assertions verify OUR CODE, not W4.
//
//  NO TEST HERE TOUCHES THE NETWORK. Both repositories are driven through the `W4ChromeTransport`
//  seam by `ChromeStubTransport`, which fails loudly on any call it was not primed for — so "made
//  no request" is an assertion, not an assumption.
//
//  The load-bearing tests in this file:
//
//    * `testCachedHomePageUpdatesBothSnapshotsWithZeroRequests` — the point of the whole design.
//    * `testSetStatusOnCampusPostsExactlyStatusOn` — plan D-12 / bug B6.
//    * `testSetStatusReplacesTheSnapshotWithTheServersAnswer` — never assume a write succeeded.
//    * `testSessionExpiredIsNeverSwallowedByTheCachedCopy` — the app cannot re-login without it.
//

import XCTest
@testable import BetterW4

// MARK: - Test doubles

/// One recorded call on the transport seam.
private struct ChromeCallRecord {
    enum Kind { case page, postAjax }
    let kind: Kind
    let route: String
    let fields: [String: String]
    let isOpportunistic: Bool
}

/// A `W4ChromeTransport` that answers from a queue and records everything.
///
/// An un-primed call throws ``ChromeStubTransport/Unexpected`` rather than returning something
/// plausible: a repository that reaches the network when it should not must fail the test that
/// exercises it, not quietly pass.
private final class ChromeStubTransport: W4ChromeTransport, @unchecked Sendable {

    struct Unexpected: Error, CustomStringConvertible {
        let route: String
        var description: String { "ChromeStubTransport was not primed for \(route)" }
    }

    private let lock = NSLock()
    private var recorded: [ChromeCallRecord] = []
    private var pageQueue: [Result<String, Error>] = []
    private var postQueue: [Result<String, Error>] = []

    // MARK: Priming

    func enqueuePage(_ html: String) {
        lock.lock(); pageQueue.append(.success(html)); lock.unlock()
    }

    func enqueuePageFailure(_ error: Error) {
        lock.lock(); pageQueue.append(.failure(error)); lock.unlock()
    }

    func enqueuePost(_ html: String) {
        lock.lock(); postQueue.append(.success(html)); lock.unlock()
    }

    func enqueuePostFailure(_ error: Error) {
        lock.lock(); postQueue.append(.failure(error)); lock.unlock()
    }

    // MARK: Inspection

    var calls: [ChromeCallRecord] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var callCount: Int { calls.count }

    // MARK: W4ChromeTransport

    func fetchPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse {
        try answer(kind: .page, route: route, fields: query, priority: priority, fromPageQueue: true)
    }

    func postAjax(
        route: String,
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> ChromePageResponse {
        try answer(kind: .postAjax, route: route, fields: fields, priority: priority, fromPageQueue: false)
    }

    private func answer(
        kind: ChromeCallRecord.Kind,
        route: String,
        fields: [String: String],
        priority: FetchPriority,
        fromPageQueue: Bool
    ) throws -> ChromePageResponse {
        let isOpportunistic: Bool
        switch priority {
        case .opportunistic: isOpportunistic = true
        case .important: isOpportunistic = false
        }

        lock.lock()
        recorded.append(
            ChromeCallRecord(kind: kind, route: route, fields: fields, isOpportunistic: isOpportunistic)
        )
        let next = fromPageQueue
            ? (pageQueue.isEmpty ? nil : pageQueue.removeFirst())
            : (postQueue.isEmpty ? nil : postQueue.removeFirst())
        lock.unlock()

        guard let next else { throw Unexpected(route: route) }
        switch next {
        case .success(let html):
            return ChromePageResponse(html: html, finalURL: W4Routes.url(route))
        case .failure(let error):
            throw error
        }
    }
}

/// Breaks the init cycle in the one test that needs a repository to broadcast into an observer that
/// does not exist yet.
private final class ChromeObserverBox: @unchecked Sendable {
    var observer: ChromeObserver?
}

// MARK: - Tests

final class ChromeRepositoryTests: XCTestCase {

    // MARK: Fixtures

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

    private func homePage() throws -> String { try fixture("home") }
    private func populatedBellPage() throws -> String { try fixture("notifications-populated") }

    // MARK: Synthesized markup [I]

    /// `.status-dropdown` rendered off campus. Nobody has captured this student off campus.
    private let offCampusFragment = """
    <div class="status-dropdown">
      <div class="status offcampus">
        <div class="status-value">off campus</div>
        <div class="location">(In Dale)</div>
      </div>
    </div>
    """

    /// What `notifications.js:65` swaps in: a wrapper whose *children* are the new bell.
    private let oneItemBellFragment = """
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
    """

    private let loginPage = """
    <html><body><form action="/index.php?r=site/login" method="post">
    <input name="LoginForm[username]" type="text"><input name="LoginForm[password]" type="password">
    </form></body></html>
    """

    private let pageWithoutChrome = "<html><body><p>Nothing to see here.</p></body></html>"

    // MARK: Environment

    private func temporaryCache() -> W4PageCache {
        W4PageCache(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("ChromeRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        )
    }

    private func liveContext(uwcId: String = "nc26abcd") -> W4RequestContext {
        W4RequestContext(
            student: Student(
                studentId: uwcId,
                name: "Alex Andersen",
                pictureId: nil,
                classLabel: nil
            ),
            credentials: W4Credentials(sessionId: "PHPSESSID-under-test")
        )
    }

    private func demoContext() -> W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func makeCampusRepository(
        client: ChromeStubTransport,
        cache: W4PageCache? = nil,
        context: W4RequestContext? = nil,
        broadcast: (@Sendable (String, ChromePageOrigin) async -> Void)? = nil
    ) -> CampusStatusRepository {
        let resolved = context ?? liveContext()
        return CampusStatusRepository(
            client: client,
            cache: cache ?? temporaryCache(),
            resolveContext: { resolved },
            broadcast: broadcast
        )
    }

    private func makeNotificationRepository(
        client: ChromeStubTransport,
        cache: W4PageCache? = nil,
        context: W4RequestContext? = nil
    ) -> NotificationRepository {
        let resolved = context ?? liveContext()
        return NotificationRepository(
            client: client,
            cache: cache ?? temporaryCache(),
            resolveContext: { resolved }
        )
    }

    // MARK: - [V] Harvesting: the point of the whole design

    /// **Done criterion.** Applying a cached Home page updates BOTH snapshots with no network call.
    func testCachedHomePageUpdatesBothSnapshotsWithZeroRequests() async throws {
        let html = try homePage()
        let campusClient = ChromeStubTransport()
        let bellClient = ChromeStubTransport()
        let campus = makeCampusRepository(client: campusClient)
        let bell = makeNotificationRepository(client: bellClient)
        let observer = ChromeObserver(campusStatus: campus, notifications: bell)

        let fetchedAt = Date().addingTimeInterval(-3600)
        let harvest = await observer.apply(html: html, origin: .cache(fetchedAt: fetchedAt))

        XCTAssertTrue(harvest.didUpdateCampusStatus)
        XCTAssertTrue(harvest.didUpdateNotifications)

        // [V] The real capture: on campus, empty location, all eleven radios.
        XCTAssertEqual(harvest.campusStatus?.value.isOnCampus, true)
        XCTAssertNil(harvest.campusStatus?.value.location)
        XCTAssertEqual(harvest.campusStatus?.value.options.count, 11)

        // [V] Bug B8: `div.notifications` is empty in the real capture, and empty is a SUCCESS.
        XCTAssertEqual(harvest.notifications?.value, W4NotificationSnapshot.empty)
        XCTAssertEqual(harvest.notifications?.value.count, 0)

        // A page fetched an hour ago is honestly reported as stale — the chrome TTL is 60 s.
        let staleAnHourAgo = W4Freshness.cached(fetchedAt: fetchedAt, isStale: true)
        XCTAssertEqual(harvest.campusStatus?.freshness, staleAnHourAgo)
        XCTAssertEqual(harvest.notifications?.freshness, staleAnHourAgo)

        // The whole promise: zero extra requests.
        XCTAssertEqual(campusClient.callCount, 0)
        XCTAssertEqual(bellClient.callCount, 0)
    }

    /// [I] A populated bell is read out of ordinary page chrome, again with no request.
    func testPopulatedBellIsHarvestedFromPageChrome() async throws {
        let html = try populatedBellPage()
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)

        let harvested = await bell.apply(pageHTML: html, origin: .live)
        let loaded = try XCTUnwrap(harvested)

        XCTAssertEqual(loaded.value.count, 3)
        // The badge carries `alert new`, and the badge's own class beats the most severe row.
        XCTAssertEqual(loaded.value.severity, .new)
        XCTAssertEqual(loaded.value.taskGroups.count, 1)
        XCTAssertEqual(loaded.value.emailGroups.count, 1)
        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(client.callCount, 0)
    }

    /// Login HTML must never reach the parsers: `W4NotificationParser` falls through to
    /// `document.body()`, finds no rows, and would silently empty a populated bell.
    func testUnauthenticatedHTMLNeverDisturbsEitherSnapshot() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)
        let bell = makeNotificationRepository(client: client)
        let observer = ChromeObserver(campusStatus: campus, notifications: bell)

        _ = try await observer.apply(html: populatedBellPage(), origin: .live)
        let primed = await bell.snapshot()?.value.count
        XCTAssertEqual(primed, 3)

        for hostile in [loginPage, pageWithoutChrome, ""] {
            let harvest = await observer.apply(html: hostile, origin: .live)
            XCTAssertTrue(harvest.isEmpty, "a page without W4 chrome must be ignored outright")
        }

        // Still three. Nothing was cleared by a page that had nothing to say.
        let survived = await bell.snapshot()?.value.count
        let chip = await campus.snapshot()?.value.isOnCampus
        XCTAssertEqual(survived, 3)
        XCTAssertEqual(chip, true)
        XCTAssertEqual(client.callCount, 0)
    }

    /// Pages arrive out of order once several repositories are in flight.
    func testAnOlderPageDoesNotOverwriteANewerObservation() async throws {
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)

        _ = try await bell.apply(pageHTML: populatedBellPage(), origin: .live)
        let before = await bell.snapshot()?.value.count
        XCTAssertEqual(before, 3)

        // A Home page pulled off disk from an hour ago, whose bell is empty.
        _ = try await bell.apply(pageHTML: homePage(), origin: .cache(fetchedAt: Date().addingTimeInterval(-3600)))

        let after = await bell.snapshot()?.value.count
        XCTAssertEqual(after, 3, "an older render must not win")
    }

    /// One `site/index` fetch, two surfaces refreshed — the broadcast hook, end to end.
    func testObserverRefreshMakesOneRequestAndUpdatesBothHalves() async throws {
        let campusClient = ChromeStubTransport()
        let bellClient = ChromeStubTransport()
        try campusClient.enqueuePage(populatedBellPage())

        let box = ChromeObserverBox()
        let campus = makeCampusRepository(client: campusClient, broadcast: { html, origin in
            _ = await box.observer?.applyNotifications(html: html, origin: origin)
        })
        let bell = makeNotificationRepository(client: bellClient)
        let observer = ChromeObserver(campusStatus: campus, notifications: bell)
        box.observer = observer

        let harvest = try await observer.refresh()

        XCTAssertEqual(harvest.campusStatus?.value.isOnCampus, true)
        XCTAssertEqual(harvest.campusStatus?.freshness, W4Freshness.fresh)
        XCTAssertEqual(harvest.notifications?.value.count, 3)

        XCTAssertEqual(campusClient.callCount, 1)
        XCTAssertEqual(campusClient.calls.first?.route, W4Routes.R.home)
        XCTAssertEqual(bellClient.callCount, 0, "the bell must ride along on the campus fetch")
    }

    /// The update stream is what Wave 6 will bind a view model to.
    func testUpdatesStreamPublishesEveryAcceptedObservation() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)

        // Registered synchronously, so the yield below cannot be missed.
        let stream = campus.updatesStream()
        let receiver = Task { () -> CampusStatus? in
            for await loaded in stream { return loaded.value }
            return nil
        }

        _ = try await campus.apply(pageHTML: homePage(), origin: .live)

        let received = await receiver.value
        XCTAssertEqual(received?.isOnCampus, true)
        XCTAssertEqual(received?.options.count, 11)
    }

    // MARK: - Campus status: the write (plan D-12 / bug B6)

    /// **Done criterion.** "On campus" posts exactly `["status": "on"]` — no `location` key at all.
    func testSetStatusOnCampusPostsExactlyStatusOn() async throws {
        let client = ChromeStubTransport()
        client.enqueuePost("")   // W4's own JS throws this response away; it is usually empty.
        let campus = makeCampusRepository(client: client)

        let onCampus = try XCTUnwrap(CampusStatus.defaultOptions.first(where: { $0.isOnCampus }))
        let loaded = try await campus.setStatus(option: onCampus)

        XCTAssertEqual(client.callCount, 1)
        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.route, W4Routes.R.setStatus)
        XCTAssertEqual(call.route, "site/setstatus")
        XCTAssertEqual(call.fields, ["status": "on"])
        XCTAssertNil(call.fields["location"], "posting a location while on campus is bug B6")

        XCTAssertTrue(loaded.value.isOnCampus)
        XCTAssertNil(loaded.value.location)
        XCTAssertEqual(loaded.freshness, .fresh)
    }

    /// [I] Bug B6, the other half: an off-campus option posts its POST **value**, never its label.
    func testSetStatusOffCampusPostsTheOptionValueNotItsLabel() async throws {
        let client = ChromeStubTransport()
        client.enqueuePost("")
        let campus = makeCampusRepository(client: client)

        // A deliberately mismatched pair: W4 renders value and label separately, and only the
        // value is postable.
        let option = CampusLocationOption(id: "location_2", value: "At Raudbua", label: "Raudbua cabin")
        let loaded = try await campus.setStatus(option: option)

        XCTAssertEqual(client.calls.first?.fields, ["status": "off", "location": "At Raudbua"])
        XCTAssertFalse(loaded.value.isOnCampus)
        XCTAssertEqual(loaded.value.location, "At Raudbua")
    }

    /// [I] "Other" posts the free text, capped at `input#other[maxlength=20]` [V].
    func testSetStatusOtherPostsTheFreeTextCappedAtTwentyCharacters() async throws {
        let client = ChromeStubTransport()
        client.enqueuePost("")
        let campus = makeCampusRepository(client: client)

        let other = try XCTUnwrap(CampusStatus.defaultOptions.first(where: { $0.isFreeText }))
        let typed = "   In the sports hall annexe   "
        let expected = String(typed.trimmingCharacters(in: .whitespaces).prefix(CampusStatus.freeTextMaxLength))

        let loaded = try await campus.setStatus(option: other, freeText: typed)

        XCTAssertEqual(client.calls.first?.fields, ["status": "off", "location": expected])
        XCTAssertEqual(expected.count, 20)
        XCTAssertEqual(loaded.value.location, expected)
    }

    /// `campusstatusdropdown.js:12-15` refuses to post "Other" with an empty box. So do we.
    func testSetStatusOtherWithoutTextThrowsAndPostsNothing() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)
        let other = try XCTUnwrap(CampusStatus.defaultOptions.first(where: { $0.isFreeText }))

        do {
            _ = try await campus.setStatus(option: other, freeText: "   ")
            XCTFail("an empty free-text location must not be posted")
        } catch let error as CampusStatusWriteError {
            XCTAssertEqual(error, .locationRequired)
        }
        XCTAssertEqual(client.callCount, 0)
    }

    func testSetStatusWithAnUnknownOptionIDThrowsAndPostsNothing() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)

        do {
            _ = try await campus.setStatus(optionID: "location_999")
            XCTFail("an unknown option id must not be guessed into a POST value")
        } catch let error as CampusStatusWriteError {
            XCTAssertEqual(error, .unknownOption("location_999"))
        }
        XCTAssertEqual(client.callCount, 0)
    }

    /// [I] Never assume the write succeeded: when the server answers with the widget, the server wins.
    func testSetStatusReplacesTheSnapshotWithTheServersAnswer() async throws {
        let client = ChromeStubTransport()
        client.enqueuePost(offCampusFragment)
        let campus = makeCampusRepository(client: client)

        let onCampus = try XCTUnwrap(CampusStatus.defaultOptions.first(where: { $0.isOnCampus }))
        let loaded = try await campus.setStatus(option: onCampus)

        // We asked to go on campus; W4 says we are in Dale. W4 is the record of truth.
        XCTAssertFalse(loaded.value.isOnCampus)
        // Bug B7: `campusstatusdropdown.js:28` writes "(In Dale)"; one wrapping pair is stripped.
        XCTAssertEqual(loaded.value.location, "In Dale")
    }

    /// A failed write must throw, never quietly report the state we hoped for.
    func testFailedWriteThrowsInsteadOfDegradingToTheCachedCopy() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)
        _ = try await campus.apply(pageHTML: homePage(), origin: .live)   // a good cached copy exists

        client.enqueuePostFailure(W4Error.httpError(status: 500, route: W4Routes.R.setStatus))
        let option = CampusLocationOption(id: "location_5", value: "In Flekke", label: "In Flekke")

        do {
            _ = try await campus.setStatus(option: option)
            XCTFail("a failed write must surface")
        } catch let error as W4Error {
            guard case .httpError(let status, _) = error else {
                return XCTFail("expected the HTTP failure, got \(error)")
            }
            XCTAssertEqual(status, 500)
        }
        // The snapshot is untouched: we never claimed the move happened.
        let unchanged = await campus.snapshot()?.value.isOnCampus
        XCTAssertEqual(unchanged, true)
    }

    // MARK: - Failure policy

    /// A read that fails degrades to the copy we hold rather than blanking the chip.
    func testLoadFallsBackToTheCachedCopyWhenTheFetchFails() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)
        _ = try await campus.apply(pageHTML: homePage(), origin: .live)

        client.enqueuePageFailure(W4Error.httpError(status: 503, route: W4Routes.R.home))
        let loaded = try await campus.load(forceRefresh: true)

        XCTAssertTrue(loaded.value.isOnCampus)
        XCTAssertTrue(loaded.freshness.isFromCache, "a degraded read must say so")
    }

    /// **The one error that may never be swallowed.** Without it the app never re-logs-in.
    func testSessionExpiredIsNeverSwallowedByTheCachedCopy() async throws {
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)
        _ = try await campus.apply(pageHTML: homePage(), origin: .live)
        let rescueCandidate = await campus.snapshot()
        XCTAssertNotNil(rescueCandidate, "the cached copy that must NOT rescue us")

        client.enqueuePageFailure(W4Error.sessionExpired)
        do {
            _ = try await campus.load(forceRefresh: true)
            XCTFail("sessionExpired must propagate even with a perfectly good cached copy")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }

        // Same rule on the bell.
        let bellClient = ChromeStubTransport()
        let bell = makeNotificationRepository(client: bellClient)
        _ = try await bell.apply(pageHTML: populatedBellPage(), origin: .live)
        bellClient.enqueuePostFailure(W4Error.sessionExpired)
        do {
            _ = try await bell.load(forceRefresh: true)
            XCTFail("sessionExpired must propagate from the bell too")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// D-21: 403 without "Login Required" is a role problem, not a dead session.
    func testForbiddenIsNotTreatedAsADeadSession() async throws {
        // With a cached copy it degrades like any other failure…
        let client = ChromeStubTransport()
        let campus = makeCampusRepository(client: client)
        _ = try await campus.apply(pageHTML: homePage(), origin: .live)
        client.enqueuePageFailure(W4Error.forbidden)

        let loaded = try await campus.load(forceRefresh: true)
        XCTAssertTrue(loaded.freshness.isFromCache)

        // …and with nothing cached it surfaces as itself, never as .sessionExpired.
        let coldClient = ChromeStubTransport()
        let cold = makeCampusRepository(client: coldClient)
        coldClient.enqueuePageFailure(W4Error.forbidden)
        do {
            _ = try await cold.load()
            XCTFail("a cold forbidden read must surface")
        } catch let error as W4Error {
            guard case .forbidden = error else {
                return XCTFail("expected .forbidden, got \(error)")
            }
        }
        XCTAssertFalse(ChromeFailure.mustPropagate(W4Error.forbidden))
        XCTAssertTrue(ChromeFailure.mustPropagate(W4Error.sessionExpired))
        XCTAssertTrue(ChromeFailure.mustPropagate(CancellationError()))
    }

    // MARK: - Persistence

    /// The snapshot survives the process: a second repository over the same cache renders offline.
    func testCampusStatusSurvivesANewRepositoryInstanceViaThePageCache() async throws {
        let cache = temporaryCache()
        let context = liveContext()

        let writer = makeCampusRepository(client: ChromeStubTransport(), cache: cache, context: context)
        _ = try await writer.apply(pageHTML: homePage(), origin: .live)

        let coldClient = ChromeStubTransport()   // primed for nothing: any fetch fails the test
        let reader = makeCampusRepository(client: coldClient, cache: cache, context: context)
        let loaded = try await reader.load()

        XCTAssertTrue(loaded.value.isOnCampus)
        XCTAssertEqual(loaded.value.options.count, 11)
        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(coldClient.callCount, 0, "a fresh cached copy must not trigger a fetch")
    }

    /// The cache is scoped per uwc id — another student's chip can never leak through.
    func testAnotherStudentsCachedChipIsNotServed() async throws {
        let cache = temporaryCache()
        let writer = makeCampusRepository(
            client: ChromeStubTransport(), cache: cache, context: liveContext(uwcId: "nc26abcd")
        )
        _ = try await writer.apply(pageHTML: homePage(), origin: .live)

        let otherClient = ChromeStubTransport()
        otherClient.enqueuePageFailure(W4Error.httpError(status: 500, route: W4Routes.R.home))
        let other = makeCampusRepository(
            client: otherClient, cache: cache, context: liveContext(uwcId: "nc25zzzz")
        )

        do {
            _ = try await other.load()
            XCTFail("there is nothing cached for this student")
        } catch let error as W4Error {
            guard case .httpError = error else {
                return XCTFail("expected the HTTP failure, got \(error)")
            }
        }
        XCTAssertEqual(otherClient.callCount, 1)
    }

    // MARK: - Notifications: writes

    /// [I] Every mutation re-parses the returned fragment and REPLACES the snapshot.
    func testNotificationMutationReplacesTheSnapshotFromTheReturnedFragment() async throws {
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)
        _ = try await bell.apply(pageHTML: populatedBellPage(), origin: .live)
        let before = await bell.snapshot()?.value.count
        XCTAssertEqual(before, 3)

        client.enqueuePost(oneItemBellFragment)
        let loaded = try await bell.markRead(id: "12")

        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.route, W4Routes.R.notificationsRead)
        XCTAssertEqual(call.route, "notifications/read")
        XCTAssertEqual(call.fields, ["notification_id": "12"])

        XCTAssertEqual(loaded.value.count, 1, "the fragment is the new truth, not our guess")
        XCTAssertEqual(loaded.value.items.map(\.id), ["13"])
        XCTAssertEqual(loaded.freshness, .fresh)
    }

    /// [I] An empty response empties the bell — exactly what `notifications.js:65` does with it.
    func testAnEmptyFragmentEmptiesTheBell() async throws {
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)
        _ = try await bell.apply(pageHTML: populatedBellPage(), origin: .live)

        client.enqueuePost("")
        let loaded = try await bell.clearAll()

        XCTAssertEqual(loaded.value, .empty)
        XCTAssertTrue(loaded.value.isEmpty)
        XCTAssertEqual(client.calls.first?.route, W4Routes.R.notificationsClearAll)
    }

    /// OQ-9: never invent an id. No identifier, no request.
    func testActionsThatNeedAnIdentifierThrowWithoutOne() async throws {
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)

        for action in [W4NotificationAction.read, .clear, .readGroup, .clearGroup] {
            do {
                _ = try await bell.perform(action, identifier: "  ")
                XCTFail("\(action.rawValue) must refuse a blank identifier")
            } catch let error as NotificationWriteError {
                XCTAssertEqual(error, .identifierRequired(action))
            }
        }
        XCTAssertEqual(client.callCount, 0)
    }

    /// Group actions post `notification_type`; the blanket actions post nothing at all.
    func testGroupAndBlanketActionsPostTheRightBody() async throws {
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)

        client.enqueuePost(oneItemBellFragment)
        _ = try await bell.markGroupRead(type: "assessment")
        XCTAssertEqual(client.calls.last?.route, W4Routes.R.notificationsReadGroup)
        XCTAssertEqual(client.calls.last?.fields, ["notification_type": "assessment"])

        client.enqueuePost(oneItemBellFragment)
        _ = try await bell.markAllEmailsRead()
        XCTAssertEqual(client.calls.last?.route, W4Routes.R.notificationsReadAllEmails)
        XCTAssertEqual(client.calls.last?.fields, [String: String]())
    }

    // MARK: - Notifications: the poll

    /// The interval is `CachePolicy`'s, not a literal — and it matches W4's own `setInterval`.
    func testPollIntervalComesFromCachePolicyAndIsSixtySeconds() {
        XCTAssertEqual(NotificationRepository.pollInterval, CachePolicy.ttl(for: .chrome))
        XCTAssertEqual(NotificationRepository.pollInterval, 60)
    }

    /// The poll is allowed ONLY while the sheet is closed and the app is foregrounded.
    func testPollIsSuppressedWhileTheSheetIsOpenOrTheAppIsBackgrounded() async throws {
        let bell = makeNotificationRepository(client: ChromeStubTransport())

        var allowed = await bell.shouldPoll()
        XCTAssertTrue(allowed)

        await bell.setSheetOpen(true)
        allowed = await bell.shouldPoll()
        XCTAssertFalse(allowed, "refreshing under the student's finger reshuffles what they are tapping")

        await bell.setSheetOpen(false)
        allowed = await bell.shouldPoll()
        XCTAssertTrue(allowed)

        await bell.setForegroundActive(false)
        allowed = await bell.shouldPoll()
        XCTAssertFalse(allowed)

        // Demo never polls, because demo never reaches the network.
        let demo = makeNotificationRepository(client: ChromeStubTransport(), context: demoContext())
        let demoAllowed = await demo.shouldPoll()
        XCTAssertFalse(demoAllowed)
    }

    /// A background refresh must never queue ahead of the screen the student is looking at.
    func testOpportunisticPriorityReachesTheTransport() async throws {
        let client = ChromeStubTransport()
        let bell = makeNotificationRepository(client: client)

        client.enqueuePost(oneItemBellFragment)
        _ = try await bell.refresh(priority: .opportunistic)

        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.route, W4Routes.R.notificationsRefresh)
        XCTAssertEqual(call.fields, [String: String]())
        XCTAssertTrue(call.isOpportunistic)
    }

    // MARK: - Demo

    /// The demo session must never make a request — not for a read, not for a write.
    func testDemoSessionNeverTouchesTheNetwork() async throws {
        let campusClient = ChromeStubTransport()
        let bellClient = ChromeStubTransport()
        let campus = makeCampusRepository(client: campusClient, context: demoContext())
        let bell = makeNotificationRepository(client: bellClient, context: demoContext())

        let chip = try await campus.load(forceRefresh: true)
        XCTAssertEqual(chip.freshness, .demo)
        XCTAssertTrue(chip.value.isOnCampus)

        let option = try XCTUnwrap(CampusStatus.defaultOptions.first(where: { $0.value == "At Raudbua" }))
        let moved = try await campus.setStatus(option: option)
        XCTAssertEqual(moved.freshness, .demo)
        XCTAssertFalse(moved.value.isOnCampus)
        XCTAssertEqual(moved.value.location, "At Raudbua")

        let bellLoaded = try await bell.load(forceRefresh: true)
        XCTAssertEqual(bellLoaded.freshness, .demo)
        XCTAssertEqual(bellLoaded.value.count, 3)

        let afterRead = try await bell.markAllRead()
        XCTAssertEqual(afterRead.freshness, .demo)
        XCTAssertEqual(afterRead.value.count, 0)
        XCTAssertEqual(afterRead.value.severity, .normal)
        XCTAssertEqual(afterRead.value.items.count, 3, "read downgrades rows, it does not delete them")

        XCTAssertEqual(campusClient.callCount, 0)
        XCTAssertEqual(bellClient.callCount, 0)
    }

    /// The demo bell's action semantics, as a pure function.
    func testDemoBellActionsReadAndClearDifferently() {
        let base = NotificationRepository.demoSnapshot
        XCTAssertEqual(base.items.count, 3)

        let cleared = NotificationRepository.demoResult(of: .clearAll, identifier: nil, in: base)
        XCTAssertEqual(cleared, .empty)

        let oneCleared = NotificationRepository.demoResult(
            of: .clear, identifier: "demo-email-1", in: base
        )
        XCTAssertEqual(oneCleared.items.count, 2)
        XCTAssertTrue(oneCleared.emailGroups.isEmpty, "an emptied group disappears with its last row")

        let groupRead = NotificationRepository.demoResult(
            of: .readGroup, identifier: "assessment", in: base
        )
        XCTAssertEqual(groupRead.items.count, 3)
        XCTAssertEqual(groupRead.count, 1, "only the untouched email is still unread")
        XCTAssertEqual(groupRead.severity, .new)

        XCTAssertEqual(NotificationRepository.demoResult(of: .refresh, identifier: nil, in: base), base)
    }
}
