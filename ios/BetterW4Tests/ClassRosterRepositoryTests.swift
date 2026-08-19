//
//  ClassRosterRepositoryTests.swift
//  BetterW4Tests
//
//  The roster repository: demo never hits the network, a class brick fetches
//  `academics/classes/class&class_id=`, and a breakfast brick fetches nothing.
//

import XCTest
@testable import BetterW4

private actor StubClassRosterClient: W4SecondaryFetching {
    struct Call {
        let route: String
        let query: [String: String]
    }

    private(set) var calls: [Call] = []
    private var htmlByRoute: [String: String] = [:]
    private var failure: Error?

    func setHTML(_ html: String, forRoute route: String) {
        htmlByRoute[route] = html
    }

    func setFailure(_ error: Error?) {
        failure = error
    }

    var callCount: Int { calls.count }
    var requestedRoutes: [String] { calls.map(\.route) }
    var requestedQueries: [[String: String]] { calls.map(\.query) }

    func fetchSecondaryPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4SecondaryPage {
        calls.append(Call(route: route, query: query))
        if let failure { throw failure }
        return W4SecondaryPage(
            html: htmlByRoute[route] ?? "<html></html>",
            finalURL: W4Routes.url(route, query),
            contentType: "text/html"
        )
    }
}

final class ClassRosterRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClassRosterRepositoryTests-\(UUID().uuidString)", isDirectory: true)
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

    private func repository(
        client: StubClassRosterClient,
        context: W4RequestContext
    ) -> ClassRosterRepository {
        ClassRosterRepository(
            client: client,
            cache: cache,
            resolveContext: { context }
        )
    }

    private func event(
        href: String? = nil,
        teacherUwcId: String? = nil,
        isAllDay: Bool = false,
        source: EventSource = .academics
    ) -> TimetableEvent {
        TimetableEvent(
            id: "ac-test",
            title: "Economics",
            source: source,
            date: Date(timeIntervalSince1970: 1_787_000_000),
            teacher: "Chris Chen",
            teacherUwcId: teacherUwcId,
            isAllDay: isAllDay,
            href: href
        )
    }

    func testDemoNeverTouchesTheNetwork() async throws {
        let client = StubClassRosterClient()
        await client.setFailure(W4Error.parsingError("network should not run in demo"))
        let repo = repository(client: client, context: demo)
        let loaded = try await repo.people(
            for: event(href: "/index.php?r=academics/classes/class&class_id=1EA16CECOX")
        )
        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertFalse(loaded.value.isEmpty)
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    func testClassBrickFetchesTheClassPage() async throws {
        let client = StubClassRosterClient()
        let html = try fixture("class-mtaa")
        await client.setHTML(html, forRoute: W4Routes.R.classPage)
        let repo = repository(client: client, context: signedIn)
        let loaded = try await repo.people(
            for: event(href: "/index.php?r=academics/classes/class&class_id=1DA13HMTAA")
        )
        XCTAssertEqual(loaded.value.map(\.uwcId), ["nc00jjen", "nc00aaa", "nc00bbb", "nc00ccc"])
        let routes = await client.requestedRoutes
        XCTAssertEqual(routes, [W4Routes.R.classPage])
        let queries = await client.requestedQueries
        XCTAssertEqual(queries, [["class_id": "1DA13HMTAA"]])
    }

    func testBreakfastDoesNotFetch() async throws {
        let client = StubClassRosterClient()
        await client.setFailure(W4Error.parsingError("breakfast has no roster"))
        let repo = repository(client: client, context: signedIn)
        let loaded = try await repo.people(for: event(href: nil, isAllDay: false))
        XCTAssertTrue(loaded.value.isEmpty)
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    func testTeacherFallbackWhenThereIsNoClassPage() async throws {
        let client = StubClassRosterClient()
        await client.setFailure(W4Error.parsingError("no class"))
        let repo = repository(client: client, context: signedIn)
        let loaded = try await repo.people(for: event(teacherUwcId: "nc00ccc"))
        XCTAssertEqual(loaded.value.map(\.uwcId), ["nc00ccc"])
        XCTAssertEqual(loaded.value.first?.kind, .staff)
        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
