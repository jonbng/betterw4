//
//  AssessmentsViewModelTests.swift
//  BetterW4Tests
//
//  Tests for `AssessmentsViewModel` (plan Wave 6 item 6.3).
//
//  WHAT THESE PROVE
//  ----------------
//  Everything runs against a stubbed `AssessmentsProviding`: no network, no SwiftData, no page
//  cache, no Keychain. What they prove is the set of behaviours `features.md` §3 says must survive
//  the port, because those are the ones that are invisible when they break:
//
//    * cache-first paint, with the fetch behind it;
//    * a blocking spinner ONLY when there is nothing cached to show;
//    * an error screen ONLY when there is nothing to show — a failed refresh over warm data is a
//      notice and never clears the list;
//    * the generation + target guard: a slow answer for August cannot overwrite September;
//    * `.sessionExpired` logs out, `.forbidden` does not;
//    * the optimistic status flip, and its *visible* revert when W4 refuses the write;
//    * writes stay off — and the affordance stays inert — while the OQ-3 flag is off.
//
//  What they cannot prove is that W4 accepts a Confirm-done POST; that lives in
//  `AssessmentRepositoryTests` and, ultimately, in capture C-3.
//

import XCTest
@testable import BetterW4

// MARK: - Doubles

/// A one-shot latch two tasks can rendezvous on. Deterministic ordering without sleeping.
private actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

/// A mutable counter an `@Sendable` notification block may close over. Every access happens on the
/// posting thread, which in this test is always the main one.
private final class LogoutCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct RecordedFetch: Sendable {
    let month: AssessmentMonth
    let forceRefresh: Bool
}

private struct RecordedWrite: Sendable {
    let transition: AssessmentTransition
    let itemId: String
    let month: AssessmentMonth
}

/// The repository seam, scripted per month.
private actor StubAssessmentProvider: AssessmentsProviding {

    private var cached: [AssessmentMonth: W4Loaded<[Assessment]>] = [:]
    private var results: [AssessmentMonth: Result<W4Loaded<[Assessment]>, Error>] = [:]
    private var fallback: Result<W4Loaded<[Assessment]>, Error> =
        .success(W4Loaded([], freshness: .fresh))
    private var writesAllowed = false
    private var writeFailure: Error?

    /// Opened by the stub the moment a fetch for that month begins.
    private var fetchStarted: [AssessmentMonth: TestGate] = [:]
    /// Awaited by the stub before a fetch for that month returns.
    private var fetchRelease: [AssessmentMonth: TestGate] = [:]
    /// Opened when a write begins; awaited before it returns.
    private var writeStarted: TestGate?
    private var writeRelease: TestGate?

    private(set) var fetches: [RecordedFetch] = []
    private(set) var writes: [RecordedWrite] = []

    // MARK: Scripting

    func setCached(_ value: W4Loaded<[Assessment]>?, for month: AssessmentMonth) {
        cached[month] = value
    }

    func setResult(_ result: Result<W4Loaded<[Assessment]>, Error>, for month: AssessmentMonth) {
        results[month] = result
    }

    func setFallback(_ result: Result<W4Loaded<[Assessment]>, Error>) {
        fallback = result
    }

    func setWritesAllowed(_ allowed: Bool) {
        writesAllowed = allowed
    }

    func setWriteFailure(_ error: Error?) {
        writeFailure = error
    }

    func gateFetch(for month: AssessmentMonth, started: TestGate, release: TestGate) {
        fetchStarted[month] = started
        fetchRelease[month] = release
    }

    func gateWrite(started: TestGate, release: TestGate) {
        writeStarted = started
        writeRelease = release
    }

    // MARK: Seam

    func cachedAssessments(for month: AssessmentMonth) async -> W4Loaded<[Assessment]>? {
        cached[month]
    }

    func assessments(
        for month: AssessmentMonth,
        forceRefresh: Bool,
        priority: FetchPriority
    ) async throws -> W4Loaded<[Assessment]> {
        fetches.append(RecordedFetch(month: month, forceRefresh: forceRefresh))
        await fetchStarted[month]?.open()
        await fetchRelease[month]?.wait()
        return try (results[month] ?? fallback).get()
    }

    func canWrite(in month: AssessmentMonth) async -> Bool {
        writesAllowed
    }

    @discardableResult
    func apply(
        _ transition: AssessmentTransition,
        to item: Assessment,
        in month: AssessmentMonth
    ) async throws -> Assessment {
        writes.append(RecordedWrite(transition: transition, itemId: item.id, month: month))
        await writeStarted?.open()
        await writeRelease?.wait()
        if let writeFailure { throw writeFailure }
        var updated = item
        updated.status = transition.resultingStatus
        return updated
    }
}

// MARK: - Tests

@MainActor
final class AssessmentsViewModelTests: XCTestCase {

    private let august = AssessmentMonth(year: 2026, month: 8)
    private let september = AssessmentMonth(year: 2026, month: 9)

    /// Midday on 15 August 2026, Oslo. Every relative label in these tests is anchored to it.
    private var fixedNow: Date {
        W4Dates.date(year: 2026, month: 8, day: 15, hour: 12, minute: 0)
            ?? Date(timeIntervalSince1970: 1_786_000_000)
    }

    private var student: Student {
        Student(studentId: "nc26abcd", name: "Alex Andersen")
    }

    private func makeViewModel(_ provider: StubAssessmentProvider) -> AssessmentsViewModel {
        let anchor = fixedNow
        return AssessmentsViewModel(repository: provider, now: { anchor })
    }

    private func item(
        id: String,
        title: String = "Essay",
        subject: String? = "History",
        classCode: String? = "HIS HL",
        teacher: String? = "Peter Hansen",
        unit: String? = "Paper 2",
        day: Int? = 20,
        month: Int = 8,
        status: AssessmentStatus = .pending,
        kind: AssessmentKind = .classAssigned,
        isOverdue: Bool = false
    ) -> Assessment {
        Assessment(
            id: "\(kind.rawValue):\(id)",
            rawId: id,
            kind: kind,
            rawKind: kind.rawValue,
            title: title,
            subject: subject,
            classCode: classCode,
            teacher: teacher,
            unit: unit,
            dueDate: day.flatMap { W4Dates.date(year: 2026, month: month, day: $0) },
            daysLeft: nil,
            status: status,
            rawStatus: status.rawValue,
            isOverdue: isOverdue,
            isEditable: kind == .studentCreated,
            href: nil
        )
    }

    // MARK: Cache first (features.md §3 rules 2 and 3)

    func testCachedItemsPaintBeforeTheFetchAnswersAndSuppressTheSpinner() async throws {
        let provider = StubAssessmentProvider()
        let cachedAt = fixedNow.addingTimeInterval(-600)
        await provider.setCached(
            W4Loaded([item(id: "1")], freshness: .cached(fetchedAt: cachedAt, isStale: false)),
            for: august
        )
        await provider.setResult(
            .success(W4Loaded([item(id: "1"), item(id: "2", title: "Lab report")], freshness: .fresh)),
            for: august
        )

        let started = TestGate()
        let release = TestGate()
        await provider.gateFetch(for: august, started: started, release: release)

        let viewModel = makeViewModel(provider)
        let task = Task { await viewModel.load(for: student) }

        // While the fetch is in flight the cached copy is already on screen, and because there is
        // something to show there is no blocking spinner.
        await started.wait()
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isRefreshing)

        await release.open()
        await task.value

        XCTAssertEqual(viewModel.items.count, 2)
        XCTAssertEqual(viewModel.freshness, .fresh)
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testTheBlockingSpinnerAppearsOnlyWhenThereIsNothingCached() async throws {
        let provider = StubAssessmentProvider()
        await provider.setCached(nil, for: august)
        await provider.setResult(.success(W4Loaded([item(id: "1")], freshness: .fresh)), for: august)

        let started = TestGate()
        let release = TestGate()
        await provider.gateFetch(for: august, started: started, release: release)

        let viewModel = makeViewModel(provider)
        let task = Task { await viewModel.load(for: student) }

        await started.wait()
        XCTAssertTrue(viewModel.isLoading)

        await release.open()
        await task.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.items.count, 1)
    }

    func testPullToRefreshAlwaysGoesToTheNetwork() async throws {
        let provider = StubAssessmentProvider()
        await provider.setCached(
            W4Loaded([item(id: "1")], freshness: .cached(fetchedAt: fixedNow, isStale: false)),
            for: august
        )
        await provider.setResult(.success(W4Loaded([item(id: "1")], freshness: .fresh)), for: august)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)
        await viewModel.refresh(for: student)

        let fetches = await provider.fetches
        XCTAssertEqual(fetches.count, 2)
        XCTAssertFalse(fetches[0].forceRefresh)
        XCTAssertTrue(fetches[1].forceRefresh)
    }

    // MARK: Generation + target guard (features.md §3 rule 1)

    func testASlowAnswerForTheOldMonthCannotOverwriteANewerSelection() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded([item(id: "aug", title: "August essay")], freshness: .fresh)),
            for: august
        )
        await provider.setResult(
            .success(W4Loaded([item(id: "sep", title: "September essay", day: 9, month: 9)],
                              freshness: .fresh)),
            for: september
        )

        let augustStarted = TestGate()
        let augustRelease = TestGate()
        await provider.gateFetch(for: august, started: augustStarted, release: augustRelease)

        let viewModel = makeViewModel(provider)
        let slowAugust = Task { await viewModel.load(for: student) }
        await augustStarted.wait()

        // The student flips to September while August is still in flight.
        await viewModel.showMonth(offsetBy: 1, for: student)
        XCTAssertEqual(viewModel.month, september)
        XCTAssertEqual(viewModel.items.map(\.rawId), ["sep"])

        // August finally answers. It must be dropped on the floor.
        await augustRelease.open()
        await slowAugust.value

        XCTAssertEqual(viewModel.month, september)
        XCTAssertEqual(viewModel.items.map(\.rawId), ["sep"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testSwitchingAccountClearsInMemoryState() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(.success(W4Loaded([item(id: "1")], freshness: .fresh)), for: august)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)
        viewModel.selectDay(W4Dates.date(year: 2026, month: 8, day: 20))
        XCTAssertNotNil(viewModel.selectedDay)

        await provider.setResult(.success(W4Loaded([], freshness: .demo)), for: august)
        await viewModel.load(for: .demo)

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.selectedDay)
    }

    // MARK: Errors (features.md §3 rules 4 and 6)

    func testAFailedRefreshOverWarmDataBecomesANoticeAndKeepsTheList() async throws {
        let provider = StubAssessmentProvider()
        await provider.setCached(
            W4Loaded([item(id: "1")], freshness: .cached(fetchedAt: fixedNow, isStale: true)),
            for: august
        )
        await provider.setResult(
            .failure(W4Error.httpError(status: 500, route: "academics/deadlines")),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        XCTAssertEqual(viewModel.items.count, 1, "A transient error must never wipe cached data")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.notice)
        XCTAssertTrue(viewModel.isShowingStaleData)

        viewModel.dismissNotice()
        XCTAssertNil(viewModel.notice)
    }

    func testAnErrorWithNothingCachedBecomesTheErrorScreen() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(.failure(W4Error.noResponse), for: august)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertNil(viewModel.notice)
        XCTAssertEqual(viewModel.errorMessage, W4Error.noResponse.errorDescription)
    }

    func testSessionExpiredLogsOutButForbiddenDoesNot() async throws {
        // `queue: nil` on purpose: the block then runs synchronously on the posting thread, so the
        // count is settled by the time `load` returns. `.main` would deliver via an operation and
        // race the assertions.
        let counter = LogoutCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .w4SessionExpired,
            object: nil,
            queue: nil
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(token) }

        let forbidden = StubAssessmentProvider()
        await forbidden.setResult(.failure(W4Error.forbidden), for: august)
        await makeViewModel(forbidden).load(for: student)
        XCTAssertEqual(
            counter.count, 0,
            "403 without Login Required is the wrong role, not a dead session"
        )

        let expired = StubAssessmentProvider()
        await expired.setResult(.failure(W4Error.sessionExpired), for: august)
        await makeViewModel(expired).load(for: student)
        XCTAssertEqual(counter.count, 1)
    }

    // MARK: Writes

    func testWritesStayInertWhileTheFeatureGateIsClosed() async throws {
        let provider = StubAssessmentProvider()
        await provider.setWritesAllowed(false)
        await provider.setResult(.success(W4Loaded([item(id: "1")], freshness: .fresh)), for: august)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)
        XCTAssertFalse(viewModel.writesAvailable)

        let target = try XCTUnwrap(viewModel.items.first)
        await viewModel.toggleStatus(of: target)

        let writes = await provider.writes
        XCTAssertTrue(writes.isEmpty, "A closed gate must not post anything")
        XCTAssertEqual(viewModel.items.first?.status, .pending)
    }

    func testConfirmDoneFlipsOptimisticallyAndKeepsTheServerAnswer() async throws {
        let provider = StubAssessmentProvider()
        await provider.setWritesAllowed(true)
        await provider.setResult(.success(W4Loaded([item(id: "1")], freshness: .fresh)), for: august)

        let started = TestGate()
        let release = TestGate()
        await provider.gateWrite(started: started, release: release)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)
        XCTAssertTrue(viewModel.writesAvailable)

        let target = try XCTUnwrap(viewModel.items.first)
        let task = Task { await viewModel.toggleStatus(of: target) }

        // The row flips before the request has returned — that is the whole point of "optimistic".
        await started.wait()
        XCTAssertEqual(viewModel.items.first?.status, .done)
        XCTAssertTrue(viewModel.isPendingWrite(target))

        await release.open()
        await task.value

        XCTAssertEqual(viewModel.items.first?.status, .done)
        XCTAssertFalse(viewModel.isPendingWrite(target))
        XCTAssertNil(viewModel.notice)

        let writes = await provider.writes
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.transition, .confirmDone)
        XCTAssertEqual(writes.first?.itemId, "class:1")
        XCTAssertEqual(writes.first?.month, august)
    }

    func testADoneItemOffersRevertToPending() async throws {
        let provider = StubAssessmentProvider()
        await provider.setWritesAllowed(true)
        await provider.setResult(
            .success(W4Loaded([item(id: "1", status: .done)], freshness: .fresh)),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        let target = try XCTUnwrap(viewModel.items.first)
        await viewModel.toggleStatus(of: target)

        let writes = await provider.writes
        XCTAssertEqual(writes.first?.transition, .revertToPending)
        XCTAssertEqual(viewModel.items.first?.status, .pending)
    }

    func testAFailedWriteRevertsTheFlipVisiblyAndExplainsItself() async throws {
        let provider = StubAssessmentProvider()
        await provider.setWritesAllowed(true)
        await provider.setResult(.success(W4Loaded([item(id: "1")], freshness: .fresh)), for: august)
        await provider.setWriteFailure(W4Error.serverConflict("Deadline is locked"))

        let started = TestGate()
        let release = TestGate()
        await provider.gateWrite(started: started, release: release)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        let target = try XCTUnwrap(viewModel.items.first)
        let task = Task { await viewModel.toggleStatus(of: target) }

        await started.wait()
        XCTAssertEqual(viewModel.items.first?.status, .done, "the optimistic flip must be visible")

        await release.open()
        await task.value

        XCTAssertEqual(viewModel.items.first?.status, .pending, "and it must visibly revert")
        XCTAssertFalse(viewModel.isPendingWrite(target))
        XCTAssertEqual(viewModel.notice, W4Error.serverConflict("Deadline is locked").errorDescription)
    }

    // MARK: Grouping, labels and the month grid

    func testItemsGroupByDayWithEnglishTitles() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded(
                [
                    item(id: "today", title: "Reading", day: 15),
                    item(id: "tomorrow", title: "Problem set", day: 16),
                    item(id: "later", title: "Oral", day: 24),
                    item(id: "undated", title: "Unknown deadline", day: nil)
                ],
                freshness: .fresh
            )),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        let groups = viewModel.dayGroups
        XCTAssertEqual(groups.map(\.title), ["Today", "Tomorrow", "Monday 24 August", "No date"])
        XCTAssertEqual(groups.last?.day, nil)
        XCTAssertEqual(groups.first?.items.count, 1)
    }

    func testDueLabelsAreEnglishAndRelative() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded(
                [
                    item(id: "a", day: 15),
                    item(id: "b", day: 16),
                    item(id: "c", day: 19),
                    item(id: "d", day: 14),
                    item(id: "e", day: 10),
                    item(id: "f", day: nil)
                ],
                freshness: .fresh
            )),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        let labels = viewModel.items.map { viewModel.dueLabel(for: $0) }
        XCTAssertEqual(labels, ["Today", "Tomorrow", "in 4 days", "1 day late", "5 days late", nil])
    }

    func testOverdueIsUnfinishedAndInThePast() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded(
                [
                    item(id: "late", day: 10),
                    item(id: "lateButDone", day: 10, status: .done),
                    item(id: "upcoming", day: 20)
                ],
                freshness: .fresh
            )),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        XCTAssertEqual(viewModel.overdueCount, 1)
        XCTAssertTrue(viewModel.isOverdue(viewModel.items[0]))
        XCTAssertFalse(viewModel.isOverdue(viewModel.items[1]))
        XCTAssertFalse(viewModel.isOverdue(viewModel.items[2]))
    }

    func testTheMonthGridIsWholeMondayFirstWeeksAndCountsItems() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded(
                [item(id: "1", day: 20), item(id: "2", day: 20), item(id: "3", day: 10)],
                freshness: .fresh
            )),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        let days = viewModel.calendarDays
        // 1 August 2026 is a Saturday, so a Monday-first grid needs 5 leading days and 6 rows.
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.date, W4Dates.date(year: 2026, month: 7, day: 27))
        XCTAssertEqual(days.filter(\.isInMonth).count, 31)
        XCTAssertEqual(days.filter(\.isToday).count, 1)

        let twentieth = try XCTUnwrap(days.first { $0.dayNumber == 20 && $0.isInMonth })
        XCTAssertEqual(twentieth.total, 2)
        XCTAssertEqual(twentieth.pending, 2)
        XCTAssertEqual(twentieth.overdue, 0)

        let tenth = try XCTUnwrap(days.first { $0.dayNumber == 10 && $0.isInMonth })
        XCTAssertEqual(tenth.overdue, 1)
    }

    func testSelectingADayFiltersTheListAndTappingItAgainClearsIt() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded([item(id: "1", day: 20), item(id: "2", day: 24)], freshness: .fresh)),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)
        XCTAssertEqual(viewModel.visibleItems.count, 2)

        let twentieth = W4Dates.date(year: 2026, month: 8, day: 20)
        viewModel.selectDay(twentieth)
        XCTAssertEqual(viewModel.visibleItems.map(\.rawId), ["1"])
        XCTAssertEqual(viewModel.selectedDayTitle, "Thursday 20 August")

        viewModel.selectDay(twentieth)
        XCTAssertNil(viewModel.selectedDay)
        XCTAssertEqual(viewModel.visibleItems.count, 2)
    }

    func testEmptyStateCopyIsEnglishAndSaysWhichEmptinessItMeans() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(.success(W4Loaded([], freshness: .fresh)), for: august)

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        XCTAssertEqual(viewModel.monthTitle, "August 2026")
        XCTAssertEqual(viewModel.emptyStateTitle, "No assessments this month")

        viewModel.selectDay(W4Dates.date(year: 2026, month: 8, day: 20))
        XCTAssertEqual(viewModel.emptyStateTitle, "Nothing due on this day")
    }

    func testMonthNavigationRollsTheYearOverAndTodayComesBack() async throws {
        let provider = StubAssessmentProvider()
        await provider.setFallback(.success(W4Loaded([], freshness: .fresh)))

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)
        XCTAssertTrue(viewModel.isShowingCurrentMonth)

        for _ in 0..<5 {
            await viewModel.showMonth(offsetBy: 1, for: student)
        }
        XCTAssertEqual(viewModel.month, AssessmentMonth(year: 2027, month: 1))
        XCTAssertEqual(viewModel.monthTitle, "January 2027")
        XCTAssertFalse(viewModel.isShowingCurrentMonth)

        await viewModel.showCurrentMonth(for: student)
        XCTAssertEqual(viewModel.month, august)
        XCTAssertTrue(viewModel.isShowingCurrentMonth)
    }

    func testDemoFreshnessIsLabelledHonestly() async throws {
        let provider = StubAssessmentProvider()
        await provider.setWritesAllowed(true)
        await provider.setResult(
            .success(W4Loaded([item(id: "1", subject: nil, classCode: nil, teacher: nil,
                                    unit: nil, kind: .studentCreated)], freshness: .demo)),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: .demo)

        XCTAssertEqual(viewModel.freshnessLabel, "Demo data. Not connected to W4.")
        XCTAssertFalse(viewModel.isShowingStaleData)
        XCTAssertEqual(viewModel.subtitle(for: viewModel.items[0]), "Added by you")
    }

    func testSubtitleJoinsWhicheverPartsW4Gave() async throws {
        let provider = StubAssessmentProvider()
        await provider.setResult(
            .success(W4Loaded(
                [
                    item(id: "full"),
                    item(id: "subjectOnly", classCode: nil, teacher: nil),
                    item(id: "sameCode", subject: "Biology", classCode: "Biology", teacher: nil)
                ],
                freshness: .fresh
            )),
            for: august
        )

        let viewModel = makeViewModel(provider)
        await viewModel.load(for: student)

        XCTAssertEqual(viewModel.subtitle(for: viewModel.items[0]), "History · HIS HL · Peter Hansen")
        XCTAssertEqual(viewModel.subtitle(for: viewModel.items[1]), "History")
        XCTAssertEqual(viewModel.subtitle(for: viewModel.items[2]), "Biology")
    }
}
