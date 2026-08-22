//
//  MyTeacherRepositoryTests.swift
//  BetterW4Tests
//
//  Demo never hits the network. A signed-in session fetches My teachers.
//

import XCTest
@testable import BetterW4

private actor StubMyTeacherClient: W4SecondaryFetching {
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

final class MyTeacherRepositoryTests: XCTestCase {

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyTeacherRepositoryTests-\(UUID().uuidString)", isDirectory: true)
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
        client: StubMyTeacherClient,
        context: W4RequestContext
    ) -> MyTeacherRepository {
        MyTeacherRepository(
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
        let client = StubMyTeacherClient()
        await client.setFailure(W4Error.parsingError("network should not run in demo"))
        let repo = repository(client: client, context: demo)

        let loaded = try await repo.load()
        XCTAssertEqual(loaded.freshness, .demo)
        XCTAssertFalse(loaded.value.isEmpty)
        XCTAssertTrue(loaded.value.contains { $0.id == "nc00ccc" })
        XCTAssertTrue(loaded.value.allSatisfy { $0.person.kind == .staff })

        let calls = await client.callCount
        XCTAssertEqual(calls, 0)
    }

    func testFetchesUnfilteredStaffPage() async throws {
        let client = StubMyTeacherClient()
        await client.setHTML(try fixture("myteachers"), forRoute: W4Routes.R.staff)
        let repo = repository(client: client, context: signedIn)

        let loaded = try await repo.load()
        XCTAssertEqual(
            loaded.value.map(\.id),
            ["nc00aore", "nc00ccc", "nc00lbro", "wk00lbon", "nc00fff", "nc00mons", "nc00pszy"]
        )
        let routes = await client.requestedRoutes
        XCTAssertEqual(routes, [W4Routes.R.staff])

        let cached = await repo.cached()
        XCTAssertEqual(cached?.value.first?.id, "nc00aore")
    }
}
