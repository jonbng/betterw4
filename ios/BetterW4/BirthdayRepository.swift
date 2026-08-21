//
//  BirthdayRepository.swift
//  BetterW4
//
//  `people/birthdays` for the current month, `people/birthdays/index` with
//  `month` + `year` siblings for any other. Cache: `W4Surface.people`, TTL
//  7 days — who has a birthday on which day does not change during term.
//  "Today" is computed from the Oslo clock, never from a cached CSS class.
//

import Foundation

actor BirthdayRepository {

    static let shared = BirthdayRepository()

    private let client: any W4SecondaryFetching
    private let cache: W4PageCache
    private let resolveContext: @Sendable () throws -> W4RequestContext

    init(
        client: any W4SecondaryFetching = W4HTTPClient(),
        cache: W4PageCache = .shared,
        resolveContext: @escaping @Sendable () throws -> W4RequestContext = {
            try W4RequestContext.require()
        }
    ) {
        self.client = client
        self.cache = cache
        self.resolveContext = resolveContext
    }

    static func cacheKey(_ ref: BirthdayMonthRef) -> String {
        String(format: "birthdays-%04d-%02d", ref.year, ref.month)
    }

    func loadMonth(
        _ ref: BirthdayMonthRef,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<BirthdayMonth> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoMonth(ref), freshness: .demo)
        }
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .people,
            key: Self.cacheKey(ref),
            route: W4Routes.R.birthdaysIndex,
            query: [
                "month": String(ref.month),
                "year": String(ref.year)
            ],
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map { html in
            var parsed = W4BirthdayParser.parse(html)
            if parsed.year == nil { parsed.year = ref.year }
            if parsed.month == nil { parsed.month = ref.month }
            if parsed.monthLabel == nil { parsed.monthLabel = ref.label }
            if parsed.previous == nil { parsed.previous = ref.offset(by: -1) }
            if parsed.next == nil { parsed.next = ref.offset(by: 1) }
            return parsed
        }
    }

    func cachedMonth(_ ref: BirthdayMonthRef) async -> W4Loaded<BirthdayMonth>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoMonth(ref), freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .people,
            key: Self.cacheKey(ref),
            context: context,
            cache: cache
        )
        return cached?.map { html in
            var parsed = W4BirthdayParser.parse(html)
            if parsed.year == nil { parsed.year = ref.year }
            if parsed.month == nil { parsed.month = ref.month }
            if parsed.monthLabel == nil { parsed.monthLabel = ref.label }
            if parsed.previous == nil { parsed.previous = ref.offset(by: -1) }
            if parsed.next == nil { parsed.next = ref.offset(by: 1) }
            return parsed
        }
    }

    // MARK: - Demo

    static func demoMonth(_ ref: BirthdayMonthRef, now: Date = TimeProvider.now) -> BirthdayMonth {
        let people = DirectoryRepository.demoPeople
        let students = people.filter { $0.kind == .student }
        let staff = people.filter { $0.kind == .staff }
        let today = W4Dates.startOfDay(now)
        let todayParts = W4Dates.calendar.dateComponents([.year, .month, .day], from: today)
        let length = W4Dates.calendar.range(of: .day, in: .month, for: W4Dates.date(year: ref.year, month: ref.month, day: 1) ?? today)?.count ?? 30

        func person(_ source: DirectoryPerson) -> BirthdayPerson {
            BirthdayPerson(
                uwcId: source.uwcId,
                name: source.displayName,
                isStaff: source.kind == .staff,
                profileRoute: source.profileRoute,
                profileURL: source.profileURL,
                photoURL: source.photoURL
            )
        }

        func day(_ number: Int, people: [DirectoryPerson]) -> BirthdayDay {
            let date = W4Dates.date(year: ref.year, month: ref.month, day: number)
            let label = date.map { displayDayFormatter.string(from: $0) } ?? "\(number)"
            return BirthdayDay(
                date: date,
                dayNumber: number,
                dateLabel: label,
                people: people.map(person)
            )
        }

        var days: [BirthdayDay] = []
        let isCurrent = todayParts.year == ref.year && todayParts.month == ref.month
        if isCurrent, let todayNumber = todayParts.day {
            days.append(day(todayNumber, people: Array(students.prefix(1))))
            let tomorrowNumber = todayNumber + 1
            if tomorrowNumber <= length {
                days.append(day(tomorrowNumber, people: Array(students.dropFirst().prefix(1))))
            }
            let later = min(todayNumber + 6, length)
            if later != todayNumber, later != tomorrowNumber {
                days.append(day(later, people: Array(staff.prefix(1)) + Array(students.dropFirst(2).prefix(2))))
            }
        } else {
            days.append(day(3, people: Array(students.prefix(2))))
            days.append(day(min(18, length), people: Array(staff.prefix(1))))
        }
        days.sort { lhs, rhs in
            if let a = lhs.date, let b = rhs.date { return a < b }
            return lhs.dayNumber < rhs.dayNumber
        }
        return BirthdayMonth(
            monthLabel: ref.label,
            year: ref.year,
            month: ref.month,
            previous: ref.offset(by: -1),
            next: ref.offset(by: 1),
            days: days
        )
    }

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}
