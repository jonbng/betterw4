//
//  DirectoryViewModelTests.swift
//  BetterW4Tests
//
//  Unit tests for `DirectoryViewModel` — the people directory's view model (plan Wave 6 item 6.5).
//
//  SEAM. Nothing here touches the network, the Keychain or SwiftData. `DirectoryRepository` and
//  `ProfileRepository` both take a `W4PeopleFetching` transport, a `W4PageCache` pointed at a temp
//  directory, a `W4PeopleStoring` persistence seam and a `() throws -> W4RequestContext` provider,
//  so the whole stack under the view model is stubbed without modifying anything to be testable.
//
//  What is asserted here is `features.md` §3 behaviour, not W4 markup: cache-first paint, a
//  spinner only when the screen would otherwise be blank, generation guards, "never wipe on a
//  transient error", `.forbidden` not logging anybody out, pin scoping, and search ranking.
//
//  FIXTURE PROVENANCE. The `ul.user-list` pages below are **[I] SYNTHESIZED** — no W4 people list
//  has ever been captured. They exercise this port's view model, and are evidence about nothing
//  else.
//
//  IDENTITIES. Invented `nc00…` / `nc99…` ids and made-up names (`reviewer-notes.md` §8).
//

import XCTest
@testable import BetterW4

// MARK: - Stubs

private final class ScriptedPeopleFetcher: W4PeopleFetching, @unchecked Sendable {

    private let responder: @Sendable (String, [String: String]) async throws -> String
    private let lock = NSLock()
    private var _routes: [String] = []

    init(responder: @escaping @Sendable (String, [String: String]) async throws -> String) {
        self.responder = responder
    }

    var routes: [String] {
        lock.lock(); defer { lock.unlock() }
        return _routes
    }

    func fetchPage(
        route: String,
        query: [String: String],
        priority: FetchPriority,
        credentials: W4Credentials,
        uwcId: String
    ) async throws -> W4PeopleFetchResult {
        lock.lock()
        _routes.append(route)
        lock.unlock()
        let html = try await responder(route, query)
        return W4PeopleFetchResult(html: html, finalURL: W4Routes.url(route, query))
    }
}

/// A gate a stubbed request can park on, so "this request was still in flight" is a fact rather
/// than a race against a sleep.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let parked = waiters
        waiters.removeAll()
        for continuation in parked { continuation.resume() }
    }
}

private actor MemoryPeopleStore: W4PeopleStoring {
    private var people: [DirectoryPerson]

    init(seed: [DirectoryPerson] = []) {
        self.people = seed
    }

    func replaceAll(_ incoming: [DirectoryPerson]) async {
        guard !incoming.isEmpty else { return }
        people = incoming
    }

    func upsert(_ incoming: [DirectoryPerson]) async {
        var byId = Dictionary(people.map { ($0.uwcId, $0) }, uniquingKeysWith: { _, new in new })
        for person in incoming { byId[person.uwcId] = person }
        people = byId.values.sorted { $0.uwcId < $1.uwcId }
    }

    func allPeople() async -> [DirectoryPerson] { people }

    func person(uwcId: String) async -> DirectoryPerson? {
        people.first { $0.uwcId == uwcId }
    }
}

// MARK: - Fixtures (nonisolated: the stub transport builds pages off the main actor)

private enum PeopleFixtures {

    static func person(
        _ uwcId: String,
        _ name: String,
        kind: DirectoryPersonKind = .student,
        year: String? = "1"
    ) -> DirectoryPerson {
        DirectoryPerson(
            uwcId: uwcId,
            name: name,
            kind: kind,
            year: kind == .student ? year : nil,
            house: "Haugland",
            country: "Norway",
            photoURL: W4PeopleParser.photoURL(forUWCId: uwcId)
        )
    }

    /// A synthesized `ul.user-list` page. The per-row `href` is what decides student vs staff —
    /// never a document-wide search (`parsers.md` §11).
    static func listHTML(_ people: [DirectoryPerson]) -> String {
        let rows = people.map { person -> String in
            let route = person.kind == .staff ? "people/staff/staff" : "people/students/student"
            return """
            <li>
              <a href="/index.php?r=\(route)&amp;uwc_id=\(person.uwcId)"><img class="photo" src="/files/user_photos/\(person.uwcId)_thumb.jpg" alt="Photo of \(person.uwcId)" /></a>
              <a href="/index.php?r=\(route)&amp;uwc_id=\(person.uwcId)">\(person.name)</a>
              <br />Neverland<br />
            </li>
            """
        }.joined(separator: "\n")

        return """
        <html><body><div id="content_inner">
          <h2>People</h2>
          <ul class="user-list">
          \(rows)
          </ul>
        </div></body></html>
        """
    }
}

// MARK: - Tests

@MainActor
final class DirectoryViewModelTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("W4DirectoryVMTests-\(UUID().uuidString)", isDirectory: true)
        cache = W4PageCache(root: cacheRoot)
        suiteName = "DirectoryViewModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheRoot)
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        cache = nil
        cacheRoot = nil
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private static func context(uwcId: String) -> W4RequestContext {
        W4RequestContext(
            student: Student(
                studentId: uwcId,
                name: "Test Person",
                pictureId: nil,
                classLabel: nil
            ),
            credentials: W4Credentials(sessionId: "stub-session")
        )
    }

    private func makeViewModel(
        context: W4RequestContext,
        store: MemoryPeopleStore,
        fetcher: ScriptedPeopleFetcher
    ) -> DirectoryViewModel {
        let directory = DirectoryRepository(
            fetcher: fetcher,
            cache: cache,
            store: store,
            pins: DirectoryPinStore(defaults: defaults),
            context: { context }
        )
        let profiles = ProfileRepository(
            fetcher: fetcher,
            cache: cache,
            store: store,
            context: { context }
        )
        return DirectoryViewModel(directory: directory, profiles: profiles)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
    }

    // MARK: - Cache-first render

    func testStoredPeoplePaintWithoutASpinner() async {
        let seeded = [
            PeopleFixtures.person("nc00aaa", "Alex Andersen"),
            PeopleFixtures.person("nc00bbb", "Bea Beltran", year: "2")
        ]
        let store = MemoryPeopleStore(seed: seeded)
        let gate = Gate()
        // Every network answer parks, so anything on screen came from the store.
        let emptyPage = PeopleFixtures.listHTML([])
        let fetcher = ScriptedPeopleFetcher { _, _ in
            await gate.wait()
            return emptyPage
        }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: store,
            fetcher: fetcher
        )

        let load = Task { await viewModel.load(.full) }
        await waitUntil("the stored table to paint") { !viewModel.allPeople.isEmpty }

        XCTAssertEqual(viewModel.allPeople.map(\.uwcId), ["nc00aaa", "nc00bbb"])
        XCTAssertFalse(
            viewModel.isLoading,
            "A spinner is only justified by an empty screen (features.md §3)"
        )

        await gate.open()
        await load.value
    }

    func testEmptyScreenShowsTheSpinnerUntilW4Answers() async {
        let gate = Gate()
        let page = PeopleFixtures.listHTML([PeopleFixtures.person("nc00ccc", "Chris Chen")])
        let fetcher = ScriptedPeopleFetcher { route, _ in
            guard route != W4Routes.R.profile else { return "" }
            await gate.wait()
            return page
        }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(),
            fetcher: fetcher
        )

        let load = Task { await viewModel.load(.firstYear) }
        await waitUntil("the spinner") { viewModel.isLoading }

        await gate.open()
        await load.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.visiblePeople.map(\.uwcId), ["nc00ccc"])
    }

    // MARK: - Generation guard

    func testASlowAnswerCannotOverwriteANewerSelection() async {
        let gate = Gate()
        let firstYearHTML = PeopleFixtures.listHTML([
            PeopleFixtures.person("nc00aaa", "Alex Andersen", year: "1")
        ])
        let secondYearHTML = PeopleFixtures.listHTML([
            PeopleFixtures.person("nc00bbb", "Bea Beltran", year: "2")
        ])

        let fetcher = ScriptedPeopleFetcher { route, _ in
            switch route {
            case W4Routes.R.studentsFirstYear:
                await gate.wait()
                return firstYearHTML
            case W4Routes.R.studentsSecondYear:
                return secondYearHTML
            default:
                return ""
            }
        }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(),
            fetcher: fetcher
        )

        let stale = Task { await viewModel.load(.firstYear) }
        await waitUntil("the first-year request to be in flight") {
            fetcher.routes.contains(W4Routes.R.studentsFirstYear)
        }

        await viewModel.load(.secondYear)
        XCTAssertEqual(viewModel.visiblePeople.map(\.uwcId), ["nc00bbb"])

        // The selection the student already left finally answers — and must be ignored.
        await gate.open()
        await stale.value

        XCTAssertEqual(
            viewModel.visiblePeople.map(\.uwcId),
            ["nc00bbb"],
            "A response tagged with an older generation must never land"
        )
    }

    // MARK: - Errors

    func testAFailedRefreshKeepsWhatIsOnScreen() async {
        let seeded = [PeopleFixtures.person("nc00aaa", "Alex Andersen")]
        let fetcher = ScriptedPeopleFetcher { _, _ in
            throw W4Error.httpError(status: 500, route: "people/students/all")
        }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: fetcher
        )

        await viewModel.load(.full)

        XCTAssertEqual(
            viewModel.allPeople.map(\.uwcId),
            ["nc00aaa"],
            "Cached rows survive a failed refresh untouched"
        )
        XCTAssertNil(viewModel.errorMessage, "A transient failure over good data says nothing")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testAnEmptyScreenReportsTheError() async {
        let fetcher = ScriptedPeopleFetcher { _, _ in
            throw W4Error.httpError(status: 500, route: "people/students/firstyear")
        }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(),
            fetcher: fetcher
        )

        await viewModel.load(.firstYear)

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.visiblePeople.isEmpty)
    }

    func testForbiddenDoesNotLogTheStudentOut() async {
        let fetcher = ScriptedPeopleFetcher { _, _ in throw W4Error.forbidden }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(),
            fetcher: fetcher
        )

        let notified = expectation(forNotification: .w4SessionExpired, object: nil)
        notified.isInverted = true

        await viewModel.load(.staff)

        await fulfillment(of: [notified], timeout: 0.4)
        XCTAssertNotNil(
            viewModel.errorMessage,
            "Wrong role is still reported on an empty screen — just not as a logout"
        )
    }

    func testSessionExpiredDoesLogTheStudentOut() async {
        let fetcher = ScriptedPeopleFetcher { _, _ in throw W4Error.sessionExpired }
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(),
            fetcher: fetcher
        )

        let notified = expectation(forNotification: .w4SessionExpired, object: nil)

        await viewModel.load(.staff)

        await fulfillment(of: [notified], timeout: 1)
    }

    // MARK: - Pins

    func testPinsAreScopedToTheSignedInStudent() async {
        let seeded = [PeopleFixtures.person("nc00aaa", "Alex Andersen")]
        let page = PeopleFixtures.listHTML(seeded)

        let mine = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )
        await mine.load(.full)

        guard let alex = mine.person(uwcId: "nc00aaa") else {
            return XCTFail("The seeded person should be on screen")
        }
        mine.togglePin(alex)
        XCTAssertTrue(mine.isPinned(alex))

        // The write itself is a hop onto the repository actor.
        await waitUntil("the pin to reach the store") {
            self.defaults.dictionaryRepresentation().keys
                .contains { $0.hasPrefix("w4.directory.pinned.") }
        }

        let somebodyElse = makeViewModel(
            context: Self.context(uwcId: "nc99yyy"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )
        await somebodyElse.load(.full)

        XCTAssertTrue(
            somebodyElse.pinnedUwcIds.isEmpty,
            "A second account on the same device must never inherit the first one's pins"
        )
    }

    // MARK: - Search

    func testSearchPutsPinnedPeopleFirst() async {
        let seeded = [
            PeopleFixtures.person("nc00aaa", "Anna Aakre"),
            PeopleFixtures.person("nc00bbb", "Anna Berg"),
            PeopleFixtures.person("nc00ccc", "Anna Coelho")
        ]
        let page = PeopleFixtures.listHTML(seeded)
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )

        await viewModel.load(.full)
        guard let coelho = viewModel.person(uwcId: "nc00ccc") else {
            return XCTFail("The seeded person should be on screen")
        }
        viewModel.togglePin(coelho)

        viewModel.searchQuery = "anna"
        await waitUntil("debounced search results") { !viewModel.searchResults.isEmpty }

        XCTAssertEqual(viewModel.searchResults.count, 3)
        XCTAssertEqual(
            viewModel.searchResults.first?.uwcId,
            "nc00ccc",
            "A pinned person outranks alphabetical order"
        )
    }

    func testClearingTheQueryClearsTheResults() async {
        let seeded = [PeopleFixtures.person("nc00aaa", "Anna Aakre")]
        let page = PeopleFixtures.listHTML(seeded)
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )
        await viewModel.load(.full)

        viewModel.searchQuery = "anna"
        await waitUntil("debounced search results") { !viewModel.searchResults.isEmpty }

        viewModel.searchQuery = ""
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testSwitchingToTeachersHidesStudentsAndKeepsTheCatalog() async {
        let seeded = [
            PeopleFixtures.person("nc00aaa", "Alex Andersen"),
            PeopleFixtures.person("nc00ccc", "Chris Chen", kind: .staff)
        ]
        let page = PeopleFixtures.listHTML(seeded)
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )
        await viewModel.load(.full)

        XCTAssertEqual(viewModel.visiblePeople.map(\.uwcId), ["nc00aaa"])
        XCTAssertFalse(viewModel.sections.contains(where: { $0.id == "staff" }))

        await viewModel.show(.teachers)

        XCTAssertEqual(viewModel.presentation, .teachers)
        XCTAssertEqual(viewModel.visiblePeople.map(\.uwcId), ["nc00ccc"])
        XCTAssertEqual(viewModel.allPeople.map(\.uwcId).sorted(), ["nc00aaa", "nc00ccc"])

        viewModel.searchQuery = "chris"
        await waitUntil("teacher search") { !viewModel.searchResults.isEmpty }
        XCTAssertEqual(viewModel.searchResults.map(\.uwcId), ["nc00ccc"])

        viewModel.searchQuery = "alex"
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(
            viewModel.searchResults.isEmpty,
            "A student name must not appear while the Teachers slice is selected"
        )
    }

    func testSwitchingYearFilterHidesTheOtherYear() async {
        let seeded = [
            PeopleFixtures.person("nc00aaa", "Alex Andersen", year: "1"),
            PeopleFixtures.person("nc00bbb", "Bea Beltran", year: "2"),
            PeopleFixtures.person("nc00ccc", "Chris Chen", kind: .staff)
        ]
        let page = PeopleFixtures.listHTML(seeded)
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )
        await viewModel.load(.full)
        await viewModel.show(.firstYear)

        XCTAssertEqual(viewModel.presentation, .firstYear)
        XCTAssertEqual(viewModel.visiblePeople.map(\.uwcId), ["nc00aaa"])

        await viewModel.show(.teachers)
        await viewModel.showStudents()

        XCTAssertEqual(
            viewModel.presentation,
            .firstYear,
            "Students should restore the last year filter after Teachers"
        )
        XCTAssertEqual(viewModel.visiblePeople.map(\.uwcId), ["nc00aaa"])
    }

    func testRankingKeepsRepositoryOrderInsideEachBucket() {
        let people = [
            PeopleFixtures.person("nc00aaa", "Alex"),
            PeopleFixtures.person("nc00bbb", "Bea"),
            PeopleFixtures.person("nc00ccc", "Chris"),
            PeopleFixtures.person("nc00ddd", "Dana")
        ]
        let ranked = DirectoryViewModel.rank(
            people,
            pinned: ["nc00ddd"],
            classmates: ["nc00bbb"]
        )
        XCTAssertEqual(ranked.map(\.uwcId), ["nc00ddd", "nc00bbb", "nc00aaa", "nc00ccc"])
    }

    // MARK: - Demo mode

    func testDemoSessionRendersPeopleRatherThanAnError() async {
        let fetcher = ScriptedPeopleFetcher { _, _ in
            XCTFail("A demo session must never reach the network")
            return ""
        }
        let viewModel = makeViewModel(
            context: W4RequestContext(student: .demo, credentials: .empty),
            store: MemoryPeopleStore(),
            fetcher: fetcher
        )

        await viewModel.load(.full)

        XCTAssertFalse(viewModel.allPeople.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(fetcher.routes.isEmpty)
        if case .demo = viewModel.freshness {
            // expected
        } else {
            XCTFail("Demo data must be reported as demo, never as fresh")
        }
    }

    func testDemoClassmatesAreTheStudentsOwnYear() async {
        let viewModel = makeViewModel(
            context: W4RequestContext(student: .demo, credentials: .empty),
            store: MemoryPeopleStore(),
            fetcher: ScriptedPeopleFetcher { _, _ in "" }
        )

        await viewModel.load(.classmates)

        // The demo session is `nc00aaa`, a first year. Classmates are everyone else in year 1.
        let ids = viewModel.classmates.map(\.uwcId)
        XCTAssertFalse(ids.contains("nc00aaa"))
        XCTAssertTrue(ids.contains("nc00ddd"))
        XCTAssertGreaterThanOrEqual(ids.count, 4)
        XCTAssertTrue(viewModel.classmates.allSatisfy { $0.year == "1" })
    }

    // MARK: - The composer bridge

    func testTheComposerBridgeSeesTheSameW4People() async {
        let seeded = [
            PeopleFixtures.person("nc00aaa", "Alex Andersen"),
            PeopleFixtures.person("nc00ccc", "Chris Chen", kind: .staff)
        ]
        let page = PeopleFixtures.listHTML(seeded)
        let viewModel = makeViewModel(
            context: Self.context(uwcId: "nc99zzz"),
            store: MemoryPeopleStore(seed: seeded),
            fetcher: ScriptedPeopleFetcher { _, _ in page }
        )

        await viewModel.load(.full)

        let entities = viewModel.entities
        XCTAssertEqual(entities.map(\.numericID).sorted(), ["nc00aaa", "nc00ccc"])
        XCTAssertEqual(
            entities.first { $0.numericID == "nc00ccc" }?.kind,
            .teacher,
            "W4 staff arrive as the bridge's `.teacher` kind"
        )
        XCTAssertEqual(viewModel.teachers.map(\.numericID), ["nc00ccc"])
        XCTAssertEqual(
            entities.first { $0.numericID == "nc00aaa" }?.email,
            "nc00aaa@uwcrcn.no",
            "Every W4 address is derived from the uwc id"
        )
    }
}
