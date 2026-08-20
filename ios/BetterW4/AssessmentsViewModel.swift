//
//  AssessmentsViewModel.swift
//  BetterW4
//
//  The view model behind the Assessments tab — W4's `index.php?r=academics/deadlines`, the one
//  surface that replaces BOTH of the app's former homework and assignment screens
//  (`features.md` §1.3, `ui.md` §4.5, plan Wave 6 item 6.3).
//
//  It never talks to the network, a parser or a store: everything comes from
//  `AssessmentRepository`, which owns caching, the demo branch and the optimistic overlay. This
//  file owns only what a screen needs — which month is showing, which day is filtered, how the
//  items group by day, and whether a write may be offered at all.
//
//  The five behaviours from `features.md` §3 that this file exists to preserve:
//    1. Generation + target guard. Every load takes a `UUID` and remembers the month it was
//       started for; nothing is published unless BOTH still match. A slow response for August can
//       never overwrite a September selection, and a demo→real switch cannot cross-contaminate.
//    2. Cache first, then refresh. `cachedAssessments` paints immediately; the fetch follows.
//    3. A blocking spinner ONLY when there is nothing cached to show. A refresh over populated
//       content sets `isRefreshing`, which the screen renders as a hairline, not a takeover.
//    4. An error message ONLY when there is nothing to show. With a warm cache a failed refresh is
//       a `notice`, and `items` is never cleared.
//    5. `.sessionExpired` — and only `.sessionExpired` — logs the student out, via
//       `W4Error.notifyIfSessionExpired()`. `.forbidden` deliberately does not.
//
//  Writes (Confirm done / Revert to pending) are gated twice: `AssessmentFeatureFlags.writesEnabled`
//  (OQ-3 — the POST payloads have never been verified) and whether W4 actually published the
//  endpoint on the page we read. `writesAvailable` collapses both into one flag so the screen can
//  render a read-only status instead of a button that would silently do nothing.
//

import Combine
import Foundation

// MARK: - Repository seam

/// The four repository calls this screen makes, and nothing else.
///
/// It exists so the view model can be tested without SwiftData, a page cache or a Keychain entry;
/// `AssessmentRepository` conforms as-is, so production takes the real actor with no adapter.
protocol AssessmentsProviding: Sendable {

    func cachedAssessments(for month: AssessmentMonth) async -> W4Loaded<[Assessment]>?

    func assessments(
        for month: AssessmentMonth,
        forceRefresh: Bool,
        priority: FetchPriority
    ) async throws -> W4Loaded<[Assessment]>

    /// Whether Confirm done / Revert to pending may be offered at all.
    func canWrite(in month: AssessmentMonth) async -> Bool

    @discardableResult
    func apply(
        _ transition: AssessmentTransition,
        to item: Assessment,
        in month: AssessmentMonth
    ) async throws -> Assessment
}

extension AssessmentRepository: AssessmentsProviding {}

// MARK: - Presentation values

/// One day's worth of assessments, ready to render as a section.
struct AssessmentDayGroup: Identifiable, Sendable {
    /// Midnight Oslo on the due day, or `nil` for items W4 gave no date at all.
    let day: Date?
    /// "Today", "Tomorrow", "Monday 17 August", or "No date".
    let title: String
    let items: [Assessment]

    var id: String {
        guard let day else { return "undated" }
        return String(Int(day.timeIntervalSince1970))
    }

    var pendingCount: Int { items.filter { $0.status == .pending }.count }
}

/// One cell of the month grid.
struct AssessmentCalendarDay: Identifiable, Sendable, Hashable {
    /// Midnight Oslo.
    let date: Date
    let dayNumber: Int
    /// False for the leading/trailing days borrowed from the neighbouring months.
    let isInMonth: Bool
    let isToday: Bool
    let total: Int
    let pending: Int
    let overdue: Int

    var id: Date { date }
    var hasItems: Bool { total > 0 }
}

/// Per-day tallies while the month grid is being built.
private struct DayCounts {
    var total = 0
    var pending = 0
    var overdue = 0
}

/// How the screen is presenting the month.
enum AssessmentDisplayMode: String, CaseIterable, Sendable {
    case list
    case month

    var title: String {
        switch self {
        case .list: return "List"
        case .month: return "Month"
        }
    }
}

// MARK: - View model

@MainActor
final class AssessmentsViewModel: ObservableObject {

    // MARK: Published state

    /// Server truth for the displayed month, with any optimistic overlay already applied by the
    /// repository, soonest-due first.
    @Published private(set) var items: [Assessment] = []
    /// The month the screen is showing. Never written directly by the view.
    @Published private(set) var month: AssessmentMonth = .current()
    /// Blocking spinner. True only while a fetch runs with nothing cached to show.
    @Published private(set) var isLoading = false
    /// A refresh is in flight over content that is already on screen.
    @Published private(set) var isRefreshing = false
    /// Set only when there is nothing on screen; otherwise a failure becomes `notice`.
    @Published private(set) var errorMessage: String?
    /// A transient, non-blocking message: a refresh that failed over warm data, or a write W4
    /// rejected. The screen shows it as a dismissible banner.
    @Published private(set) var notice: String?
    /// Where `items` came from, so the screen can be honest about staleness.
    @Published private(set) var freshness: W4Freshness?
    /// True only when the OQ-3 flag is on *and* W4 published an endpoint for this month, or in
    /// demo. False means the screen must render status read-only.
    @Published private(set) var writesAvailable = false
    /// Ids whose Confirm done / Revert to pending POST is still in flight.
    @Published private(set) var pendingWrites: Set<String> = []
    /// The day tapped in the month grid, or `nil` for "the whole month".
    @Published var selectedDay: Date?
    /// Whether the month grid sits above the list. The grid is additive — the day list is always
    /// rendered — so `.month` is "calendar plus list" and `.list` is the list on its own.
    @Published var displayMode: AssessmentDisplayMode = .month

    // MARK: Guards

    /// `features.md` §3 rule 1. Every published mutation is behind `isCurrent(_:_:)`.
    private var loadGeneration: UUID?
    /// The month the in-flight load was started for — the "target" half of the guard.
    private var loadTarget: AssessmentMonth?
    /// `features.md` §3 rule 5: a demo ⇄ real switch clears in-memory state.
    private var activeStudentId: String?

    private let repository: any AssessmentsProviding
    private let now: @Sendable () -> Date

    init(
        repository: any AssessmentsProviding = AssessmentRepository.shared,
        now: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        self.repository = repository
        self.now = now
        self.month = AssessmentMonth.current(now())
    }

    // MARK: - Derived state

    /// `items` narrowed to `selectedDay` when the student tapped a day in the grid.
    var visibleItems: [Assessment] {
        guard let selectedDay else { return items }
        return items.filter { item in
            guard let due = item.dueDate else { return false }
            return W4Dates.isSameDay(due, selectedDay)
        }
    }

    /// The list, grouped into day sections. Dated days ascending, undated last.
    var dayGroups: [AssessmentDayGroup] {
        let today = W4Dates.startOfDay(now())
        var byDay: [Date: [Assessment]] = [:]
        var undated: [Assessment] = []

        for item in visibleItems {
            guard let due = item.dueDate else {
                undated.append(item)
                continue
            }
            byDay[W4Dates.startOfDay(due), default: []].append(item)
        }

        var groups = byDay.keys.sorted().map { day in
            AssessmentDayGroup(
                day: day,
                title: AssessmentsViewModel.dayTitle(for: day, today: today),
                items: byDay[day] ?? []
            )
        }
        if !undated.isEmpty {
            groups.append(
                AssessmentDayGroup(day: nil, title: "No date", items: undated)
            )
        }
        return groups
    }

    /// The month grid: whole weeks, Monday-first, with the neighbouring days that pad them out.
    var calendarDays: [AssessmentCalendarDay] {
        let calendar = W4Dates.calendar
        guard let firstOfMonth = W4Dates.date(year: month.year, month: month.month, day: 1),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        // `firstWeekday` is Monday (2) on `W4Dates.calendar`, so this is 0 for a Monday.
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = dayRange.count
        let cellCount = Int(ceil(Double(leading + dayCount) / 7.0)) * 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstOfMonth) else {
            return []
        }

        let today = W4Dates.startOfDay(now())
        var countsByDay: [Date: DayCounts] = [:]
        for item in items {
            guard let due = item.dueDate else { continue }
            let day = W4Dates.startOfDay(due)
            var counts = countsByDay[day] ?? DayCounts()
            counts.total += 1
            if item.status == .pending { counts.pending += 1 }
            if AssessmentsViewModel.isOverdue(item, today: today) { counts.overdue += 1 }
            countsByDay[day] = counts
        }

        return (0..<cellCount).compactMap { offset -> AssessmentCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let day = W4Dates.startOfDay(date)
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let counts = countsByDay[day] ?? DayCounts()
            return AssessmentCalendarDay(
                date: day,
                dayNumber: components.day ?? 0,
                isInMonth: components.year == month.year && components.month == month.month,
                isToday: day == today,
                total: counts.total,
                pending: counts.pending,
                overdue: counts.overdue
            )
        }
    }

    /// "Today" / "Monday 17 August" for the day tapped in the grid, or `nil` when nothing is
    /// filtered. The chip needs this even on a day with no items, where `dayGroups` is empty.
    var selectedDayTitle: String? {
        guard let selectedDay else { return nil }
        return AssessmentsViewModel.dayTitle(for: selectedDay, today: W4Dates.startOfDay(now()))
    }

    /// "August 2026".
    var monthTitle: String {
        guard let first = W4Dates.date(year: month.year, month: month.month, day: 1) else {
            return month.key
        }
        return AssessmentsViewModel.monthTitleFormatter.string(from: first)
    }

    /// True when the screen is already on the month containing today.
    var isShowingCurrentMonth: Bool {
        month == AssessmentMonth.current(now())
    }

    var pendingCount: Int { items.filter { $0.status == .pending }.count }

    var overdueCount: Int {
        let today = W4Dates.startOfDay(now())
        return items.filter { AssessmentsViewModel.isOverdue($0, today: today) }.count
    }

    /// "Demo data. Not connected to W4." / "Updated 5 minutes ago" / nil when freshly fetched.
    var freshnessLabel: String? {
        guard let freshness else { return nil }
        switch freshness {
        case .demo:
            return "Demo data. Not connected to W4."
        case .cached(let fetchedAt, _):
            let relative = AssessmentsViewModel.relativeFormatter.localizedString(
                for: fetchedAt,
                relativeTo: now()
            )
            return "Updated \(relative)"
        case .fresh:
            return nil
        }
    }

    /// Whether the freshness label should be rendered as a warning rather than a footnote.
    var isShowingStaleData: Bool {
        guard let freshness, case .cached(_, let isStale) = freshness else { return false }
        return isStale
    }

    /// The empty-state copy: the same screen means two different things with and without a filter.
    var emptyStateTitle: String {
        selectedDay == nil ? "No assessments this month" : "Nothing due on this day"
    }

    var emptyStateMessage: String {
        selectedDay == nil
            ? "Nothing is due in \(monthTitle)."
            : "Pick another day, or clear the filter to see the whole month."
    }

    func isPendingWrite(_ item: Assessment) -> Bool {
        pendingWrites.contains(item.id)
    }

    func isOverdue(_ item: Assessment) -> Bool {
        AssessmentsViewModel.isOverdue(item, today: W4Dates.startOfDay(now()))
    }

    /// "Today" / "Tomorrow" / "in 4 days" / "2 days late" / nil when W4 gave no date.
    func dueLabel(for item: Assessment) -> String? {
        let today = W4Dates.startOfDay(now())
        guard let days = AssessmentsViewModel.daysLeft(for: item, today: today) else { return nil }
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "1 day late"
        default: return days < 0 ? "\(-days) days late" : "in \(days) days"
        }
    }

    /// "Biology · BIO HL · Jane Doe" — whichever parts W4 gave us.
    func subtitle(for item: Assessment) -> String? {
        var parts: [String] = []
        if let subject = item.subject, !subject.isEmpty { parts.append(subject) }
        if let classCode = item.classCode, !classCode.isEmpty, classCode != item.subject {
            parts.append(classCode)
        }
        if let teacher = item.teacher, !teacher.isEmpty { parts.append(teacher) }
        if parts.isEmpty, item.kind == .studentCreated { parts.append("Added by you") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The subject-ish token used for the icon and colour. Student-created items have no subject,
    /// so they fall back to their own title, which `SubjectMapper` hashes into a stable hue.
    func iconToken(for item: Assessment) -> String {
        item.classCode ?? item.subject ?? item.title
    }

    // MARK: - Loading

    /// The screen's `.task(id:)` entry point: cache first, then refresh.
    func load(for student: Student) async {
        await load(for: student, month: month, forceRefresh: false)
    }

    /// Pull-to-refresh. Always goes to W4, and never wipes what is already on screen.
    func refresh(for student: Student) async {
        await load(for: student, month: month, forceRefresh: true)
    }

    /// Month navigation. `delta` is in whole months.
    func showMonth(offsetBy delta: Int, for student: Student) async {
        await load(for: student, month: month.offset(byMonths: delta), forceRefresh: false)
    }

    /// The "Today" button in the toolbar.
    func showCurrentMonth(for student: Student) async {
        await load(for: student, month: AssessmentMonth.current(now()), forceRefresh: false)
    }

    func selectDay(_ day: Date?) {
        guard let day else {
            selectedDay = nil
            return
        }
        let normalized = W4Dates.startOfDay(day)
        selectedDay = (selectedDay.map { W4Dates.isSameDay($0, normalized) } ?? false)
            ? nil
            : normalized
    }

    func dismissNotice() {
        notice = nil
    }

    private func load(for student: Student, month target: AssessmentMonth, forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation
        loadTarget = target

        // Rule 5: a different account (including demo ⇄ real) starts from nothing.
        if activeStudentId != student.studentId {
            items = []
            freshness = nil
            selectedDay = nil
            pendingWrites = []
            writesAvailable = false
            errorMessage = nil
            notice = nil
        }
        activeStudentId = student.studentId

        if month != target {
            month = target
            items = []
            freshness = nil
            selectedDay = nil
            errorMessage = nil
        }

        // Rule 2: paint whatever is on disk before anything can go wrong.
        if !forceRefresh, let cached = await repository.cachedAssessments(for: target) {
            guard isCurrent(generation, target) else { return }
            items = cached.value
            freshness = cached.freshness
            errorMessage = nil
        }
        guard isCurrent(generation, target) else { return }

        // Rule 3: the blocking spinner only exists for the empty case.
        isLoading = items.isEmpty
        isRefreshing = true
        defer {
            if isCurrent(generation, target) {
                isLoading = false
                isRefreshing = false
            }
        }

        await refreshWriteAvailability(generation, target)

        do {
            let loaded = try await repository.assessments(
                for: target,
                forceRefresh: forceRefresh,
                priority: .important
            )
            guard isCurrent(generation, target) else { return }
            items = loaded.value
            freshness = loaded.freshness
            errorMessage = nil
            await refreshWriteAvailability(generation, target)
            // Due-date reminders are scheduled from whatever month is loaded. The scheduler
            // treats this as the complete set and clears anything not in it, which is what makes
            // an assessment marked done on the server stop reminding.
            await NotificationScheduler.shared.updateAssessments(
                loaded.value,
                isDemo: loaded.freshness == .demo
            )
        } catch {
            guard isCurrent(generation, target) else { return }
            // Rule 7: a cancelled load is not a failure and must not be shown.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }

            (error as? W4Error)?.notifyIfSessionExpired()
            ReviewPromptCoordinator.shared.reportRecentError()

            let message = AssessmentsViewModel.message(for: error)
            // Rule 4: an error screen only when there is genuinely nothing to show.
            if items.isEmpty {
                errorMessage = message
            } else {
                notice = message
            }
        }
    }

    private func refreshWriteAvailability(_ generation: UUID, _ target: AssessmentMonth) async {
        let allowed = await repository.canWrite(in: target)
        guard isCurrent(generation, target) else { return }
        writesAvailable = allowed
    }

    /// Rule 1: generation **and** target. Either one alone lets a stale response through.
    private func isCurrent(_ generation: UUID, _ target: AssessmentMonth) -> Bool {
        loadGeneration == generation && loadTarget == target && month == target
    }

    // MARK: - Writing

    /// Confirm done / Revert to pending, optimistically.
    ///
    /// The row flips before the request leaves and flips back — visibly — if W4 refuses it. The
    /// repository writes the same flip into its overlay store, so a refresh that lands mid-write
    /// does not undo the tap either.
    func toggleStatus(of item: Assessment) async {
        guard writesAvailable else { return }
        guard !pendingWrites.contains(item.id) else { return }

        let transition = item.offeredTransition
        let previousStatus = item.status
        let target = month

        pendingWrites.insert(item.id)
        applyStatusLocally(transition.resultingStatus, to: item.id)

        defer { pendingWrites.remove(item.id) }

        do {
            let updated = try await repository.apply(transition, to: item, in: target)
            guard month == target else { return }
            applyStatusLocally(updated.status, to: item.id)
            if transition == .confirmDone {
                ReviewPromptCoordinator.shared.maybePrompt(.homeworkDone)
            }
        } catch {
            guard month == target else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                applyStatusLocally(previousStatus, to: item.id)
                return
            }
            // Visible revert: a write that fails silently is the worst outcome this surface has.
            applyStatusLocally(previousStatus, to: item.id)
            (error as? W4Error)?.notifyIfSessionExpired()
            ReviewPromptCoordinator.shared.reportRecentError()
            notice = AssessmentsViewModel.message(for: error)
        }
    }

    /// Looks the row up by id rather than index: a refresh may have reordered `items` since the tap.
    private func applyStatusLocally(_ status: AssessmentStatus, to id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].status != status else { return }
        items[index].status = status
    }

    // MARK: - Pure helpers

    static func isOverdue(_ item: Assessment, today: Date) -> Bool {
        guard item.status == .pending else { return false }
        if item.isOverdue { return true }
        guard let due = item.dueDate else { return false }
        return W4Dates.startOfDay(due) < today
    }

    /// W4's own countdown when it published one, otherwise whole Oslo days to the due date.
    static func daysLeft(for item: Assessment, today: Date) -> Int? {
        if let due = item.dueDate {
            let components = W4Dates.calendar.dateComponents(
                [.day],
                from: today,
                to: W4Dates.startOfDay(due)
            )
            if let days = components.day { return days }
        }
        return item.daysLeft
    }

    static func dayTitle(for day: Date, today: Date) -> String {
        let difference = W4Dates.calendar.dateComponents([.day], from: today, to: day).day
        switch difference {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return sectionDateFormatter.string(from: day)
        }
    }

    /// `LocalizedError.errorDescription` when the error has one, so `W4Error`'s English copy wins
    /// over `localizedDescription`'s generic wrapper.
    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? (error as NSError).localizedDescription
    }

    // MARK: Formatters

    // Pinned to Oslo and `en_GB_POSIX` (plan D-11): the month name must read the same on a phone
    // set to Danish, and W4 itself renders English.

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = W4Dates.locale
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = W4Dates.locale
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.unitsStyle = .full
        return formatter
    }()
}
