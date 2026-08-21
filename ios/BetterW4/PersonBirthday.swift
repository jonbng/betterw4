//
//  PersonBirthday.swift
//  BetterW4
//
//  Birthday as printed on a public profile (`28-Jan`, `17-Nov`, `3 March`,
//  `1 January 2008`). Year is usually omitted; the interesting number is how
//  many days until the next occurrence.
//

import Foundation

struct PersonBirthday: Equatable, Sendable {
    let raw: String
    let month: Int
    let day: Int
    /// Day + full English month (`28 January`), never the year.
    let display: String

    func daysUntil(from now: Date = TimeProvider.now) -> Int {
        let today = W4Dates.startOfDay(now)
        let calendar = W4Dates.calendar
        let year = calendar.component(.year, from: today)
        guard let thisYear = date(year: year, calendar: calendar) else { return 0 }
        if calendar.isDate(thisYear, inSameDayAs: today) { return 0 }
        if thisYear > today {
            return calendar.dateComponents([.day], from: today, to: thisYear).day ?? 0
        }
        guard let nextYear = date(year: year + 1, calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: today, to: nextYear).day ?? 0
    }

    var isToday: Bool { daysUntil() == 0 }
    var isTomorrow: Bool { daysUntil() == 1 }

    func relativeLabel(from now: Date = TimeProvider.now) -> String {
        switch daysUntil(from: now) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case let n: return "In \(n) days"
        }
    }

    static func parse(_ raw: String?, now: Date = TimeProvider.now) -> PersonBirthday? {
        guard let raw else { return nil }
        let trimmed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !trimmed.isEmpty else { return nil }
        if let date = parseDate(trimmed) {
            return from(date: date, raw: raw)
        }
        return nil
    }

    private static func from(date: Date, raw: String) -> PersonBirthday {
        let calendar = W4Dates.calendar
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return PersonBirthday(
            raw: raw,
            month: month,
            day: day,
            display: displayFormatter.string(from: date)
        )
    }

    private func date(year: Int, calendar: Calendar) -> Date? {
        let clamped = min(day, daysInMonth(year: year, month: month, calendar: calendar))
        return calendar.date(from: DateComponents(year: year, month: month, day: clamped))
    }

    private func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        let components = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let date = W4Dates.parseDate(raw) { return date }
        for suffix in [" 2024", "-2024"] {
            if let date = W4Dates.parseDate(raw + suffix) { return date }
        }
        for formatter in monthDayFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = W4Dates.locale
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let monthDayFormatters: [DateFormatter] = {
        ["d MMMM yyyy", "d MMM yyyy", "d-MMM", "dd-MMM", "d MMM", "dd MMM", "d MMMM", "dd MMMM"].map { format in
            let formatter = DateFormatter()
            formatter.locale = W4Dates.locale
            formatter.timeZone = W4Dates.zone
            formatter.calendar = W4Dates.calendar
            formatter.dateFormat = format
            return formatter
        }
    }()
}
