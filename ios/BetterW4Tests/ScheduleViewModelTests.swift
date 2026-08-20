//
//  ScheduleViewModelTests.swift
//  BetterW4Tests
//
//  `ScheduleViewModel` is the Timetable tab's whole brain, and everything worth asserting about it
//  is a rule from `features.md` §3 rather than a getter:
//
//    * cached data paints before the network, and a spinner appears only when there is nothing to
//      paint at all;
//    * a failed refresh never removes the week the student is reading;
//    * a half-rendered grid never replaces a good one;
//    * `.forbidden` is not a dead session and must not sign anybody out — `.sessionExpired` is and
//      must;
//    * when W4 ignores `?year=&week=` the week controls switch off instead of quietly showing the
//      wrong week (plan D-18).
//
//  Nothing here touches the network or `Timetable.store`: the transport is a stub, the store
//  bridge is `.disabled`, and the page cache is rooted in a per-test temporary directory. The HTML
//  is the same synthesized grid `TimetableRepositoryTests` uses — two nested `#timetable`
//  elements, a header row of day cells, an hour gutter column and one column per day. Lesson
//  blocks are **[I]**: no real `.period` element has ever been captured.
//

import XCTest
@testable import BetterW4

// MARK: - Transport double

/// Answers from a canned table keyed by route, and records what it was asked for.
private actor StubScheduleLoader: TimetablePageLoading {

    private var responses: [String: Result<TimetablePageResponse, any Error>]
    private var callCount = 0

    init(responses: [String: Result<TimetablePageResponse, any Error>] = [:]) {
        self.responses = responses
    }

    func setResponse(_ result: Result<TimetablePageResponse, any Error>, for route: String) {
        responses[route] = result
    }

    func calls() -> Int { callCount }

    func loadPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        uwcId: String,
        priority: FetchPriority
    ) async throws -> TimetablePageResponse {
        callCount += 1
        switch responses[route] {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case nil:
            throw W4Error.httpError(status: 404, route: route)
        }
    }
}

// MARK: - Tests

@MainActor
final class ScheduleViewModelTests: XCTestCase {

    /// Pinned to the real clock: `W4PageCache` stamps and judges its own entries with
    /// `TimeProvider.now`, so a fake clock days away would make every page look ancient.
    private var now: Date!
    private var cacheRoot: URL!

    private let uwcId = "nc26test"

    override func setUpWithError() throws {
        now = Date()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduleViewModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
    }

    // MARK: Demo

    func testDemoSessionRendersAWeekAndNeverFetches() async {
        let loader = StubScheduleLoader()
        let viewModel = makeViewModel(loader: loader, isDemo: true)

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.selectedFreshness, .demo)
        XCTAssertTrue(viewModel.isShowingDemoData)
        XCTAssertEqual(viewModel.selectedWeek?.days.count, 7)
        XCTAssertTrue(viewModel.selectedWeek?.hasEvents == true, "demo mode must render a real-looking week")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)

        let calls = await loader.calls()
        XCTAssertEqual(calls, 0, "demo mode must branch before any network call")
    }

    // MARK: Happy path

    func testFreshFetchFillsTheSelectedWeek() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsHTML()))
        ])
        let viewModel = makeViewModel(loader: loader)

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.selectedFreshness, .fresh)
        XCTAssertEqual(viewModel.selectedWeek?.days.count, 7)
        XCTAssertFalse(viewModel.isLoading, "the spinner must be gone once a week is on screen")
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertNil(viewModel.errorMessage)

        let ids = viewModel.selectedWeek?.allEvents.map(\.id) ?? []
        XCTAssertTrue(ids.contains("ac-w4-42"), "Academics lesson missing: \(ids)")
        XCTAssertTrue(ids.contains("ea-w4-99"), "Extra Academics lesson missing: \(ids)")
    }

    func testOnAppearAlwaysSelectsTodayEvenAfterBrowsingAway() async {
        let viewModel = await loadedViewModel()
        let later = W4Dates.adding(days: 3, to: now)
        await viewModel.select(date: later)

        XCTAssertFalse(
            W4Dates.isSameDay(viewModel.selectedDate, viewModel.today),
            "precondition: the student has left today"
        )

        await viewModel.onAppear()

        XCTAssertTrue(
            W4Dates.isSameDay(viewModel.selectedDate, viewModel.today),
            "opening the timetable must land on today, not the last browsed day"
        )
    }

    func testTimedAndAllDayBlocksAreSplitForTheDayTheyFallOn() async {
        let viewModel = await loadedViewModel()
        let monday = startOfCurrentWeek()

        let timed = viewModel.timedEvents(on: monday)
        XCTAssertEqual(timed.map(\.id), ["ac-w4-42", "ea-w4-99"], "timed blocks must come back sorted by start")
        XCTAssertTrue(viewModel.allDayEvents(on: monday).isEmpty)

        // A day W4 rendered no blocks for is empty, not missing.
        let tuesday = W4Dates.adding(days: 1, to: monday)
        XCTAssertNotNil(viewModel.day(on: tuesday), "every header date becomes a day, even an empty one")
        XCTAssertTrue(viewModel.timedEvents(on: tuesday).isEmpty)
    }

    func testDayContextComesFromTheGridHeader() async {
        let viewModel = await loadedViewModel()
        let monday = startOfCurrentWeek()
        let saturday = W4Dates.adding(days: 5, to: monday)

        XCTAssertEqual(viewModel.rotationDay(on: monday), "Day 1")
        XCTAssertFalse(viewModel.isNoClassesDay(monday))
        XCTAssertTrue(viewModel.isNoClassesDay(saturday), "the weekend column carries the no-classes class")
    }

    func testCurrentAndUpcomingLessonAreDerivedFromTheClock() async {
        let viewModel = await loadedViewModel()
        let monday = startOfCurrentWeek()

        // The Academics block runs 08:00–09:00 Oslo on the Monday of the grid.
        let inside = W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60 + 30)
        XCTAssertEqual(viewModel.currentLesson(at: inside)?.id, "ac-w4-42")
        XCTAssertNil(viewModel.nextLesson(at: inside), "nothing is 'next' while a lesson is running")

        let justBefore = W4Dates.date(onDayOf: monday, minutesFromMidnight: 7 * 60 + 30)
        XCTAssertNil(viewModel.currentLesson(at: justBefore))
        XCTAssertEqual(viewModel.nextLesson(at: justBefore)?.id, "ac-w4-42")

        let longBefore = W4Dates.date(onDayOf: monday, minutesFromMidnight: 6 * 60)
        XCTAssertNil(viewModel.nextLesson(at: longBefore), "two hours out is not 'starting soon'")
    }

    func testGridHoursComeFromThePageNotFromAHardcodedSchoolDay() async {
        let viewModel = await loadedViewModel()
        let monday = startOfCurrentWeek()

        XCTAssertEqual(viewModel.gridStartHour(for: monday), 7, "tt_start_hour")
        XCTAssertEqual(viewModel.gridEndHour(for: monday), 22, "tt_end_hour")
    }

    // MARK: Failure

    func testColdFailureSurfacesAMessageAndNoWeek() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .failure(W4Error.httpError(status: 500, route: W4Routes.R.myTimetable))
        ])
        let viewModel = makeViewModel(loader: loader)

        await viewModel.onAppear()

        XCTAssertNil(viewModel.selectedWeek)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading, "a finished failure must not leave a spinner behind")
    }

    func testFailedRefreshKeepsTheWeekAlreadyOnScreen() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsHTML()))
        ])
        let viewModel = makeViewModel(loader: loader)
        await viewModel.onAppear()
        XCTAssertNotNil(viewModel.selectedWeek)

        // W4 falls over on the next pull.
        await loader.setResponse(
            .failure(W4Error.networkError(URLError(.timedOut))),
            for: W4Routes.R.myTimetable
        )
        await viewModel.refresh()

        XCTAssertNotNil(viewModel.selectedWeek, "a transient failure must never wipe cached data")
        XCTAssertFalse(viewModel.selectedWeek?.allEvents.isEmpty ?? true)
        XCTAssertTrue(
            viewModel.selectedFreshness?.isFromCache == true,
            "the surviving copy is cached, and must say so"
        )
    }

    func testAHalfRenderedGridNeverReplacesAGoodWeek() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsHTML()))
        ])
        let viewModel = makeViewModel(loader: loader)
        await viewModel.onAppear()
        let goodIDs = viewModel.selectedWeek?.allEvents.map(\.id) ?? []
        XCTAssertFalse(goodIDs.isEmpty)

        // A page with no day columns at all: an error page, or markup we do not know.
        await loader.setResponse(
            .success(response("<html><body><div id=\"timetable\"></div></body></html>")),
            for: W4Routes.R.myTimetable
        )
        await viewModel.refresh()

        XCTAssertEqual(
            viewModel.selectedWeek?.allEvents.map(\.id),
            goodIDs,
            "a truncated page must not delete lessons we already have"
        )
    }

    // MARK: Session rules

    func testForbiddenDoesNotSignTheStudentOut() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .failure(W4Error.forbidden)
        ])
        let viewModel = makeViewModel(loader: loader)

        let logout = expectation(forNotification: .w4SessionExpired, object: nil)
        logout.isInverted = true

        await viewModel.onAppear()

        await fulfillment(of: [logout], timeout: 0.2)
        XCTAssertEqual(viewModel.errorMessage, "You do not have access to the timetable.")
    }

    func testSessionExpiredSignsTheStudentOut() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .failure(W4Error.sessionExpired)
        ])
        let viewModel = makeViewModel(loader: loader)

        let logout = expectation(forNotification: .w4SessionExpired, object: nil)

        await viewModel.onAppear()

        await fulfillment(of: [logout], timeout: 1)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: Week navigation (D-18)

    func testWeekNavigationSwitchesOffWhenW4IgnoresTheWeekParameters() async {
        // Every request answers with the *current* week's grid, whatever week was asked for —
        // which is exactly what a server that ignores `?year=&week=` looks like.
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsHTML()))
        ])
        let viewModel = makeViewModel(loader: loader)
        await viewModel.onAppear()
        XCTAssertTrue(viewModel.weekNavigationAvailable)

        await viewModel.select(date: W4Dates.adding(days: 7, to: now))

        XCTAssertFalse(
            viewModel.weekNavigationAvailable,
            "asking for next week and being handed this week must switch navigation off"
        )
        XCTAssertNil(
            viewModel.selectedWeek,
            "the week W4 answered with is filed under its own key, never the one we asked for"
        )
    }

    // MARK: Selection and reset

    func testSelectingANeighbouringDayKeepsThePreviousWeekLoaded() async {
        let viewModel = await loadedViewModel()
        let currentKey = viewModel.selectedWeekKey

        await viewModel.select(date: W4Dates.adding(days: 7, to: now))

        XCTAssertNotNil(
            viewModel.weeks[currentKey],
            "the pager swipes across a week boundary, so the week behind it must stay loaded"
        )
    }

    func testResetForgetsEveryWeekAndReloads() async {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsHTML()))
        ])
        let viewModel = makeViewModel(loader: loader)
        await viewModel.onAppear()
        XCTAssertFalse(viewModel.weeks.isEmpty)

        await viewModel.reset()

        XCTAssertNotNil(viewModel.selectedWeek, "reset reloads rather than leaving the tab blank")
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Helpers

    private func makeViewModel(
        loader: StubScheduleLoader,
        isDemo: Bool = false
    ) -> ScheduleViewModel {
        let student = Student(
            studentId: isDemo ? Student.demoStudentId : uwcId,
            name: "Test Student",
            pictureId: nil,
            classLabel: nil
        )
        let context = W4RequestContext(
            student: student,
            credentials: isDemo ? .empty : W4Credentials(sessionId: "PHPSESSID-test")
        )
        let fixedNow = now!
        let repository = TimetableRepository(
            loader: loader,
            cache: W4PageCache(root: cacheRoot),
            store: .disabled,
            context: { context },
            clock: { fixedNow }
        )
        return ScheduleViewModel(repository: repository, clock: { fixedNow })
    }

    /// A view model with the current week already on screen.
    private func loadedViewModel() async -> ScheduleViewModel {
        let loader = StubScheduleLoader(responses: [
            W4Routes.R.myTimetable: .success(response(academicsHTML())),
            W4Routes.R.eaTimetable: .success(response(extraAcademicsHTML()))
        ])
        let viewModel = makeViewModel(loader: loader)
        await viewModel.onAppear()
        return viewModel
    }

    private func response(_ html: String) -> TimetablePageResponse {
        TimetablePageResponse(html: html, finalURL: W4Routes.url(W4Routes.R.myTimetable))
    }

    private func startOfCurrentWeek() -> Date {
        let iso = W4Dates.isoWeek(of: now)
        return W4Dates.startOfISOWeek(year: iso.year, week: iso.week) ?? W4Dates.startOfDay(now)
    }

    private func academicsHTML() -> String {
        Self.gridHTML(
            monday: startOfCurrentWeek(),
            periodsByDay: [0: Self.lessonHTML(id: "42", title: "Biology HL", from: "8:00", to: "9:00", top: 60)]
        )
    }

    private func extraAcademicsHTML() -> String {
        Self.gridHTML(
            monday: startOfCurrentWeek(),
            periodsByDay: [0: Self.lessonHTML(id: "99", title: "Sea Kayaking", from: "17:00", to: "18:30", top: 600)]
        )
    }

    /// Mirrors the captured page: nested `#timetable` elements, a header whose first cell is the
    /// empty gutter, an hour-gutter column, then one column per day.
    private static func gridHTML(monday: Date, periodsByDay: [Int: String]) -> String {
        var header = #"<div class="header-cell first">&nbsp;</div>"#
        for offset in 0..<7 {
            let day = W4Dates.adding(days: offset, to: monday)
            let isWeekend = offset >= 5
            let rotationClass = isWeekend ? "rotation-day no-classes" : "rotation-day"
            let rotationLabel = isWeekend ? "Weekend" : "Day " + String(offset + 1)
            header += """
            <div class="header-cell">
              <div class="day-name">\(W4Dates.weekdayName(of: day))</div>
              <div>\(W4Dates.format(day))</div>
              <div class="\(rotationClass)">\(rotationLabel)</div>
              <div>No EA</div>
            </div>
            """
        }

        var columns = #"<div class="column" style="height: 900px"><div class="cell">7:00 &#8212; 8:00</div></div>"#
        for index in 0..<7 {
            columns += #"<div class="column" style="height: 900px">"#
                + (periodsByDay[index] ?? "")
                + "</div>"
        }

        return """
        <html><body>
        <script>tt_start_hour = 7; tt_end_hour = 22;</script>
        <div id="timetable">
          <h3>Week grid</h3>
          <div id="timetable-header"><div class="header-row">\(header)</div></div>
          <div id="timetable">\(columns)</div>
        </div>
        </body></html>
        """
    }

    /// **[I]** Invented from the Android port's selectors — no real `.period` has been captured.
    private static func lessonHTML(id: String, title: String, from: String, to: String, top: Int) -> String {
        """
        <div class="period" style="top: \(top)px; height: 60px;" title="\(title)">
          <div class="inner"><a href="index.php?r=academics/classes/class&amp;id=\(id)">\(title)</a>
            <div class="datetime">\(from) &#8212; \(to)</div><div class="room">R1</div>
          </div>
        </div>
        """
    }
}
