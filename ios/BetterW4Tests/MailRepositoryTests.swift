//
//  MailRepositoryTests.swift
//  BetterW4Tests
//
//  Covers `MailRepository`, `MailFileCache`, `AttachmentCache` and `MessageListPrefetcher`
//  (Wave 5 item 5.3).
//
//  ── WHAT THESE TESTS DO AND DO NOT PROVE ──────────────────────────────────────────────────
//
//  The HTML they feed the repository is `BetterW4Tests/Fixtures/W4/mailer-*.html`, which is
//  **[I] SYNTHESIZED** — no `index.php?r=mailer/*` page has ever been captured (parsers.md §7,
//  reviewer-notes §7, plan OQ-4). So nothing here verifies W4.
//
//  What they do verify is the repository's own contract, which holds whatever the real markup
//  turns out to be:
//    * a demo session never reaches the transport, not once, on any entry point;
//    * a list inside its TTL is served from disk with no request, and refetches once it lapses;
//    * a list and a message body both survive "relaunch" — a fresh repository over the same
//      cache directories, with a transport that refuses to answer;
//    * a message body never expires, even a decade later;
//    * a failed refresh over a warm cache returns the cached copy…
//    * …except `W4Error.sessionExpired`, which propagates through it, while `W4Error.forbidden`
//      does not (reviewer-notes §3: a student opening a staff-only page must not be logged out);
//    * markup the parser cannot read never replaces a good cached copy;
//    * clearing the cache empties lists *and* bodies;
//    * a prefetch reaches the transport at `.opportunistic`, never `.important`;
//    * the attachment cache evicts the least recently used first, by file count and by bytes.
//
//  No test here touches the network: `StubMailTransport` is the only transport in the file, and
//  the request context is injected as a closure so the Keychain is never read either.
//

import XCTest
@testable import BetterW4

// MARK: - Test doubles

/// Records every request and answers from a script. `@unchecked Sendable` with a lock because the
/// repository is an actor and calls in from whatever executor the test task lands on.
private final class StubMailTransport: MailPageFetching, @unchecked Sendable {

    struct Call {
        let route: String
        let query: [String: String]
        let priority: String
    }

    enum Answer {
        case html(String)
        case failure(Error)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _answer: Answer
    private var _fileAnswer: Result<Data, Error>
    private var _fileCallCount = 0

    init(answer: Answer = .html(""), file: Result<Data, Error> = .success(Data())) {
        _answer = answer
        _fileAnswer = file
    }

    var calls: [Call] { lock.withLock { _calls } }
    var callCount: Int { calls.count }
    var fileCallCount: Int { lock.withLock { _fileCallCount } }

    func answer(with answer: Answer) {
        lock.withLock { _answer = answer }
    }

    func fetchMailPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (html: String, finalURL: URL) {
        let answer = recordPage(route: route, query: query, priority: priority)
        switch answer {
        case .html(let html):
            return (html, W4Routes.url(route, query))
        case .failure(let error):
            throw error
        }
    }

    func fetchMailFile(
        url: URL,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> Data {
        try recordFile().get()
    }

    // Locking lives in synchronous helpers: `NSLock.lock()` is unavailable from an async context.

    private func recordPage(route: String, query: [String: String], priority: FetchPriority) -> Answer {
        lock.withLock {
            _calls.append(Call(route: route, query: query, priority: Self.name(of: priority)))
            return _answer
        }
    }

    private func recordFile() -> Result<Data, Error> {
        lock.withLock {
            _fileCallCount += 1
            return _fileAnswer
        }
    }

    /// `FetchPriority` is compared by name so the assertion does not depend on the enum gaining
    /// (or losing) a synthesized `Equatable`.
    static func name(of priority: FetchPriority) -> String {
        switch priority {
        case .important: return "important"
        case .opportunistic: return "opportunistic"
        }
    }
}

/// A clock the test moves by hand, so TTL expiry and LRU ordering are deterministic instead of
/// depending on how fast the machine runs.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_770_000_000)) {
        value = start
    }

    var now: Date { lock.withLock { value } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(seconds) }
    }
}

// MARK: - Tests

final class MailRepositoryTests: XCTestCase {

    private var scratch: URL!
    private var mailRoot: URL!
    private var pageRoot: URL!
    private var attachmentRoot: URL!
    private var clock: TestClock!

    private static let uwcId = "nc26abcd"

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        mailRoot = scratch.appendingPathComponent("MailCache", isDirectory: true)
        pageRoot = scratch.appendingPathComponent("W4Pages", isDirectory: true)
        attachmentRoot = scratch.appendingPathComponent("Attachments", isDirectory: true)
        clock = TestClock()
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
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

    private static func realContext() -> W4RequestContext {
        W4RequestContext(
            student: Student(
                studentId: uwcId,
                name: "Alex Andersen",
                pictureId: nil,
                classLabel: nil
            ),
            credentials: W4Credentials(sessionId: "phpsessid-for-tests")
        )
    }

    private static func demoContext() -> W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    /// A repository over this test's scratch directories. Every dependency is injected: no
    /// Keychain, no shared caches, no network.
    private func makeRepository(
        transport: StubMailTransport,
        context: W4RequestContext? = nil,
        attachmentLimits: (bytes: Int64, files: Int) = (50 * 1_024 * 1_024, 100)
    ) -> MailRepository {
        let resolved = context ?? Self.realContext()
        let clock = self.clock!
        return MailRepository(
            transport: transport,
            store: MailFileCache(root: mailRoot),
            pageCache: W4PageCache(root: pageRoot),
            attachments: AttachmentCache(
                root: attachmentRoot,
                maximumByteCount: attachmentLimits.bytes,
                maximumFileCount: attachmentLimits.files,
                now: { clock.now }
            ),
            resolveContext: { resolved },
            now: { clock.now }
        )
    }

    // MARK: - Demo mode (hard rule: never a request)

    func testDemoSessionNeverReachesTheTransport() async throws {
        let transport = StubMailTransport(answer: .failure(W4Error.noResponse))
        let repository = makeRepository(transport: transport, context: Self.demoContext())

        let inbox = try await repository.list(folder: .inbox)
        let archive = try await repository.list(folder: .archive)
        let body = try await repository.message(id: "demo-mail-1")
        let cachedList = await repository.cachedList(folder: .inbox)
        let unread = await repository.unreadCount()

        XCTAssertEqual(transport.callCount, 0, "a demo session must never make a request")
        XCTAssertEqual(inbox.freshness, .demo)
        XCTAssertEqual(archive.freshness, .demo)
        XCTAssertEqual(body.freshness, .demo)
        XCTAssertEqual(cachedList?.freshness, .demo)
        XCTAssertFalse(inbox.value.messages.isEmpty, "demo mail must not be an empty screen")
        XCTAssertFalse(body.value.bodyHTML.isEmpty)
        XCTAssertEqual(unread, 1)
    }

    func testDemoAttachmentIsServedFromDiskWithoutADownload() async throws {
        let transport = StubMailTransport(answer: .failure(W4Error.noResponse))
        let repository = makeRepository(transport: transport, context: Self.demoContext())

        let url = try await repository.attachmentFile(for: MailDemoData.demoAttachment)

        XCTAssertEqual(transport.fileCallCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasSuffix("demo-note.txt"))
    }

    // MARK: - Fetch, parse, cache

    func testInboxFetchIsParsedAndReturnedFresh() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)

        let loaded = try await repository.list(folder: .inbox)

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.outcome, .parsed)
        XCTAssertEqual(loaded.value.messages.map(\.id), ["12", "7"])
        XCTAssertEqual(transport.calls.map(\.route), [W4Routes.R.mailerInbox])
    }

    func testArchiveUsesItsOwnRouteAndItsOwnCacheKey() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-archive")))
        let repository = makeRepository(transport: transport)

        let archive = try await repository.list(folder: .archive)

        XCTAssertEqual(archive.value.folder.id, MailFolder.archive.id)
        XCTAssertEqual(transport.calls.map(\.route), [W4Routes.R.mailerArchive])
        XCTAssertEqual(MailRepository.surface(for: .archive), .mailArchive)
        XCTAssertEqual(MailRepository.surface(for: .inbox), .mailInbox)
        // The archive must not have overwritten (or been read as) the inbox.
        let cachedInbox = await MailFileCache(root: mailRoot).list(folderID: MailFolder.inbox.id, uwcId: Self.uwcId)
        XCTAssertNil(cachedInbox)
    }

    func testMessageBodyIsFetchedWithTheIdAsAQueryParameter() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-view")))
        let repository = makeRepository(transport: transport)

        let loaded = try await repository.message(id: "12")

        XCTAssertEqual(loaded.freshness, .fresh)
        XCTAssertEqual(loaded.value.id, "12")
        XCTAssertEqual(loaded.value.subject, "Welcome to term 1")
        XCTAssertFalse(loaded.value.bodyHTML.isEmpty)
        XCTAssertEqual(transport.calls.first?.route, W4Routes.R.mailerView)
        XCTAssertEqual(transport.calls.first?.query["id"], "12")
    }

    // MARK: - TTL

    func testFreshListIsServedFromCacheWithoutASecondRequest() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)

        _ = try await repository.list(folder: .inbox)
        clock.advance(60)                                   // still inside the 5-minute TTL
        let second = try await repository.list(folder: .inbox)

        XCTAssertEqual(transport.callCount, 1, "a fresh cached list must not hit the network")
        XCTAssertEqual(second.freshness, .cached(fetchedAt: clock.now.addingTimeInterval(-60), isStale: false))
        XCTAssertEqual(second.value.messages.map(\.id), ["12", "7"])
    }

    func testListIsRefetchedOnceItsTTLLapses() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)

        _ = try await repository.list(folder: .inbox)
        clock.advance(CachePolicy.ttl(for: .mailInbox) + 1)
        let second = try await repository.list(folder: .inbox)

        XCTAssertEqual(transport.callCount, 2)
        XCTAssertEqual(second.freshness, .fresh)
    }

    func testForceRefreshIgnoresAFreshCache() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)

        _ = try await repository.list(folder: .inbox)
        _ = try await repository.list(folder: .inbox, forceRefresh: true)

        XCTAssertEqual(transport.callCount, 2)
    }

    // MARK: - Survives relaunch (the item's "Done" criterion)

    func testListSurvivesRelaunchWithNoNetwork() async throws {
        let online = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        _ = try await makeRepository(transport: online).list(folder: .inbox)

        // "Relaunch": a brand-new repository, brand-new cache objects, same directories on disk,
        // and a transport that cannot answer.
        let offline = StubMailTransport(answer: .failure(URLError(.notConnectedToInternet)))
        let relaunched = makeRepository(transport: offline)
        clock.advance(CachePolicy.ttl(for: .mailInbox) + 60)  // and the copy is stale by now

        let loaded = try await relaunched.list(folder: .inbox)

        XCTAssertEqual(loaded.value.messages.map(\.id), ["12", "7"])
        XCTAssertTrue(loaded.freshness.isFromCache)
        if case .cached(_, let isStale) = loaded.freshness {
            XCTAssertTrue(isStale, "the copy is past its TTL and the UI must be told")
        } else {
            XCTFail("expected the cached list")
        }
        XCTAssertEqual(offline.callCount, 1, "it tried, failed, and fell back — it did not skip the refresh")
    }

    func testMessageBodySurvivesRelaunchAndNeverExpires() async throws {
        let online = StubMailTransport(answer: .html(try fixture("mailer-view")))
        _ = try await makeRepository(transport: online).message(id: "12")

        let offline = StubMailTransport(answer: .failure(URLError(.notConnectedToInternet)))
        let relaunched = makeRepository(transport: offline)
        clock.advance(10 * 365 * 24 * 60 * 60)               // a decade later

        let loaded = try await relaunched.message(id: "12")

        XCTAssertEqual(offline.callCount, 0, "a sent message cannot change; it must never be refetched")
        XCTAssertEqual(loaded.value.subject, "Welcome to term 1")
        XCTAssertFalse(loaded.value.bodyHTML.isEmpty)
        XCTAssertEqual(loaded.freshness.isFromCache, true)
        if case .cached(_, let isStale) = loaded.freshness {
            XCTAssertFalse(isStale, "an immutable body is never stale")
        } else {
            XCTFail("expected a cached body")
        }
    }

    func testCachedAccessorsReadDiskWithoutAnyRequest() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)
        let beforeAnything = await repository.cachedList(folder: .inbox)
        XCTAssertNil(beforeAnything, "nothing cached yet")

        _ = try await repository.list(folder: .inbox)
        let cached = await repository.cachedList(folder: .inbox)

        XCTAssertEqual(transport.callCount, 1)
        XCTAssertEqual(cached?.value.messages.count, 2)
    }

    // MARK: - Failure policy

    func testSessionExpiryPropagatesEvenWithAWarmCache() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)
        _ = try await repository.list(folder: .inbox)
        transport.answer(with: .failure(W4Error.sessionExpired))

        do {
            _ = try await repository.list(folder: .inbox, forceRefresh: true)
            XCTFail("a dead session must never be swallowed by the cache fallback")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    func testSessionExpiryPropagatesFromTheMessageBodyPathToo() async throws {
        let transport = StubMailTransport(answer: .failure(W4Error.sessionExpired))
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.message(id: "12")
            XCTFail("expected .sessionExpired")
        } catch let error as W4Error {
            guard case .sessionExpired = error else {
                return XCTFail("expected .sessionExpired, got \(error)")
            }
        }
    }

    /// reviewer-notes §3: 403 without "Login Required" is the wrong role, not a dead session.
    func testForbiddenFallsBackToTheCachedCopy() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)
        _ = try await repository.list(folder: .inbox)
        transport.answer(with: .failure(W4Error.forbidden))

        let loaded = try await repository.list(folder: .inbox, forceRefresh: true)

        XCTAssertTrue(loaded.freshness.isFromCache)
        XCTAssertEqual(loaded.value.messages.count, 2)
    }

    func testFailureWithNothingCachedThrows() async throws {
        let transport = StubMailTransport(answer: .failure(W4Error.httpError(status: 500, route: "mailer/inbox")))
        let repository = makeRepository(transport: transport)

        do {
            _ = try await repository.list(folder: .inbox)
            XCTFail("with an empty cache there is nothing to fall back to")
        } catch let error as W4Error {
            guard case .httpError(let status, _) = error else {
                return XCTFail("expected .httpError, got \(error)")
            }
            XCTAssertEqual(status, 500)
        }
    }

    func testCancellationIsNotSwallowedByTheCacheFallback() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)
        _ = try await repository.list(folder: .inbox)
        transport.answer(with: .failure(CancellationError()))

        do {
            _ = try await repository.list(folder: .inbox, forceRefresh: true)
            XCTFail("a cancelled task has no caller left to serve")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Poison-cache guards

    func testUnreadableMarkupIsNeverCached() async throws {
        let transport = StubMailTransport(answer: .html("<html><body><p>Not a grid at all.</p></body></html>"))
        let repository = makeRepository(transport: transport)

        let loaded = try await repository.list(folder: .inbox)

        XCTAssertEqual(loaded.value.outcome, .unrecognised)
        let cached = await MailFileCache(root: mailRoot).list(folderID: MailFolder.inbox.id, uwcId: Self.uwcId)
        XCTAssertNil(cached, "unrecognised markup must not become the cached inbox")
    }

    func testUnreadableMarkupDoesNotReplaceAGoodCachedList() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)
        _ = try await repository.list(folder: .inbox)

        transport.answer(with: .html("<html><body><p>W4 moved the markup.</p></body></html>"))
        _ = try await repository.list(folder: .inbox, forceRefresh: true)

        let cached = await MailFileCache(root: mailRoot).list(folderID: MailFolder.inbox.id, uwcId: Self.uwcId)
        XCTAssertEqual(cached?.messages.map(\.id), ["12", "7"])
    }

    /// W4 says "no results": that IS the mailbox, and it must be cached.
    func testGenuineEmptyStateIsCached() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-empty")))
        let repository = makeRepository(transport: transport)

        let loaded = try await repository.list(folder: .inbox)

        XCTAssertEqual(loaded.value.outcome, .emptyState)
        let cached = await MailFileCache(root: mailRoot).list(folderID: MailFolder.inbox.id, uwcId: Self.uwcId)
        XCTAssertEqual(cached?.outcome, .emptyState)
    }

    // MARK: - Clearing

    func testClearCacheEmptiesBothTheListAndTheBody() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)
        _ = try await repository.list(folder: .inbox)
        transport.answer(with: .html(try fixture("mailer-view")))
        _ = try await repository.message(id: "12")

        await repository.clearCache()

        let store = MailFileCache(root: mailRoot)
        let cachedList = await store.list(folderID: MailFolder.inbox.id, uwcId: Self.uwcId)
        let cachedBody = await store.message(id: "12", uwcId: Self.uwcId)
        let listThroughRepository = await repository.cachedList(folder: .inbox)
        let bodyThroughRepository = await repository.cachedMessage(id: "12")
        let cachedHTML = await W4PageCache(root: pageRoot)
            .page(surface: .mailInbox, key: MailFolder.inbox.id, uwcId: Self.uwcId)

        XCTAssertNil(cachedList)
        XCTAssertNil(cachedBody)
        XCTAssertNil(listThroughRepository)
        XCTAssertNil(bodyThroughRepository)
        XCTAssertNil(cachedHTML, "the cached HTML page must go too")
    }

    // MARK: - Unread badge

    func testWritingTheInboxPublishesTheUnreadBadge() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)

        let expectation = XCTNSNotificationExpectation(name: .unreadMessageCountDidChange)
        expectation.handler = { note in
            guard note.userInfo?["studentId"] as? String == Self.uwcId else { return false }
            return note.userInfo?["count"] as? Int == 1
        }

        _ = try await repository.list(folder: .inbox)

        await fulfillment(of: [expectation], timeout: 2)
        let unread = await repository.unreadCount()
        XCTAssertEqual(unread, 1, "the fixture carries exactly one tr.unread row")
    }

    // MARK: - Prefetch priority

    func testPrefetchAlwaysRunsAtOpportunisticPriority() async throws {
        let transport = StubMailTransport(answer: .html(try fixture("mailer-inbox")))
        let repository = makeRepository(transport: transport)

        await MessageListPrefetcher.prefetchNow(force: true, using: repository)

        XCTAssertEqual(transport.calls.count, 1)
        XCTAssertEqual(transport.calls.first?.route, W4Routes.R.mailerInbox)
        XCTAssertEqual(
            transport.calls.map(\.priority),
            ["opportunistic"],
            "a prefetch must never queue ahead of the screen the student is looking at"
        )
        XCTAssertEqual(StubMailTransport.name(of: MessageListPrefetcher.priority), "opportunistic")
    }

    func testPrefetchSwallowsFailuresAndRespectsTheTTL() async throws {
        let transport = StubMailTransport(answer: .failure(W4Error.httpError(status: 500, route: "mailer/inbox")))
        let repository = makeRepository(transport: transport)

        await MessageListPrefetcher.prefetchNow(force: false, using: repository)   // must not throw
        XCTAssertEqual(transport.callCount, 1)

        transport.answer(with: .html(try fixture("mailer-inbox")))
        await MessageListPrefetcher.prefetchNow(force: false, using: repository)
        XCTAssertEqual(transport.callCount, 2)

        // Now the inbox is fresh: an unforced prefetch must not spend a request on it.
        await MessageListPrefetcher.prefetchNow(force: false, using: repository)
        XCTAssertEqual(transport.callCount, 2)
    }

    // MARK: - Attachments

    func testAttachmentIsDownloadedOnceAndServedFromDiskAfterwards() async throws {
        let transport = StubMailTransport(
            answer: .html(""),
            file: .success(Data("%PDF-1.4 demo".utf8))
        )
        let repository = makeRepository(transport: transport)
        let attachment = MailAttachment(
            id: "91",
            name: "term-1-schedule.pdf",
            url: "/index.php?r=mailer/download&attachment_id=91"
        )

        let first = try await repository.attachmentFile(for: attachment)
        let second = try await repository.attachmentFile(for: attachment)

        XCTAssertEqual(first, second)
        XCTAssertEqual(transport.fileCallCount, 1, "the second open must come from the cache")
        XCTAssertEqual(try Data(contentsOf: first), Data("%PDF-1.4 demo".utf8))
        XCTAssertTrue(first.lastPathComponent.hasSuffix("__term-1-schedule.pdf"))
    }
}

// MARK: - Attachment cache

final class AttachmentCacheTests: XCTestCase {

    private var root: URL!
    private var clock: TestClock!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentCacheTests-\(UUID().uuidString)", isDirectory: true)
        clock = TestClock()
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func makeCache(bytes: Int64 = 50 * 1_024 * 1_024, files: Int = 100) -> AttachmentCache {
        let clock = self.clock!
        return AttachmentCache(
            root: root,
            maximumByteCount: bytes,
            maximumFileCount: files,
            now: { clock.now }
        )
    }

    func testEvictsTheLeastRecentlyUsedWhenTheFileCeilingIsCrossed() async throws {
        let cache = makeCache(files: 3)

        for index in 1...3 {
            _ = await cache.store(Data("file \(index)".utf8), for: "https://w4.uwcrcn.no/f\(index)", name: "f\(index).txt")
            clock.advance(10)
        }
        // Touch the oldest so it is no longer the least recently used.
        _ = await cache.file(for: "https://w4.uwcrcn.no/f1", name: "f1.txt")
        clock.advance(10)

        _ = await cache.store(Data("file 4".utf8), for: "https://w4.uwcrcn.no/f4", name: "f4.txt")

        let count = await cache.fileCount()
        XCTAssertEqual(count, 3)
        let hasF1 = await cache.contains("https://w4.uwcrcn.no/f1", name: "f1.txt")
        let hasF2 = await cache.contains("https://w4.uwcrcn.no/f2", name: "f2.txt")
        let hasF3 = await cache.contains("https://w4.uwcrcn.no/f3", name: "f3.txt")
        let hasF4 = await cache.contains("https://w4.uwcrcn.no/f4", name: "f4.txt")
        XCTAssertTrue(hasF1, "f1 was read most recently, so it survives")
        XCTAssertFalse(hasF2, "f2 was the least recently used")
        XCTAssertTrue(hasF3)
        XCTAssertTrue(hasF4)
    }

    func testEvictsByByteBudgetOldestFirst() async throws {
        let cache = makeCache(bytes: 3_000)
        let kilobyte = Data(repeating: 0x41, count: 1_000)

        for index in 1...3 {
            _ = await cache.store(kilobyte, for: "https://w4.uwcrcn.no/big\(index)", name: "big\(index).bin")
            clock.advance(10)
        }
        var size = await cache.sizeInBytes()
        XCTAssertEqual(size, 3_000)

        _ = await cache.store(kilobyte, for: "https://w4.uwcrcn.no/big4", name: "big4.bin")

        size = await cache.sizeInBytes()
        XCTAssertLessThanOrEqual(size, 3_000)
        let oldest = await cache.contains("https://w4.uwcrcn.no/big1", name: "big1.bin")
        let newest = await cache.contains("https://w4.uwcrcn.no/big4", name: "big4.bin")
        XCTAssertFalse(oldest, "the oldest file pays for the newest")
        XCTAssertTrue(newest, "the file just written is never the victim")
    }

    func testTheFileJustWrittenSurvivesEvenWhenItAloneBreaksTheBudget() async throws {
        let cache = makeCache(bytes: 500)

        let url = await cache.store(Data(repeating: 0x42, count: 2_000), for: "https://w4.uwcrcn.no/huge", name: "huge.bin")

        XCTAssertNotNil(url)
        let exists = await cache.contains("https://w4.uwcrcn.no/huge", name: "huge.bin")
        XCTAssertTrue(exists, "handing back a URL we just deleted would be worse than being over budget")
    }

    func testCacheDirectoryIsExcludedFromBackup() async throws {
        let cache = makeCache()
        _ = await cache.store(Data("x".utf8), for: "https://w4.uwcrcn.no/x", name: "x.txt")

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "downloaded mail has no business in iCloud")
    }

    func testClearRemovesEverything() async throws {
        let cache = makeCache()
        _ = await cache.store(Data("a".utf8), for: "https://w4.uwcrcn.no/a", name: "a.txt")
        _ = await cache.store(Data("b".utf8), for: "https://w4.uwcrcn.no/b", name: "b.txt")

        await cache.clear()

        let count = await cache.fileCount()
        XCTAssertEqual(count, 0)
        let size = await cache.sizeInBytes()
        XCTAssertEqual(size, 0)
    }

    func testDistinctURLsWithTheSameFileNameDoNotCollide() async throws {
        let cache = makeCache()

        let first = await cache.store(Data("one".utf8), for: "https://w4.uwcrcn.no/a/handbook.pdf", name: "handbook.pdf")
        let second = await cache.store(Data("two".utf8), for: "https://w4.uwcrcn.no/b/handbook.pdf", name: "handbook.pdf")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(first)), Data("one".utf8))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(second)), Data("two".utf8))
    }

    func testFileNamesAreSanitisedAndBounded() {
        XCTAssertEqual(AttachmentCache.sanitised("term 1/schedule.pdf"), "term_1_schedule.pdf")
        XCTAssertFalse(AttachmentCache.sanitised("../../etc/passwd").contains("/"), "no path traversal")
        XCTAssertFalse(AttachmentCache.sanitised("../../etc/passwd").hasPrefix("."), "no hidden file")
        XCTAssertEqual(AttachmentCache.sanitised(""), "file")
        let long = AttachmentCache.sanitised(String(repeating: "n", count: 400) + ".pdf")
        XCTAssertLessThanOrEqual(long.count, 80)
        XCTAssertTrue(long.hasSuffix(".pdf"))
    }
}

// MARK: - Mail file cache

final class MailFileCacheTests: XCTestCase {

    private var root: URL!
    private static let uwcId = "nc26abcd"

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailFileCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func page(unread: Bool = true) -> MailListPage {
        MailListPage(
            folder: .inbox,
            messages: [
                MailMessage(id: "12", folderID: "inbox", subject: "Welcome", from: "House Leader", isUnread: unread),
                MailMessage(id: "7", folderID: "inbox", subject: "Kitchen booking", from: "W4 Mailer")
            ],
            pagination: MailPagination(hasMorePages: true, currentPage: 1, pageCount: 3, summary: "Displaying 1-2 of 5 results."),
            outcome: .parsed,
            columns: MailColumnLayout(headers: ["received", "from", "subject"], received: 0, from: 1, subject: 2)
        )
    }

    func testSnapshotRoundTripsIncludingPaginationAndColumns() async throws {
        let cache = MailFileCache(root: root)
        let fetchedAt = Date(timeIntervalSince1970: 1_770_000_000)

        await cache.storeList(MailListSnapshot(page: page(), fetchedAt: fetchedAt), uwcId: Self.uwcId)
        let restored = await cache.list(folderID: "inbox", uwcId: Self.uwcId)

        XCTAssertEqual(restored?.fetchedAt, fetchedAt)
        XCTAssertEqual(restored?.page(folder: .inbox), page())
        XCTAssertEqual(restored?.unreadCount, 1)
    }

    func testMessageBodyRoundTrips() async throws {
        let cache = MailFileCache(root: root)
        let detail = MailMessageDetail(
            id: "12",
            subject: "Welcome",
            from: "House Leader",
            recipients: ["Alex Andersen"],
            sentAt: Date(timeIntervalSince1970: 1_770_000_000),
            bodyHTML: "<p>Hello</p>",
            attachments: [MailAttachment(id: "91", name: "a.pdf", url: "/index.php?r=mailer/download&attachment_id=91")]
        )

        await cache.storeMessage(MailMessageSnapshot(detail: detail, fetchedAt: Date(timeIntervalSince1970: 1)), uwcId: Self.uwcId)
        let restored = await cache.message(id: "12", uwcId: Self.uwcId)

        XCTAssertEqual(restored?.detail, detail)
    }

    func testScopingKeepsOneStudentsMailOutOfAnothers() async throws {
        let cache = MailFileCache(root: root)
        await cache.storeList(MailListSnapshot(page: page(), fetchedAt: Date()), uwcId: Self.uwcId)

        let other = await cache.list(folderID: "inbox", uwcId: "nc26zzzz")

        XCTAssertNil(other)
    }

    func testClearingOneStudentLeavesTheOtherAlone() async throws {
        let cache = MailFileCache(root: root)
        await cache.storeList(MailListSnapshot(page: page(), fetchedAt: Date()), uwcId: Self.uwcId)
        await cache.storeList(MailListSnapshot(page: page(), fetchedAt: Date()), uwcId: "nc26zzzz")

        await cache.clear(uwcId: Self.uwcId)

        let cleared = await cache.list(folderID: "inbox", uwcId: Self.uwcId)
        let untouched = await cache.list(folderID: "inbox", uwcId: "nc26zzzz")
        XCTAssertNil(cleared)
        XCTAssertNotNil(untouched)
    }

    /// Subjects and ids are user data: they must never appear as path components.
    func testIdentifiersAreBase64EncodedIntoFileNames() {
        let encoded = MailFileCache.safeComponent("nc26abcd")
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("nc26abcd"))
    }

    func testCacheDirectoryIsExcludedFromBackup() async throws {
        let cache = MailFileCache(root: root)
        await cache.storeList(MailListSnapshot(page: page(), fetchedAt: Date()), uwcId: Self.uwcId)

        let directory = root.appendingPathComponent(MailFileCache.safeComponent(Self.uwcId), isDirectory: true)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
