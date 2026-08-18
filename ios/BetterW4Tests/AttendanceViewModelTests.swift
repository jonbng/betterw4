//
//  AttendanceViewModelTests.swift
//  BetterW4Tests
//
//  Wave 6 item 6.4: `AttendanceViewModel` and `GradesViewModel`, plus the two presentation types
//  the attendance screen is built from (`AttendanceMeterDisplay`, `AttendanceDaySection`).
//
//  Nothing here touches the network. Both view models take their repository by injection, both
//  repositories take their transport by injection, and the page cache is a real `W4PageCache`
//  rooted in a per-test temporary directory — so "cache-first", "the meters cost zero requests"
//  and "a failed refresh keeps the cached copy" are *proved* against a real cache rather than
//  asserted against a mock.
//
//  What these tests protect is `features.md` §3: the generation guard, cache-first rendering, the
//  spinner-only-when-empty rule, the error-only-when-empty rule, the reset on student switch, and
//  the rule that `W4Error.forbidden` degrades instead of logging anybody out.
//
//  FIXTURE PROVENANCE
//    [I] Every page below is hand-written. Neither the absence list nor the grades table has ever
//        been captured from W4, so these prove this layer plumbs the parsers correctly; they prove
//        nothing about W4's markup. The one shape that *is* verified is the Home meter markup,
//        reproduced here from `references/pages/UWCRCN W4.html:239-249`.
//

import XCTest
@testable import BetterW4

@MainActor
final class AttendanceViewModelTests: XCTestCase {

    // MARK: - Test rig

    /// Answers a queue of responses per route, so a second load can be given different HTML from
    /// the first. An optional delay is how the generation-guard test makes the *slower* request the
    /// *earlier* one.
    private actor AttendanceStub: AttendancePageFetching {

        private struct Response {
            let result: Result<String, Error>
            let delay: Duration
        }

        private var queues: [String: [Response]] = [:]
        private(set) var routes: [String] = []

        func stub(_ route: String, html: String, delay: Duration = .zero) {
            queues[route, default: []].append(Response(result: .success(html), delay: delay))
        }

        func stub(_ route: String, error: Error, delay: Duration = .zero) {
            queues[route, default: []].append(Response(result: .failure(error), delay: delay))
        }

        var callCount: Int { routes.count }

        func fetchPage(
            route: String,
            query: [String: String],
            credentials: W4Credentials,
            studentId: String?,
            priority: FetchPriority
        ) async throws -> AttendancePageResponse {
            routes.append(route)

            var queue = queues[route] ?? []
            guard !queue.isEmpty else { throw W4Error.httpError(status: 599, route: route) }
            // The last response repeats, so a test only has to stub what it cares about.
            let response = queue.count == 1 ? queue[0] : queue.removeFirst()
            queues[route] = queue

            if response.delay > .zero {
                try? await Task.sleep(for: response.delay)
            }
            switch response.result {
            case .success(let html):
                return AttendancePageResponse(html: html, finalURL: W4Routes.url(route))
            case .failure(let error):
                throw error
            }
        }
    }

    private final class GradeStub: W4SecondaryFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String: Result<String, Error>] = [:]
        private var recorded: [String] = []

        var routes: [String] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func stub(_ route: String, html: String) {
            lock.lock(); defer { lock.unlock() }
            responses[route] = .success(html)
        }

        func stub(_ route: String, error: Error) {
            lock.lock(); defer { lock.unlock() }
            responses[route] = .failure(error)
        }

        func fetchSecondaryPage(
            route: String,
            query: [String: String],
            credentials: W4Credentials,
            studentId: String?,
            priority: FetchPriority
        ) async throws -> W4SecondaryPage {
            lock.lock()
            recorded.append(route)
            let response = responses[route]
            lock.unlock()

            guard let response else { throw W4Error.httpError(status: 599, route: route) }
            switch response {
            case .success(let html):
                return W4SecondaryPage(html: html, finalURL: W4Routes.url(route), contentType: "text/html")
            case .failure(let error):
                throw error
            }
        }
    }

    /// A context the test can swap mid-flight, which is how the student-switch rule is exercised.
    private final class ContextBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: W4RequestContext

        init(_ value: W4RequestContext) { self.value = value }

        var context: W4RequestContext {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private var cacheRoot: URL!
    private var cache: W4PageCache!

    /// A fixed "now". Every seeded page is written relative to it, so "fresh" is arithmetic rather
    /// than a race with the wall clock.
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let uwcId = "nc26abcd"

    override func setUpWithError() throws {
        try super.setUpWithError()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttendanceViewModelTests-\(UUID().uuidString)", isDirectory: true)
        cache = W4PageCache(root: cacheRoot)
    }

    override func tearDownWithError() throws {
        if let cacheRoot { try? FileManager.default.removeItem(at: cacheRoot) }
        cache = nil
        cacheRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private var signedInStudent: Student {
        Student(studentId: uwcId, name: "Alex Andersen")
    }

    private func signedInContext() -> W4RequestContext {
        W4RequestContext(
            student: signedInStudent,
            credentials: W4Credentials(sessionId: "phpsessid-test")
        )
    }

    private func demoContext() -> W4RequestContext {
        W4RequestContext(student: .demo, credentials: .empty)
    }

    private func attendanceRepository(
        fetcher: any AttendancePageFetching,
        context: W4RequestContext
    ) -> AttendanceRepository {
        attendanceRepository(fetcher: fetcher, box: ContextBox(context))
    }

    private func attendanceRepository(
        fetcher: any AttendancePageFetching,
        box: ContextBox
    ) -> AttendanceRepository {
        let clock = self.clock
        return AttendanceRepository(
            fetcher: fetcher,
            cache: cache,
            resolveContext: { box.context },
            now: { clock }
        )
    }

    private func gradeRepository(
        client: any W4SecondaryFetching,
        context: W4RequestContext
    ) -> GradeRepository {
        GradeRepository(client: client, cache: cache, resolveContext: { context })
    }

    /// Both view models take the clock by injection. The value is hoisted out of `self` first so
    /// the escaping closure captures a `Date` rather than the (non-`Sendable`) test case.
    private func makeAttendanceViewModel(_ repository: AttendanceRepository) -> AttendanceViewModel {
        let clock = self.clock
        return AttendanceViewModel(repository: repository, now: { clock })
    }

    private func makeGradesViewModel(_ repository: GradeRepository) -> GradesViewModel {
        let clock = self.clock
        return GradesViewModel(repository: repository, now: { clock })
    }

    private func seed(
        _ html: String,
        surface: W4Surface,
        key: String,
        secondsOld: TimeInterval
    ) async {
        await cache.store(
            html: html,
            surface: surface,
            key: key,
            uwcId: uwcId,
            finalURL: nil,
            contentType: nil,
            fetchedAt: clock.addingTimeInterval(-secondsOld)
        )
    }

    /// The **[V]** Home meter markup, with the counts parameterised.
    private func meterPage(absences: Int, latenesses: Int) -> String {
        """
        <html><body><div id="absences">
          <div id="academic-absences"><h3>Academics Attendance Meter</h3>
            <p>You have \(absences) absences and \(latenesses) latenesses so far</p></div>
          <div id="ea-absences"><h3>EA Attendance Meter</h3>
            <p>You have 0 absences and 0 latenesses so far</p></div>
        </div></body></html>
        """
    }

    /// **[I]** hand-written — the absence list page has never been captured.
    private func listPage(
        rows: [(date: String, period: String, subject: String, type: String, status: String)]
    ) -> String {
        let body = rows.map { row in
            "<tr><td>\(row.date)</td><td>\(row.period)</td><td>\(row.subject)</td>"
                + "<td>\(row.type)</td><td>\(row.status)</td></tr>"
        }.joined()
        return """
        <html><body><div id="content_inner"><div class="grid-view"><table class="items">
          <thead><tr><th>Date</th><th>Period</th><th>Class</th><th>Type</th><th>Status</th></tr></thead>
          <tbody>\(body)</tbody>
        </table></div></div></body></html>
        """
    }

    private func emptyListPage(_ message: String) -> String {
        """
        <html><body><div id="content_inner"><div class="grid-view"><table class="items">
          <thead><tr><th>Date</th><th>Period</th><th>Class</th><th>Type</th><th>Status</th></tr></thead>
          <tbody><tr><td colspan="5" class="empty">\(message)</td></tr></tbody>
        </table></div></div></body></html>
        """
    }

    /// **[I]** hand-written — the grades page has never been captured (OQ-12).
    private func gradesPage() -> String {
        """
        <html><body><div id="content_inner"><table class="grades">
          <thead><tr><th>Subject</th><th>Teacher</th><th class="anticipated">Predicted</th><th>Final</th></tr></thead>
          <tbody>
            <tr><td>Mathematics HL</td><td>A. Newton</td><td class="anticipated">6</td>
                <td class="effort-grade-meets-expectations">7</td></tr>
            <tr><td>Biology SL</td><td>C. Darwin</td><td class="anticipated">5</td><td>5</td></tr>
            <tr><td>Theory of Knowledge</td><td>D. Hume</td><td class="anticipated">B</td><td>&ndash;</td></tr>
          </tbody>
        </table></div></body></html>
        """
    }

    private func stubEmptyLedgers(_ stub: AttendanceStub) async {
        await stub.stub(W4Routes.R.absences, html: emptyListPage("No results found."))
        await stub.stub(W4Routes.R.eaAbsences, html: emptyListPage("No results found."))
    }

    // MARK: - Demo mode (every screen must render demo data, never an error)

    func testDemoRendersBothMetersAndRecordsWithoutTouchingTheNetwork() async {
        let stub = AttendanceStub()
        let viewModel = AttendanceViewModel(
            repository: attendanceRepository(fetcher: stub, context: demoContext()))

        await viewModel.load(for: .demo)

        let calls = await stub.callCount
        XCTAssertEqual(calls, 0, "Demo mode must never issue a request")

        XCTAssertEqual(viewModel.meters.count, 2)
        XCTAssertEqual(viewModel.meters[0].source, .academics)
        XCTAssertEqual(viewModel.meters[0].absences, 2)
        XCTAssertEqual(viewModel.meters[0].latenesses, 1)
        XCTAssertEqual(viewModel.meters[1].source, .extraAcademics)
        XCTAssertEqual(viewModel.meters[1].meter, .zero)

        XCTAssertTrue(viewModel.hasRecords)
        XCTAssertFalse(viewModel.sections.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.freshnessLabel, "Demo data")
    }

    func testDemoExtraAcademicsLedgerShowsItsOwnEmptyMessage() async {
        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: AttendanceStub(), context: demoContext()))

        await viewModel.load(for: .demo)
        viewModel.selectedSource = .extraAcademics

        XCTAssertTrue(viewModel.sections.isEmpty)
        XCTAssertEqual(viewModel.emptyMessage, "No results found.")
    }

    // MARK: - Live loading

    func testMetersAndListsRenderFromW4() async {
        let stub = AttendanceStub()
        await stub.stub(W4Routes.R.home, html: meterPage(absences: 3, latenesses: 2))
        await stub.stub(
            W4Routes.R.absences,
            html: listPage(rows: [
                (date: "12-May-2026", period: "P2", subject: "English A HL", type: "Absence", status: "Unexcused"),
                (date: "12-May-2026", period: "P3", subject: "Biology SL", type: "Lateness", status: "Excused"),
                (date: "10-May-2026", period: "P1", subject: "English A HL", type: "Absence", status: "Unexcused")
            ])
        )
        await stub.stub(W4Routes.R.eaAbsences, html: emptyListPage("No results found."))

        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        XCTAssertEqual(viewModel.meters[0].absences, 3)
        XCTAssertEqual(viewModel.meters[0].latenesses, 2)
        XCTAssertEqual(viewModel.meters[1].meter, .zero)
        XCTAssertNil(viewModel.errorMessage)

        // Two days, newest first.
        XCTAssertEqual(viewModel.sections.count, 2)
        XCTAssertEqual(viewModel.sections.first?.records.count, 2)
        XCTAssertEqual(viewModel.sections.last?.records.count, 1)

        // The status string is rendered verbatim; the enum only groups (D-13).
        XCTAssertEqual(viewModel.sections.first?.records.first?.status, "Unexcused")
        XCTAssertEqual(viewModel.sections.first?.records.last?.kind, .lateness)

        // The breakdown counts events; it never derives a meter.
        XCTAssertEqual(viewModel.breakdown.first?.label, "English A HL")
        XCTAssertEqual(viewModel.breakdown.first?.total, 2)
    }

    func testMetersComeFromTheCachedHomePageWithoutAnExtraRequest() async {
        // `HomeRepository`'s copy of Home, well inside its TTL. The meters must be free.
        await seed(
            meterPage(absences: 4, latenesses: 1),
            surface: .home,
            key: W4Routes.R.home,
            secondsOld: 60
        )

        let stub = AttendanceStub()
        await stubEmptyLedgers(stub)

        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        let routes = await stub.routes
        XCTAssertFalse(
            routes.contains(W4Routes.R.home),
            "A fresh cached Home page must cost zero requests"
        )
        XCTAssertEqual(viewModel.meters[0].absences, 4)
        XCTAssertEqual(viewModel.meters[0].latenesses, 1)
    }

    // MARK: - §3.2 / §3.3 / §3.4 — cache first, no spinner over content, no error over content

    func testAFailedRefreshKeepsTheCachedCopyAndShowsANoticeInsteadOfAnError() async {
        await seed(
            meterPage(absences: 9, latenesses: 9),
            surface: .attendanceMeters,
            key: W4Routes.R.home,
            secondsOld: 60
        )
        await seed(
            listPage(rows: [
                (date: "01-May-2026", period: "P1", subject: "Cached Class", type: "Absence", status: "Cached")
            ]),
            surface: .attendanceAcademics,
            key: W4Routes.R.absences,
            secondsOld: 60
        )

        let stub = AttendanceStub()
        await stub.stub(W4Routes.R.home, error: URLError(.notConnectedToInternet))
        await stub.stub(W4Routes.R.absences, error: URLError(.notConnectedToInternet))
        await stub.stub(W4Routes.R.eaAbsences, error: URLError(.notConnectedToInternet))

        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, context: signedInContext()))
        // Pull-to-refresh: every TTL bypassed, so every route is actually attempted and fails.
        await viewModel.refresh(for: signedInStudent)

        XCTAssertTrue(viewModel.hasContent, "A transient failure must never wipe cached data")
        XCTAssertEqual(viewModel.meters[0].absences, 9)
        XCTAssertEqual(viewModel.sections.first?.records.first?.subject, "Cached Class")
        XCTAssertNil(viewModel.errorMessage, "There is something to show, so there is no error screen")
        XCTAssertEqual(viewModel.noticeMessage, "Offline — showing the last saved copy.")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testErrorSurfacesOnlyWhenThereIsNothingCached() async {
        let stub = AttendanceStub()
        await stub.stub(W4Routes.R.home, error: URLError(.notConnectedToInternet))
        await stub.stub(W4Routes.R.absences, error: URLError(.notConnectedToInternet))
        await stub.stub(W4Routes.R.eaAbsences, error: URLError(.notConnectedToInternet))

        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        XCTAssertFalse(viewModel.hasContent)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.noticeMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - §3.6 — `.forbidden` degrades, it never logs anybody out

    func testForbiddenDegradesToANoticeAndNeverPostsSessionExpired() async {
        await seed(
            meterPage(absences: 1, latenesses: 0),
            surface: .attendanceMeters,
            key: W4Routes.R.home,
            secondsOld: 60
        )
        await seed(
            listPage(rows: [
                (date: "01-May-2026", period: "P1", subject: "Cached Class", type: "Absence", status: "Cached")
            ]),
            surface: .attendanceAcademics,
            key: W4Routes.R.absences,
            secondsOld: 60
        )

        let stub = AttendanceStub()
        await stub.stub(W4Routes.R.home, error: W4Error.forbidden)
        await stub.stub(W4Routes.R.absences, error: W4Error.forbidden)
        await stub.stub(W4Routes.R.eaAbsences, error: W4Error.forbidden)

        let counter = SessionExpiryCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .w4SessionExpired,
            object: nil,
            queue: .main
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(token) }

        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, context: signedInContext()))
        await viewModel.refresh(for: signedInStudent)

        XCTAssertEqual(counter.value, 0, "403 is a role problem, never a dead session")
        XCTAssertTrue(viewModel.hasContent)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.noticeMessage, "W4 would not show this page for your account.")
    }

    // MARK: - §3.5 — a different student clears in-memory state

    func testSwitchingStudentClearsThePreviousStudentsData() async {
        let box = ContextBox(demoContext())
        let stub = AttendanceStub()
        // Nothing is stubbed for the live routes: after the switch every fetch fails cold.
        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, box: box))

        await viewModel.load(for: .demo)
        XCTAssertTrue(viewModel.hasRecords)

        box.context = signedInContext()
        await viewModel.load(for: signedInStudent)

        XCTAssertFalse(viewModel.hasRecords, "Demo rows must not survive into a real session")
        XCTAssertFalse(viewModel.hasContent)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - §3.1 — the generation guard

    func testASlowEarlierLoadCannotOverwriteAFasterLaterOne() async {
        let stub = AttendanceStub()
        // First response is slow and says 1/1; second is immediate and says 5/5.
        await stub.stub(W4Routes.R.home, html: meterPage(absences: 1, latenesses: 1), delay: .milliseconds(600))
        await stub.stub(W4Routes.R.home, html: meterPage(absences: 5, latenesses: 5))
        await stubEmptyLedgers(stub)

        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: stub, context: signedInContext()))

        let student = signedInStudent
        let slow = Task { @MainActor in await viewModel.load(for: student) }
        try? await Task.sleep(for: .milliseconds(50))
        await viewModel.refresh(for: student)
        let fastResult = viewModel.meters[0].absences
        _ = await slow.value

        XCTAssertEqual(fastResult, 5)
        XCTAssertEqual(
            viewModel.meters[0].absences,
            5,
            "The stale in-flight response must not overwrite the newer selection"
        )
    }

    // MARK: - Presentation models

    func testMeterSentencePluralisesBothCounts() {
        XCTAssertEqual(
            AttendanceMeterDisplay(source: .academics, meter: AttendanceMeter(absences: 1, latenesses: 1)).sentence,
            "You have 1 absence and 1 lateness so far."
        )
        XCTAssertEqual(
            AttendanceMeterDisplay(source: .academics, meter: AttendanceMeter(absences: 0, latenesses: 2)).sentence,
            "You have 0 absences and 2 latenesses so far."
        )
    }

    func testAMissingMeterIsNotAZeroMeter() {
        let missing = AttendanceMeterDisplay(source: .extraAcademics, meter: nil)
        XCTAssertFalse(missing.isReported)
        XCTAssertNil(missing.absences)
        XCTAssertEqual(missing.sentence, "Not reported yet.")

        let zero = AttendanceMeterDisplay(source: .extraAcademics, meter: .zero)
        XCTAssertTrue(zero.isReported)
        XCTAssertEqual(zero.absences, 0)
    }

    func testDaySectionsAreNewestFirstAndUndatedRowsSortLast() {
        let today = W4Dates.startOfDay(clock)
        let yesterday = W4Dates.adding(days: -1, to: today)

        func record(_ date: Date?, _ raw: String, _ subject: String) -> AttendanceRecord {
            AttendanceRecord(
                id: "\(raw)-\(subject)",
                source: .academics,
                date: date,
                displayDate: raw,
                period: "P1",
                subject: subject,
                kind: .absence,
                status: "Unexcused",
                teacher: nil,
                note: nil
            )
        }

        let sections = AttendanceDaySection.sections(
            from: [
                record(nil, "sometime", "Undated"),
                record(yesterday, W4Dates.format(yesterday), "Older"),
                record(today, W4Dates.format(today), "Newest")
            ],
            now: clock
        )

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "sometime"])
        XCTAssertEqual(sections.first?.records.first?.subject, "Newest")
        XCTAssertNil(sections.last?.date)
    }

    func testRegisterAbsencesIsALinkToW4AndNeverAForm() {
        let viewModel = makeAttendanceViewModel(attendanceRepository(fetcher: AttendanceStub(), context: signedInContext()))
        let url = viewModel.registerAbsencesURL
        XCTAssertEqual(url.host(), W4Routes.host)
        XCTAssertTrue(url.absoluteString.contains("people/students/absences/register"))
        // The form is modelled, but it is never submittable (OQ-10).
        XCTAssertFalse(AbsenceRegistrationForm().canSubmit)
    }

    // MARK: - Grades

    func testGradesRenderWithW4sOwnDynamicColumns() async {
        let client = GradeStub()
        client.stub(W4Routes.R.grades, html: gradesPage())

        let viewModel = GradesViewModel(
            repository: gradeRepository(client: client, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        XCTAssertEqual(viewModel.columns.map(\.label), ["Predicted", "Final"])
        XCTAssertEqual(viewModel.columns.first?.isAnticipated, true)
        XCTAssertEqual(viewModel.columns.last?.isAnticipated, false)
        XCTAssertEqual(viewModel.gradedRows.count, 3)
        XCTAssertNil(viewModel.errorMessage)

        // An en dash is *no cell at all*, never a zero.
        let tok = viewModel.gradedRows.first { $0.subject.hasPrefix("Theory of Knowledge") }
        XCTAssertNotNil(tok)
        XCTAssertNil(tok?.cell(for: "final"))

        // The effort grade rides along with the cell, where Lectio kept a weight.
        let maths = viewModel.gradedRows.first { $0.subject.hasPrefix("Mathematics") }
        XCTAssertEqual(maths?.level, "HL")
        XCTAssertEqual(maths?.cell(for: "final")?.effort, .meets)
        XCTAssertEqual(maths?.cell(for: "final")?.ibProgress, 1.0)
    }

    func testAverageIsTheIBMeanOfOneColumnAndSkipsFreeText() async {
        let client = GradeStub()
        client.stub(W4Routes.R.grades, html: gradesPage())

        let viewModel = makeGradesViewModel(gradeRepository(client: client, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        // Predicted holds 6, 5 and the free text "B" — "B" must not be coerced into a number.
        XCTAssertEqual(viewModel.average(forColumnID: "predicted"), "5.5")
        // Final holds 7 and 5; Theory of Knowledge has no cell there at all.
        XCTAssertEqual(viewModel.average(forColumnID: "final"), "6.0")
        XCTAssertEqual(viewModel.columnAverages.map(\.value), ["5.5", "6.0"])
        XCTAssertNil(viewModel.average(forColumnID: "no-such-column"))
    }

    func testSelectingAColumnFiltersToRowsThatHaveOne() async {
        let client = GradeStub()
        client.stub(W4Routes.R.grades, html: gradesPage())

        let viewModel = makeGradesViewModel(gradeRepository(client: client, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        XCTAssertEqual(viewModel.visibleRows.count, 3)
        XCTAssertEqual(viewModel.selectionLabel, "All")

        viewModel.selectedColumnID = "final"
        XCTAssertEqual(viewModel.visibleRows.count, 2)
        XCTAssertEqual(viewModel.selectionLabel, "Final")
    }

    func testASelectedColumnThatDisappearsFromW4IsDeselected() async {
        let client = GradeStub()
        client.stub(W4Routes.R.grades, html: gradesPage())

        let viewModel = makeGradesViewModel(gradeRepository(client: client, context: signedInContext()))
        await viewModel.load(for: signedInStudent)
        viewModel.selectedColumnID = "final"

        // W4 stops rendering the Final column.
        client.stub(
            W4Routes.R.grades,
            html: """
            <html><body><div id="content_inner"><table class="grades">
              <thead><tr><th>Subject</th><th class="anticipated">Predicted</th></tr></thead>
              <tbody><tr><td>Biology SL</td><td class="anticipated">5</td></tr></tbody>
            </table></div></body></html>
            """
        )
        await viewModel.refresh(for: signedInStudent)

        XCTAssertEqual(viewModel.columns.map(\.id), ["predicted"])
        XCTAssertNil(viewModel.selectedColumnID)
        XCTAssertEqual(viewModel.selectionLabel, "All")
    }

    func testGradesKeepTheCachedReportWhenARefreshFails() async {
        await seed(
            gradesPage(),
            surface: .grades,
            key: GradeReportKind.academic.cacheKey,
            secondsOld: 60
        )

        let client = GradeStub()
        client.stub(W4Routes.R.grades, error: URLError(.timedOut))

        let viewModel = makeGradesViewModel(gradeRepository(client: client, context: signedInContext()))
        await viewModel.refresh(for: signedInStudent)

        XCTAssertFalse(client.routes.isEmpty, "A forced refresh must actually try the network")
        XCTAssertTrue(viewModel.hasContent)
        XCTAssertEqual(viewModel.gradedRows.count, 3)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testGradesDemoModeRendersWithoutTouchingTheNetwork() async {
        let client = GradeStub()
        let viewModel = makeGradesViewModel(gradeRepository(client: client, context: demoContext()))
        await viewModel.load(for: .demo)

        XCTAssertTrue(client.routes.isEmpty)
        XCTAssertEqual(viewModel.columns.map(\.id), ["predicted", "final"])
        XCTAssertEqual(viewModel.gradedRows.count, 4)
        XCTAssertEqual(viewModel.freshnessLabel, "Demo data")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testGradesSurfaceAnErrorOnlyWithNothingCached() async {
        let client = GradeStub()
        client.stub(W4Routes.R.grades, error: URLError(.timedOut))

        let viewModel = makeGradesViewModel(gradeRepository(client: client, context: signedInContext()))
        await viewModel.load(for: signedInStudent)

        XCTAssertFalse(viewModel.hasContent)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
}

// MARK: - Small test helper

/// A counter a `NotificationCenter` observer can bump from any queue.
private final class SessionExpiryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock(); count += 1; lock.unlock()
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
