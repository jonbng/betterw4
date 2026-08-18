//
//  ScheduleViewModel.swift
//  BetterW4
//
//  The Timetable tab's state. Its only collaborator is `TimetableRepository` (plan Wave 6.1):
//  never the HTTP client, never a parser. The repository already merges Academics with Extra
//  Academics, caches every page, falls back to stored lessons and branches on demo mode, so this
//  file is exactly two things — a per-week store keyed by ISO week, and the rules from
//  `features.md` §3 about when a response is allowed to overwrite what is already on screen.
//
//  Those rules, spelled out because they are the whole point:
//
//    * **Generation guard.** Every load for a week takes a token. A response applies only while
//      its token is still the newest one for that week, so a slow answer for week 33 can never
//      land on top of a fresh one the student just pulled.
//    * **Cache first, then refresh.** `cachedWeek(containing:)` paints before anything touches the
//      network; the fetch that follows only ever replaces the copy on screen.
//    * **Spinner only when empty.** `isLoading` is true only when the *selected* week has nothing
//      to show at all. A refresh over a painted week is `isRefreshing`, which is a banner.
//    * **A failure never wipes data.** Every error branch touches `errorMessage` and nothing else.
//    * **Only `.sessionExpired` logs out.** `.forbidden` is a role check, not a dead session
//      (plan D-21), so it surfaces as a message and the student stays signed in.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ScheduleViewModel: ObservableObject {

    // MARK: - Published state

    /// Loaded weeks, keyed by `ScheduleIdentity.weekKey` (`"2026-W33"`). Keeping neighbours around
    /// is what lets the day pager swipe across a week boundary without blanking.
    @Published private(set) var weeks: [String: ScheduleWeek] = [:]

    /// Where each loaded week came from, so the UI can say "last updated …" honestly.
    @Published private(set) var freshnessByWeek: [String: W4Freshness] = [:]

    /// The day the pager is showing, normalised to the start of the Oslo day.
    @Published private(set) var selectedDate: Date

    /// True only while the selected week has nothing at all to render.
    @Published private(set) var isLoading = false

    /// True while any week is being refreshed behind data that is already on screen.
    @Published private(set) var isRefreshing = false

    /// The last failure, in English. Never cleared by a failure, never accompanied by a data wipe.
    @Published var errorMessage: String?

    /// D-18: W4's `?year=&week=` support is a probe, not a promise. When the probe fails the
    /// previous/next-week controls switch off rather than silently mislabelling a week.
    @Published private(set) var weekNavigationAvailable = true

    // MARK: - Collaborators

    private let repository: TimetableRepository
    private let clock: @Sendable () -> Date

    /// Newest load token per week key — the generation guard.
    private var tokens: [String: Int] = [:]
    /// How many loads are in flight per week key, so a pager that oscillates does not queue
    /// duplicates and a finishing load does not clear the banner of one still running.
    private var loadsInFlight: [String: Int] = [:]

    init(
        repository: TimetableRepository = .shared,
        clock: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        self.repository = repository
        self.clock = clock
        self.selectedDate = W4Dates.startOfDay(clock())
    }

    // MARK: - Derived reads

    /// Start of today, Oslo.
    var today: Date { W4Dates.startOfDay(clock()) }

    var selectedWeekKey: String { ScheduleIdentity.weekKey(for: selectedDate) }

    var selectedWeek: ScheduleWeek? { weeks[selectedWeekKey] }

    var selectedFreshness: W4Freshness? { freshnessByWeek[selectedWeekKey] }

    /// ISO week number of the selected day, for the floating badge.
    var selectedWeekNumber: Int { W4Dates.isoWeek(of: selectedDate).week }

    func week(containing date: Date) -> ScheduleWeek? {
        weeks[ScheduleIdentity.weekKey(for: date)]
    }

    func hasLoadedWeek(containing date: Date) -> Bool {
        week(containing: date) != nil
    }

    func day(on date: Date) -> ScheduleDay? {
        week(containing: date)?.day(on: date)
    }

    func events(on date: Date) -> [TimetableEvent] {
        SchoolCalendar.visibleEvents(
            day(on: date)?.events ?? [],
            showSchoolCalendar: SettingsStore.shared.showSchoolCalendar
        )
    }

    /// Reloads the visible weeks if the school calendar was just turned on and
    /// none of the in-memory weeks already carry overlay events.
    func applySchoolCalendarPreference() async {
        guard SettingsStore.shared.showSchoolCalendar else { return }
        let alreadyOverlaid = weeks.values.contains { week in
            week.allEvents.contains(where: SchoolCalendar.isSchoolCalendarEvent)
        }
        if !alreadyOverlaid {
            await refresh()
        }
    }

    /// Blocks with a real time range, earliest first.
    func timedEvents(on date: Date) -> [TimetableEvent] {
        events(on: date).timed
    }

    /// All-day blocks, plus anything W4 gave no usable time for.
    func allDayEvents(on date: Date) -> [TimetableEvent] {
        events(on: date).allDay
    }

    /// `"Day 3"`, `"Weekend"`, or `nil` when W4 rendered no rotation marker.
    func rotationDay(on date: Date) -> String? {
        day(on: date)?.rotationDay
    }

    /// The Extra Academics line from the day's header cell.
    func extraAcademicsNote(on date: Date) -> String? {
        guard let note = day(on: date)?.eaNote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }

    func isNoClassesDay(_ date: Date) -> Bool {
        day(on: date)?.isNoClasses ?? false
    }

    /// `tt_start_hour` for the week containing `date`, or W4's default when it is not loaded yet.
    func gridStartHour(for date: Date) -> Int {
        week(containing: date)?.startHour ?? W4TimetableGeometry.defaultStartHour
    }

    /// `tt_end_hour` for the week containing `date`.
    func gridEndHour(for date: Date) -> Int {
        week(containing: date)?.endHour ?? W4TimetableGeometry.defaultEndHour
    }

    // MARK: - Now line and header lesson

    /// The lesson running at `instant`, if the student is looking at the day it runs on.
    func currentLesson(at instant: Date) -> TimetableEvent? {
        timedEvents(on: instant).first { $0.isLive(at: instant) }
    }

    /// The next lesson starting within `withinMinutes`, or `nil` when one is already running.
    func nextLesson(at instant: Date, withinMinutes: Int = 60) -> TimetableEvent? {
        guard currentLesson(at: instant) == nil else { return nil }
        return timedEvents(on: instant).first { event in
            guard let minutes = event.minutesUntilStart(from: instant) else { return false }
            return minutes <= withinMinutes
        }
    }

    // MARK: - Freshness copy

    var isShowingCachedCopy: Bool {
        selectedFreshness?.isFromCache ?? false
    }

    var isShowingStaleCopy: Bool {
        if case .cached(_, let isStale) = selectedFreshness { return isStale }
        return false
    }

    var isShowingDemoData: Bool {
        selectedFreshness == .demo
    }

    /// `"Last updated 12 minutes ago"`, or `nil` when the data came straight from W4.
    var lastUpdatedText: String? {
        guard let fetchedAt = selectedFreshness?.fetchedAt else { return nil }
        return "Last updated \(Self.relativeFormatter.localizedString(for: fetchedAt, relativeTo: clock()))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - Selection

    /// Moves the pager to `date` and makes sure its week is loaded.
    func select(date: Date) async {
        let normalised = W4Dates.startOfDay(date)
        if normalised != selectedDate {
            selectedDate = normalised
            syncBusyFlags()
        }
        await load(weekContaining: normalised)
    }

    /// Back to today, reloading its week.
    func goToToday() async {
        await select(date: today)
    }

    /// One ISO week earlier. No-op when W4 has already told us it ignores the week parameters.
    func goToPreviousWeek() async {
        guard weekNavigationAvailable else { return }
        await select(date: W4Dates.adding(days: -7, to: selectedDate))
    }

    /// One ISO week later.
    func goToNextWeek() async {
        guard weekNavigationAvailable else { return }
        await select(date: W4Dates.adding(days: 7, to: selectedDate))
    }

    // MARK: - Loading

    /// First paint for the tab.
    func onAppear() async {
        await load(weekContaining: selectedDate)
    }

    /// Pull-to-refresh: always go to W4, and keep the current week on screen if it fails.
    func refresh() async {
        await load(weekContaining: selectedDate, force: true)
    }

    /// Cache-first read of the week containing `date`, followed by a refresh.
    ///
    /// `force` turns the refresh into `.alwaysRefresh`; without it the repository serves a cached
    /// week that is still inside its TTL without touching the network at all, which is what makes
    /// swiping back and forth across a week boundary free.
    func load(weekContaining date: Date, force: Bool = false) async {
        let key = ScheduleIdentity.weekKey(for: date)
        guard force || (loadsInFlight[key] ?? 0) == 0 else { return }

        let token = (tokens[key] ?? 0) + 1
        tokens[key] = token
        loadsInFlight[key] = (loadsInFlight[key] ?? 0) + 1
        syncBusyFlags()
        defer {
            let remaining = (loadsInFlight[key] ?? 1) - 1
            loadsInFlight[key] = remaining > 0 ? remaining : nil
            syncBusyFlags()
        }

        // 1. Paint whatever is already on disk before any request goes out.
        if weeks[key] == nil, let cached = await repository.cachedWeek(containing: date) {
            guard tokens[key] == token else { return }
            apply(cached, requestedKey: key)
            syncBusyFlags()
        }

        // 2. Refresh. A failure below keeps step 1's copy on screen.
        do {
            let loaded = try await repository.week(
                containing: date,
                policy: force ? .alwaysRefresh : .refreshWhenStale
            )
            guard tokens[key] == token else { return }
            apply(loaded, requestedKey: key)
            errorMessage = nil
        } catch {
            guard tokens[key] == token else { return }
            handle(error)
        }

        // Only ever downgraded here: `apply` may already have switched navigation off after a
        // week W4 answered with did not match the one we asked for.
        let supportsNavigation = await repository.supportsWeekNavigation
        if !supportsNavigation {
            weekNavigationAvailable = false
        }
    }

    /// Forgets every loaded week and reloads the selected one. Used by "Clear cache".
    func reset() async {
        weeks.removeAll()
        freshnessByWeek.removeAll()
        // Bumped rather than dropped: a load already in flight must not be able to apply its
        // result after a reset, and a fresh key would let it.
        for key in tokens.keys {
            tokens[key] = (tokens[key] ?? 0) + 1
        }
        errorMessage = nil
        weekNavigationAvailable = true
        syncBusyFlags()
        await load(weekContaining: selectedDate, force: true)
    }

    // MARK: - Applying a result

    /// Files a loaded week under the week it actually describes.
    ///
    /// Two guards, both of which have bitten this screen before:
    ///
    ///   * an empty grid is dropped rather than written, so a truncated page cannot blank a week
    ///     the student was reading (plan D-22);
    ///   * a week W4 answered with that is not the week we asked for is stored under *its* key and
    ///     switches week navigation off, because that is exactly what a failed `?year=&week=`
    ///     probe looks like (plan D-18).
    private func apply(_ loaded: W4Loaded<ScheduleWeek>, requestedKey: String) {
        let value = loaded.value
        guard !value.days.isEmpty else { return }

        let actualKey = ScheduleIdentity.weekKey(year: value.year, week: value.week)
        weeks[actualKey] = value
        freshnessByWeek[actualKey] = loaded.freshness

        if actualKey != requestedKey {
            weekNavigationAvailable = false
        }
    }

    // MARK: - Errors

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }

        guard let w4Error = error as? W4Error else {
            errorMessage = error.localizedDescription
            return
        }

        switch w4Error {
        case .sessionExpired:
            // The only branch that signs anybody out. `AuthenticationViewModel` observes the
            // notification and routes back to the login screen.
            w4Error.notifyIfSessionExpired()
            errorMessage = "Your session has expired. Please log in again."

        case .forbidden:
            // Signed in, wrong role (plan D-21). Never a logout.
            errorMessage = "You do not have access to the timetable."

        case .cookieExpired, .missingCookies:
            // Recoverable: keep the timetable on screen and let the student retry.
            errorMessage = "Could not reach W4. Please try again."

        case .parsingError(let detail) where detail == TimetableRepository.weekNavigationUnsupported:
            weekNavigationAvailable = false
            errorMessage = "W4 only shows the current week."

        case .notPortedToW4(let host, _):
            errorMessage = "This screen tried to reach \(host) instead of W4."

        default:
            errorMessage = w4Error.errorDescription ?? "Could not load the timetable."
        }
    }

    // MARK: - Busy flags

    /// A spinner is only ever shown for a week with nothing behind it; everything else is a quiet
    /// refresh over data the student can already read.
    private func syncBusyFlags() {
        let key = selectedWeekKey
        let selectedIsEmpty = weeks[key] == nil
        isLoading = selectedIsEmpty && (loadsInFlight[key] ?? 0) > 0
        isRefreshing = !selectedIsEmpty && !loadsInFlight.isEmpty
    }
}
