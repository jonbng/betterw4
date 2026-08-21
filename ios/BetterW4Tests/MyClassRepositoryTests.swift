//
//  MyClassRepositoryTests.swift
//  BetterW4Tests
//
//  Demo never hits the network. A signed-in session fetches My classes, then
//  a class page under the same cache key the roster uses.
//

import XCTest
@testable import BetterW4

private actor StubMyClassClient: W4SecondaryFetching {
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

final class MyClassRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClassRepositoryTests-\(UUID().uuidString)", isDirectory: true)
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
        client: StubMyClassClient,
        context: W4RequestContext
    ) -> MyClassRepository {
        MyClassRepository(
            client: client,
            cache: cache,
            resolveContext: { context }
        )
    }

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDemoNeverTouchesTheNetwork() async throws {
        let client = StubMyClassClient()
        await client.setFailure(W4Error.parsingError("network should not run in demo"))
        let repo = repository(client: client, context: demo)

        let index = try await repo.loadIndex()
        XCTAssertEqual(index.freshness, .demo)
        XCTAssertFalse(index.value.isEmpty)
        XCTAssertTrue(index.value.contains { $0.id == "1DA13HMTAA" })
        XCTAssertTrue(index.value.allSatisfy { !$0.loaded })

        let detail = try await repo.loadClass(id: "1DA13HMTAA")
        XCTAssertEqual(detail.freshness, .demo)
        XCTAssertTrue(detail.value.loaded)
        XCTAssertFalse(detail.value.students.isEmpty)
        XCTAssertTrue(detail.value.students.contains { $0.id == DemoDataProvider.uwcId })

        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    func testIndexFetchesMyClasses() async throws {
        let client = StubMyClassClient()
        await client.setHTML(try fixture("myclasses"), forRoute: W4Routes.R.myClasses)
        let repo = repository(client: client, context: signedIn)

        let loaded = try await repo.loadIndex()
        XCTAssertEqual(
            loaded.value.map(\.id),
            ["1ZAUDXCORE", "1EA16CECOX", "1YA25SLALI", "1DA13HMTAA"]
        )
        let routes = await client.requestedRoutes
        XCTAssertEqual(routes, [W4Routes.R.myClasses])
    }

    func testClassPageUsesTheRosterCacheKey() async throws {
        let client = StubMyClassClient()
        await client.setHTML(try fixture("class-mtaa"), forRoute: W4Routes.R.classPage)
        let repo = repository(client: client, context: signedIn)

        let loaded = try await repo.loadClass(id: "1DA13HMTAA")
        XCTAssertEqual(loaded.value.subject, "Mathematics Analysis and Approaches")
        XCTAssertEqual(loaded.value.teachers.map(\.id), ["nc00jjen"])
        let routes = await client.requestedRoutes
        XCTAssertEqual(routes, [W4Routes.R.classPage])
        let queries = await client.requestedQueries
        XCTAssertEqual(queries, [["class_id": "1DA13HMTAA"]])

        let cached = await repo.cachedClass(id: "1DA13HMTAA")
        XCTAssertEqual(cached?.value.id, "1DA13HMTAA")
    }
}
