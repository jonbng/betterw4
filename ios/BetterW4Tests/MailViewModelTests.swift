//
//  MailViewModelTests.swift
//  BetterW4Tests
//
//  Covers the Mail tab's view models — `MessagesViewModel`, `MailMessageViewModel` and
//  `ComposeMessageViewModel` (Wave 6 item 6.2).
//
//  ── WHAT THESE TESTS DO AND DO NOT PROVE ──────────────────────────────────────────────────
//
//  The HTML below is **[I] SYNTHESIZED**, hand-written from the Yii 1 CGridView convention and
//  README §6's column labels. No `index.php?r=mailer/*` page has ever been captured (plan OQ-4).
//  Nothing here verifies W4.
//
//  What it does verify is the behaviour contract from `docs/spec/features.md` §3, which holds
//  whatever the real markup turns out to be:
//    * cache-first render, then a background refresh;
//    * a spinner only when there is nothing cached to show;
//    * a stale response for an older folder can never overwrite a newer selection;
//    * a failed refresh over a warm cache leaves the rows alone and raises no error;
//    * `W4Error.sessionExpired` logs the student out, `W4Error.forbidden` emphatically does not;
//    * a demo session never reaches the transport, on any screen;
//    * compose is honestly disabled rather than faking a successful send.
//
//  No test here touches the network or the Keychain: the transport is a stub and the request
//  context is injected as a closure.
//

import XCTest
@testable import BetterW4

// MARK: - Synthesized pages

private enum MailPageFixture {

    static func inbox(unreadFirstRow: Bool = true) -> String {
        page(
            headers: ["Received", "From", "Subject"],
            rows: [
                """
                <tr class="odd\(unreadFirstRow ? " unread" : "")">
                    <td>14-Aug-2026 12:04</td>
                    <td>House Leader</td>
                    <td><a href="/index.php?r=mailer/view&amp;id=12">Welcome to term 1</a></td>
                </tr>
                """,
                """
                <tr class="even">
                    <td>13-Aug-2026 09:00</td>
                    <td>Outdoor Department</td>
                    <td><a href="/index.php?r=mailer/view&amp;id=7">Kayaking kit list</a></td>
                </tr>
                """
            ]
        )
    }

    static let archive = page(
        headers: ["Send date", "Subject"],
        rows: [
            """
            <tr class="odd">
                <td>12-Aug-2026 18:30</td>
                <td><a href="/index.php?r=mailer/view&amp;id=4">Question about the CAS deadline</a></td>
            </tr>
            """
        ]
    )

    static let emptyInbox = page(headers: ["Received", "From", "Subject"], rows: [
        #"<tr><td class="empty" colspan="3">No results found.</td></tr>"#
    ])

    /// A page W4 served but this app cannot read: no grid at all, and no empty-state marker.
    static let unreadable = """
    <html><body><div id="content_inner"><h2>Inbox</h2><p>Something entirely new.</p></div></body></html>
    """

    static let messageBody = """
    <html><body><div id="content_inner">
        <h2>Welcome to term 1</h2>
        <table class="detail-view">
            <tr><th>From:</th><td>House Leader</td></tr>
            <tr><th>Received:</th><td>14-Aug-2026 12:04</td></tr>
        </table>
        <div class="message-body">
            <p>Hello Alex,</p>
            <p>Please read the <a href="/index.php?r=documents/view&amp;id=3">handbook</a> before Monday.</p>
        </div>
    </div></body></html>
    """

    private static func page(headers: [String], rows: [String]) -> String {
        let head = headers.map { "<th>\($0)</th>" }.joined()
        return """
        <html><body><div id="content_inner">
            <div class="grid-view">
                <table class="items">
                    <thead><tr>\(head)</tr></thead>
                    <tbody>\(rows.joined())</tbody>
                </table>
            </div>
        </div></body></html>
        """
    }
}

// MARK: - Test doubles

/// Answers per route and records what it was asked for. `@unchecked Sendable` with a lock: the
/// repository is an actor and calls in from whatever executor the test task lands on.
private final class StubMailViewTransport: MailPageFetching, @unchecked Sendable {

    private let lock = NSLock()
    private var _answers: [String: Result<String, Error>]
    private var _routes: [String] = []

    init(inbox: Result<String, Error> = .success(""), archive: Result<String, Error> = .success("")) {
        _answers = [
            W4Routes.R.mailerInbox: inbox,
            W4Routes.R.mailerArchive: archive
        ]
    }

    var routes: [String] { lock.withLock { _routes } }
    var callCount: Int { routes.count }

    func setAnswer(_ answer: Result<String, Error>, for route: String) {
        lock.withLock { _answers[route] = answer }
    }

    func fetchMailPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (html: String, finalURL: URL) {
        let answer = record(route)
        switch answer {
        case .success(let html): return (html, W4Routes.url(route, query))
        case .failure(let error): throw error
        }
    }

    func fetchMailFile(
        url: URL,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> Data {
        Data("attachment".utf8)
    }

    /// `NSLock.lock()` is unavailable from an async context, so the locking lives here.
    private func record(_ route: String) -> Result<String, Error> {
        lock.withLock {
            _routes.append(route)
            return _answers[route] ?? .success("")
        }
    }
}

/// Lets a test hold one in-flight request open while it does something else.
private actor MailTestGate {

    private var isRequested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markRequested() {
        isRequested = true
        let waiters = requestWaiters
        requestWaiters = []
        waiters.forEach { $0.resume() }
    }

    func waitForRequest() async {
        if isRequested { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters = []
        waiters.forEach { $0.resume() }
    }

    func waitForRelease() async {
        if isReleased { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            releaseWaiters.append(continuation)
        }
    }
}

/// Holds the inbox request open until the test releases it; answers the archive immediately.
private final class GatedMailTransport: MailPageFetching, @unchecked Sendable {

    let gate = MailTestGate()

    private let inboxHTML: String
    private let archiveHTML: String

    init(inboxHTML: String, archiveHTML: String) {
        self.inboxHTML = inboxHTML
        self.archiveHTML = archiveHTML
    }

    func fetchMailPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> (html: String, finalURL: URL) {
        if route == W4Routes.R.mailerInbox {
            await gate.markRequested()
            await gate.waitForRelease()
            return (inboxHTML, W4Routes.url(route, query))
        }
        return (archiveHTML, W4Routes.url(route, query))
    }

    func fetchMailFile(
        url: URL,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> Data {
        Data()
    }
}

// MARK: - Tests

@MainActor
final class MailViewModelTests: XCTestCase {

    private var scratch: URL!
    private var mailRoot: URL!
    private var pageRoot: URL!
    private var attachmentRoot: URL!

    private static let uwcId = "nc26abcd"

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        mailRoot = scratch.appendingPathComponent("MailCache", isDirectory: true)
        pageRoot = scratch.appendingPathComponent("W4Pages", isDirectory: true)
        attachmentRoot = scratch.appendingPathComponent("Attachments", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        try super.tearDownWithError()
    }

    // MARK: Helpers

    private static let student = Student(
        studentId: uwcId,
        name: "Alex Andersen",
        pictureId: nil,
        classLabel: nil
    )

    private static func realContext() -> W4RequestContext {
        W4RequestContext(student: student, credentials: W4Credentials(sessionId: "phpsessid-for-tests"))
    }

    private static func demoContext() -> W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    /// A repository over this test's scratch directories. No Keychain, no shared caches, no
    /// network — every dependency is injected.
    private func makeRepository(
        transport: MailPageFetching,
        context: W4RequestContext? = nil
    ) -> MailRepository {
        let resolved = context ?? Self.realContext()
        return MailRepository(
            transport: transport,
            store: MailFileCache(root: mailRoot),
            pageCache: W4PageCache(root: pageRoot),
            attachments: AttachmentCache(root: attachmentRoot),
            resolveContext: { resolved }
        )
    }

    // MARK: - Reading the inbox

    func testInboxRendersW4Rows() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.inbox()))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        await viewModel.load()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.map(\.id), ["12", "7"])
        XCTAssertEqual(viewModel.messages.first?.subject, "Welcome to term 1")
        XCTAssertEqual(viewModel.messages.first?.from, "House Leader")
        XCTAssertTrue(viewModel.messages.first?.isUnread ?? false)
        XCTAssertNotNil(viewModel.messages.first?.receivedAt)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.outcome, .parsed)
    }

    func testUnreadBadgeCountsUnreadInboxRows() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.inbox()))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        await viewModel.load()

        XCTAssertEqual(viewModel.unreadCount, 1)

        viewModel.markReadLocally(id: "12")
        XCTAssertFalse(viewModel.messages.first?.isUnread ?? true)
        XCTAssertEqual(viewModel.unreadCount, 0)
    }

    func testEmptyInboxIsAnEmptyStateNotAFailure() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.emptyInbox))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        await viewModel.load()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.isEmptyState)
        XCTAssertFalse(viewModel.isUnreadableState)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUnreadableMarkupIsNotPresentedAsAnEmptyMailbox() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.unreadable))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        await viewModel.load()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.isUnreadableState)
        XCTAssertFalse(viewModel.isEmptyState)
    }

    // MARK: - Cache-first, then refresh

    func testSecondLoadPaintsFromCacheAndDoesNotRefetchInsideTheTTL() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.inbox()))
        let repository = makeRepository(transport: transport)

        let first = MessagesViewModel(repository: repository)
        await first.load()
        XCTAssertEqual(transport.callCount, 1)

        let second = MessagesViewModel(repository: repository)
        await second.load()

        XCTAssertEqual(second.messages.count, 2)
        XCTAssertEqual(transport.callCount, 1, "a list inside its TTL must be served from disk")
        XCTAssertTrue(second.isShowingCachedCopy)
        XCTAssertFalse(second.isLoading)
    }

    func testFailedRefreshOverAWarmCacheKeepsTheRowsAndRaisesNoError() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.inbox()))
        let repository = makeRepository(transport: transport)
        let viewModel = MessagesViewModel(repository: repository)

        await viewModel.load()
        XCTAssertEqual(viewModel.messages.count, 2)

        transport.setAnswer(.failure(URLError(.notConnectedToInternet)), for: W4Routes.R.mailerInbox)
        await viewModel.refresh()

        XCTAssertEqual(viewModel.messages.count, 2, "an offline refresh must never empty the list")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.isShowingCachedCopy)
    }

    func testErrorIsSurfacedOnlyWhenTheScreenWouldBeBlank() async throws {
        let transport = StubMailViewTransport(inbox: .failure(W4Error.httpError(status: 500, route: "mailer/inbox")))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        await viewModel.load()

        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Generation / target guard

    func testAStaleFolderResponseCannotOverwriteANewerSelection() async throws {
        let transport = GatedMailTransport(
            inboxHTML: MailPageFixture.inbox(),
            archiveHTML: MailPageFixture.archive
        )
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        // Inbox load starts and parks inside the transport.
        viewModel.selectedFolder = .inbox
        let inboxLoad = Task { await viewModel.load() }
        await transport.gate.waitForRequest()

        // The student switches to Sent, which completes first.
        viewModel.selectedFolder = .archive
        await viewModel.load()
        XCTAssertEqual(viewModel.messages.map(\.subject), ["Question about the CAS deadline"])

        // Now the older inbox response lands. It must be dropped on the floor.
        await transport.gate.release()
        await inboxLoad.value

        XCTAssertEqual(viewModel.selectedFolder.id, MailFolder.archive.id)
        XCTAssertEqual(
            viewModel.messages.map(\.subject),
            ["Question about the CAS deadline"],
            "the inbox response arrived after the student moved to Sent and must not be painted"
        )
    }

    // MARK: - Session handling

    func testSessionExpiredLogsTheStudentOut() async throws {
        let transport = StubMailViewTransport(inbox: .failure(W4Error.sessionExpired))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        let expectation = expectation(forNotification: .w4SessionExpired, object: nil)
        await viewModel.load()
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testForbiddenDoesNotLogTheStudentOut() async throws {
        let transport = StubMailViewTransport(inbox: .failure(W4Error.forbidden))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))

        var loggedOut = false
        let observer = NotificationCenter.default.addObserver(
            forName: .w4SessionExpired,
            object: nil,
            queue: nil
        ) { _ in loggedOut = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        await viewModel.load()

        XCTAssertFalse(loggedOut, "403 without Login Required is the wrong role, not a dead session")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Search

    func testSearchFiltersBySubjectAndSender() async throws {
        let transport = StubMailViewTransport(inbox: .success(MailPageFixture.inbox()))
        let viewModel = MessagesViewModel(repository: makeRepository(transport: transport))
        await viewModel.load()

        viewModel.searchQuery = "kayak"
        XCTAssertEqual(viewModel.visibleMessages.map(\.id), ["7"])

        viewModel.searchQuery = "house leader"
        XCTAssertEqual(viewModel.visibleMessages.map(\.id), ["12"])

        viewModel.searchQuery = "   "
        XCTAssertEqual(viewModel.visibleMessages.count, 2)
        XCTAssertFalse(viewModel.isSearching)
    }

    // MARK: - Demo mode

    func testDemoInboxNeverReachesTheTransport() async throws {
        let transport = StubMailViewTransport(inbox: .failure(W4Error.noResponse))
        let repository = makeRepository(transport: transport, context: Self.demoContext())
        let viewModel = MessagesViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(transport.callCount, 0)
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.freshness, .demo)
    }

    func testDemoMessageBodyNeverReachesTheTransport() async throws {
        let transport = StubMailViewTransport(inbox: .failure(W4Error.noResponse))
        let repository = makeRepository(transport: transport, context: Self.demoContext())
        let viewModel = MailMessageViewModel(repository: repository, scheduleInboxRefresh: { _ in })

        let row = MailMessage(
            id: "demo-mail-1",
            folderID: MailFolder.inbox.id,
            subject: "Welcome to term 1",
            from: "House Leader"
        )
        await viewModel.load(message: row, student: .demo)

        XCTAssertEqual(transport.callCount, 0)
        XCTAssertNotNil(viewModel.detail)
        XCTAssertFalse(viewModel.blocks.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - One message

    func testMessageBodyIsRenderedFromHTML() async throws {
        let transport = StubMailViewTransport()
        transport.setAnswer(.success(MailPageFixture.messageBody), for: W4Routes.R.mailerView)
        let viewModel = MailMessageViewModel(
            repository: makeRepository(transport: transport),
            scheduleInboxRefresh: { _ in }
        )

        let row = MailMessage(
            id: "12",
            folderID: MailFolder.inbox.id,
            subject: "Welcome to term 1",
            from: "House Leader"
        )
        await viewModel.load(message: row, student: Self.student)

        XCTAssertEqual(viewModel.detail?.id, "12")
        XCTAssertFalse(viewModel.blocks.isEmpty, "the TinyMCE body must render to drawable blocks")
        let text = HTMLContentRenderer.plainText(viewModel.blocks)
        XCTAssertTrue(text.contains("Hello Alex"), "rendered text was: \(text)")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testMessageBodyIsServedFromCacheOnSecondOpen() async throws {
        let transport = StubMailViewTransport()
        transport.setAnswer(.success(MailPageFixture.messageBody), for: W4Routes.R.mailerView)
        let repository = makeRepository(transport: transport)
        let row = MailMessage(id: "12", folderID: MailFolder.inbox.id, subject: "Welcome to term 1")

        let first = MailMessageViewModel(repository: repository, scheduleInboxRefresh: { _ in })
        await first.load(message: row, student: Self.student)
        XCTAssertEqual(transport.callCount, 1)

        let second = MailMessageViewModel(repository: repository, scheduleInboxRefresh: { _ in })
        await second.load(message: row, student: Self.student)

        XCTAssertEqual(transport.callCount, 1, "a sent message cannot change, so it never refetches")
        XCTAssertFalse(second.blocks.isEmpty)
    }

    // MARK: - Compose

    func testComposeIsHonestlyDisabledRatherThanFakingASend() async throws {
        XCTAssertFalse(
            MailFeatureFlags.composeEnabled,
            "flip this only when a real mailer/send round trip has been captured"
        )

        let viewModel = ComposeMessageViewModel()
        viewModel.subject = "Question about the CAS deadline"
        viewModel.messageBody = "Hi, could we move it to Friday?"

        XCTAssertFalse(viewModel.canSend)
        XCTAssertTrue(viewModel.hasDraft)

        let sent = await viewModel.send(for: Self.student)

        XCTAssertFalse(sent)
        XCTAssertNotNil(viewModel.sendFailure)
        XCTAssertEqual(viewModel.subject, "Question about the CAS deadline", "the draft survives")
    }

    func testAttachmentLimitsAreW4sNotLectios() {
        XCTAssertEqual(OutgoingMessageAttachment.maximumCount, 5)
        XCTAssertEqual(OutgoingMessageAttachment.maximumByteCount, 2 * 1_024 * 1_024)
        XCTAssertEqual(OutgoingMessageAttachment.maximumCount, MailAttachmentLimits.maximumCount)
    }

    func testPlainTextBecomesEscapedTinyMCEParagraphs() {
        XCTAssertEqual(
            ComposeMessageViewModel.html(fromPlainText: "a < b\nsecond line\n\nnew paragraph"),
            "<p>a &lt; b<br>second line</p><p>new paragraph</p>"
        )
        XCTAssertEqual(ComposeMessageViewModel.html(fromPlainText: "   "), "")
    }

    func testDraftCarriesW4sFormFieldNames() {
        let viewModel = ComposeMessageViewModel()
        viewModel.subject = "Kit list"
        viewModel.messageBody = "Bring boots."
        viewModel.sendCopyToMe = true

        let fields = viewModel.draft.formFields()

        XCTAssertEqual(fields[MailComposeFields.subject], "Kit list")
        XCTAssertEqual(fields[MailComposeFields.message], "<p>Bring boots.</p>")
        XCTAssertEqual(fields[MailComposeFields.sendCC], "1")
        XCTAssertEqual(fields[MailComposeFields.attachmentSource], MailComposeFields.attachmentSourceUpload)
    }

    // MARK: - Rendering helpers

    func testRelativeLinksResolveAgainstW4AndMailtoIsLeftAlone() {
        XCTAssertEqual(
            MessageContentRenderer.absoluteURL("/index.php?r=mailer/view&id=12")?.absoluteString,
            "https://w4.uwcrcn.no/index.php?r=mailer/view&id=12"
        )
        XCTAssertEqual(
            MessageContentRenderer.absoluteURL("mailto:nc26abcd@uwcrcn.no")?.absoluteString,
            "mailto:nc26abcd@uwcrcn.no"
        )
        XCTAssertNil(MessageContentRenderer.absoluteURL("   "))
    }
}
