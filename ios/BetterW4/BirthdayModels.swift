//
//  BirthdayModels.swift
//  BetterW4
//
//  The month calendar at `people/birthdays` (features.md §1.12, ui.md §4.21).
//
//  Evidence: live capture 21 Aug 2026. Unlike Home's today/tomorrow block,
//  each calendar cell names the person (`a[title]`), links the profile, and
//  stamps staff vs student from the href. `/images/user.png` is W4's missing
//  photo, not a portrait.
//

import Foundation

enum BirthdayKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case students
    case staff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .students: return "Students"
        case .staff: return "Staff"
        }
    }

    func includes(_ person: BirthdayPerson) -> Bool {
        switch self {
        case .all: return true
        case .students: return !person.isStaff
        case .staff: return person.isStaff
        }
    }
}

struct BirthdayPerson: Identifiable, Hashable, Sendable {
    let uwcId: String
    let name: String?
    let isStaff: Bool
    let profileRoute: String?
    let profileURL: URL?
    let photoURL: URL?

    var id: String { uwcId }

    var kind: DirectoryPersonKind { isStaff ? .staff : .student }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? uwcId : trimmed
    }

    var roleLabel: String { isStaff ? "Staff" : "Student" }

    var directoryPerson: DirectoryPerson {
        DirectoryPerson(
            uwcId: uwcId,
            name: displayName,
            kind: kind,
            photoURL: photoURL
        )
    }
}

struct BirthdayDay: Identifiable, Hashable, Sendable {
    let date: Date?
    let dayNumber: Int
    let dateLabel: String
    let people: [BirthdayPerson]

    var id: String {
        if let date { return W4Dates.format(date) }
        return "day-\(dayNumber)"
    }

    var isEmpty: Bool { people.isEmpty }

    func filtered(by filter: BirthdayKindFilter) -> BirthdayDay {
        guard filter != .all else { return self }
        return BirthdayDay(
            date: date,
            dayNumber: dayNumber,
            dateLabel: dateLabel,
            people: people.filter(filter.includes)
        )
    }
}

struct BirthdayMonthRef: Hashable, Sendable {
    let year: Int
    let month: Int

    var label: String { BirthdayMonth.label(year: year, month: month) }

    func offset(by months: Int) -> BirthdayMonthRef {
        var monthIndex = month + months
        var year = self.year
        while monthIndex < 1 {
            monthIndex += 12
            year -= 1
        }
        while monthIndex > 12 {
            monthIndex -= 12
            year += 1
        }
        return BirthdayMonthRef(year: year, month: monthIndex)
    }

    static func current(now: Date = TimeProvider.now) -> BirthdayMonthRef {
        let parts = W4Dates.calendar.dateComponents([.year, .month], from: now)
        return BirthdayMonthRef(year: parts.year ?? 2026, month: parts.month ?? 1)
    }
}

struct BirthdayMonth: Hashable, Sendable {
    var monthLabel: String?
    var year: Int?
    var month: Int?
    var previous: BirthdayMonthRef?
    var next: BirthdayMonthRef?
    var days: [BirthdayDay]

    var people: [BirthdayPerson] { days.flatMap(\.people) }

    var isEmpty: Bool { people.isEmpty }

    var ref: BirthdayMonthRef? {
        guard let year, let month else { return nil }
        return BirthdayMonthRef(year: year, month: month)
    }

    init(
        monthLabel: String? = nil,
        year: Int? = nil,
        month: Int? = nil,
        previous: BirthdayMonthRef? = nil,
        next: BirthdayMonthRef? = nil,
        days: [BirthdayDay] = []
    ) {
        self.monthLabel = monthLabel
        self.year = year
        self.month = month
        self.previous = previous
        self.next = next
        self.days = days
    }

    func day(on date: Date) -> BirthdayDay? {
        let start = W4Dates.startOfDay(date)
        return days.first { day in
            guard let dayDate = day.date else { return false }
            return W4Dates.startOfDay(dayDate) == start
        }
    }

    func daysWithPeople(
        from start: Date? = nil,
        through end: Date? = nil
    ) -> [BirthdayDay] {
        days.filter { day in
            guard !day.people.isEmpty else { return false }
            guard let date = day.date else { return true }
            if let start, W4Dates.startOfDay(date) < W4Dates.startOfDay(start) { return false }
            if let end, W4Dates.startOfDay(date) > W4Dates.startOfDay(end) { return false }
            return true
        }
    }

    func filtered(by filter: BirthdayKindFilter) -> BirthdayMonth {
        guard filter != .all else { return self }
        return BirthdayMonth(
            monthLabel: monthLabel,
            year: year,
            month: month,
            previous: previous,
            next: next,
            days: days.map { $0.filtered(by: filter) }
        )
    }

    static func label(year: Int, month: Int) -> String {
        guard let date = W4Dates.date(year: year, month: month, day: 1) else {
            return "\(month) \(year)"
        }
        return monthYearFormatter.string(from: date)
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
