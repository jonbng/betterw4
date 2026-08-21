//
//  BirthdaysViewModel.swift
//  BetterW4
//
//  Month calendar of W4 birthdays. Cache-first, then refresh. Adjacent months
//  are fetched so "coming up" can wrap past the last day of the current month.
//

import Combine
import Foundation

@MainActor
final class BirthdaysViewModel: ObservableObject {

    @Published private(set) var selected: BirthdayMonthRef
    @Published var filter: BirthdayKindFilter = .all
    @Published private(set) var month: BirthdayMonth?
    @Published private(set) var followingMonth: BirthdayMonth?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: BirthdayRepository
    private var loadGeneration: UUID?

    init(
        repository: BirthdayRepository = .shared,
        now: Date = TimeProvider.now
    ) {
        self.repository = repository
        self.selected = BirthdayMonthRef.current(now: now)
    }

    var displayedMonth: BirthdayMonth {
        let source = month?.ref == selected ? month : nil
        return (source ?? BirthdayMonth(
            monthLabel: selected.label,
            year: selected.year,
            month: selected.month,
            previous: selected.offset(by: -1),
            next: selected.offset(by: 1)
        )).filtered(by: filter)
    }

    var monthLabel: String {
        displayedMonth.monthLabel ?? selected.label
    }

    var isCurrentMonth: Bool {
        selected == BirthdayMonthRef.current()
    }

    var todayPeople: [BirthdayPerson] {
        guard isCurrentMonth else { return [] }
        return displayedMonth.day(on: W4Dates.startOfDay(TimeProvider.now))?.people ?? []
    }

    var tomorrowPeople: [BirthdayPerson] {
        guard isCurrentMonth else { return [] }
        let date = W4Dates.adding(days: 1, to: W4Dates.startOfDay(TimeProvider.now))
        return people(on: date)
    }

    var upcomingDays: [BirthdayDay] {
        let today = W4Dates.startOfDay(TimeProvider.now)
        let from = W4Dates.adding(days: tomorrowPeople.isEmpty ? 1 : 2, to: today)
        if isCurrentMonth {
            let current = displayedMonth.daysWithPeople(from: from)
            let following = (followingMonth ?? BirthdayMonth())
                .filtered(by: filter)
                .daysWithPeople()
            return Array((current + following).prefix(12))
        }
        return displayedMonth.daysWithPeople()
    }

    var earlierDays: [BirthdayDay] {
        guard isCurrentMonth else { return [] }
        let yesterday = W4Dates.adding(days: -1, to: W4Dates.startOfDay(TimeProvider.now))
        return displayedMonth.daysWithPeople(through: yesterday)
    }

    func load() async {
        await run(forceRefresh: false)
    }

    func refresh() async {
        await run(forceRefresh: true)
    }

    func goToPreviousMonth() {
        selected = month?.previous ?? selected.offset(by: -1)
        Task { await run(forceRefresh: false) }
    }

    func goToNextMonth() {
        selected = month?.next ?? selected.offset(by: 1)
        Task { await run(forceRefresh: false) }
    }

    func goToCurrentMonth() {
        selected = BirthdayMonthRef.current()
        Task { await run(forceRefresh: false) }
    }

    static func caption(for day: BirthdayDay, now: Date = TimeProvider.now) -> String {
        guard let date = day.date else { return day.dateLabel }
        let today = W4Dates.startOfDay(now)
        if W4Dates.startOfDay(date) == today { return "Today" }
        if W4Dates.startOfDay(date) == W4Dates.adding(days: 1, to: today) { return "Tomorrow" }
        let weekday = weekdayFormatter.string(from: date)
        let sameWeek = W4Dates.calendar.isDate(date, equalTo: today, toGranularity: .weekOfYear)
        if sameWeek { return weekday }
        return day.dateLabel
    }

    private func people(on date: Date) -> [BirthdayPerson] {
        if let match = displayedMonth.day(on: date) { return match.people }
        return followingMonth?.filtered(by: filter).day(on: date)?.people ?? []
    }

    private func run(forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation
        let target = selected

        if !forceRefresh, month?.ref != target, let cached = await repository.cachedMonth(target) {
            guard loadGeneration == generation else { return }
            month = cached.value
            freshness = cached.freshness
        }

        if month?.ref != target { isLoading = true }

        do {
            let loaded = try await repository.loadMonth(target, forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            month = loaded.value
            freshness = loaded.freshness
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if month?.ref != target {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load birthdays."
            }
        }

        if loadGeneration == generation { isLoading = false }

        let nextRef = month?.next ?? target.offset(by: 1)
        if let extra = await repository.cachedMonth(nextRef) {
            guard loadGeneration == generation else { return }
            followingMonth = extra.value
        }
        if let extra = try? await repository.loadMonth(nextRef, forceRefresh: forceRefresh, priority: .opportunistic) {
            guard loadGeneration == generation else { return }
            followingMonth = extra.value
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
