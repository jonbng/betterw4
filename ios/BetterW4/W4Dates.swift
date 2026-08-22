//
//  W4Dates.swift
//  BetterW4
//
//  The one and only date/time authority for everything scraped out of
//  https://w4.uwcrcn.no. Created for W4 port plan decision D-11.
//
//  WHY THIS FILE EXISTS (docs/spec/parsers.md section 0.1 — the strongest piece
//  of evidence in the whole research set):
//
//      The captured Home page renders its timetable grid 900 px tall over the
//      15 hours from `tt_start_hour = 7` to `tt_end_hour = 22`, i.e. 1 px == 1
//      minute from 07:00. The now-line sat at `top: 394px`, which is 13:34.
//      The HAR captured in the same session is stamped `11:30:12 GMT`, which is
//      13:30 in Europe/Oslo (CEST). Therefore W4 renders wall-clock time in
//      Europe/Oslo, with no offset anywhere in the markup.
//
//  Consequences, and they are binding for every parser in the app:
//
//    * Never use `TimeZone.current`. A student on a trip with the phone set to
//      another timezone must still see the Oslo timetable.
//    * Never use `Calendar.current` or `Locale.current`. The month name "Aug"
//      must parse on a phone set to Danish, and week numbering must be ISO
//      (Monday-first, 4-day rule) the way W4 and en_GB number weeks.
//    * Every `Date` produced from W4 HTML is an instant built from an Oslo
//      wall-clock reading, and is rendered back with this same fixed zone.
//
//  Everything here is `nonisolated` and synchronous: parsers are pure
//  `(String) -> Model` functions and must not hop actors (plan D-30).
//

import Foundation

// MARK: - W4Dates

/// Date parsing and formatting for W4 wire formats, pinned to `Europe/Oslo`.
///
/// Accepted input formats, tried in this order (plan D-11):
/// `d-MMM-yyyy`, `dd-MMM-yyyy`, `d-MMM-yy`, `dd-MMM-yy`, `yyyy-MM-dd`,
/// `d/M/yyyy`, `dd/MM/yyyy`, and with a time `dd-MMM-yyyy HH:mm`.
enum W4Dates {

    // MARK: Fixed locale, zone and calendar

    /// The timezone W4 renders every wall-clock date and time in.
    ///
    /// The force-unwrap ladder is deliberate: `Europe/Oslo` is in every copy of
    /// the tz database Apple ships, and if it somehow were not, UTC+1 is a far
    /// better answer than crashing a student's timetable.
    static let zone: TimeZone = TimeZone(identifier: "Europe/Oslo")
        ?? TimeZone(secondsFromGMT: 3600)
        ?? TimeZone(secondsFromGMT: 0)!

    /// Fixed parsing locale. `en_GB_POSIX` gives stable, language-independent
    /// English month abbreviations ("Aug"), which is what W4 emits.
    static let locale: Locale = Locale(identifier: "en_GB_POSIX")

    /// Fixed Gregorian calendar in `zone`, configured for **ISO 8601 weeks**:
    /// weeks start on Monday and week 1 is the week containing 4 January.
    /// `2026-08-10` is ISO 2026-W33-1 under these rules, which matches the
    /// captured heading "August 2026, week 33".
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        calendar.firstWeekday = 2           // Monday
        calendar.minimumDaysInFirstWeek = 4 // ISO 8601 week-1 rule
        return calendar
    }()

    /// The format W4 itself renders dates in (`14-Aug-2026`).
    static let dateFormat = "dd-MMM-yyyy"
    /// The format W4 grids render timestamps in (`14-Aug-2026 12:04`). **[I]**
    static let dateTimeFormat = "dd-MMM-yyyy HH:mm"
    /// Wall-clock time of day (`08:05`).
    static let timeFormat = "HH:mm"

    // MARK: Formatters

    // `DateFormatter` is `Sendable` and is documented as thread-safe for
    // parsing and formatting once configured. These are configured exactly once
    // in their initialisers and are never mutated afterwards, so sharing them
    // across parsers running off the main actor is safe.

    private static let dateFormatters: [DateFormatter] = [
        "d-MMM-yyyy",
        "dd-MMM-yyyy",
        "d-MMM-yy",
        "dd-MMM-yy",
        "yyyy-MM-dd",
        "d/M/yyyy",
        "dd/MM/yyyy"
    ].map(makeFormatter)

    private static let dateTimeFormatters: [DateFormatter] = [
        "dd-MMM-yyyy HH:mm",
        "d-MMM-yyyy HH:mm",
        "dd-MMM-yy HH:mm",
        "d-MMM-yy HH:mm",
        "yyyy-MM-dd HH:mm",
        "dd-MMM-yyyy HH:mm:ss",
        "d-MMM-yyyy HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "dd/MM/yyyy HH:mm",
        "d/M/yyyy HH:mm"
    ].map(makeFormatter)

    private static let outputDateFormatter = makeFormatter(dateFormat)
    private static let outputDateTimeFormatter = makeFormatter(dateTimeFormat)
    private static let outputTimeFormatter = makeFormatter(timeFormat)

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.calendar = calendar
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    // MARK: Parsing

    /// Parses a W4 calendar date and returns the **start of that day in Oslo**.
    ///
    /// Tolerates surrounding whitespace, non-breaking spaces, collapsed inner
    /// whitespace and the occasional four-letter `Sept`. Returns `nil` rather
    /// than throwing: a parser that cannot read a date must degrade, never crash.
    static func parseDate(_ raw: String?) -> Date? {
        guard let candidate = normalized(raw) else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: candidate) {
                return startOfDay(date)
            }
        }
        // "14-Aug-2026 12:04" is still a perfectly good day.
        for formatter in dateTimeFormatters {
            if let date = formatter.date(from: candidate) {
                return startOfDay(date)
            }
        }
        return nil
    }

    /// Alias for ``parseDate(_:)``, matching the Kotlin port's `W4Dates.parse`.
    static func parse(_ raw: String?) -> Date? {
        parseDate(raw)
    }

    /// Parses a W4 timestamp (`14-Aug-2026 12:04`) as an Oslo wall-clock
    /// instant. A bare date parses as midnight Oslo.
    static func parseDateTime(_ raw: String?) -> Date? {
        guard let candidate = normalized(raw) else { return nil }
        for formatter in dateTimeFormatters {
            if let date = formatter.date(from: candidate) {
                return date
            }
        }
        for formatter in dateFormatters {
            if let date = formatter.date(from: candidate) {
                return date
            }
        }
        return nil
    }

    /// Finds the first W4-shaped date inside a longer string and parses it.
    ///
    /// The timetable header cell renders the date in its own `<div>`, but other
    /// surfaces bury it in prose ("Deadline: 14-Aug-2026"), so this scans for
    /// `d-MMM-yyyy`, `yyyy-MM-dd` and `d/M/yyyy` shapes and parses the first hit.
    static func firstDate(in text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let patterns = [
            #"\d{1,2}-[A-Za-z]{3,9}-\d{2,4}"#,
            #"\d{4}-\d{1,2}-\d{1,2}"#,
            #"\d{1,2}/\d{1,2}/\d{4}"#
        ]
        for pattern in patterns {
            guard let match = firstMatch(pattern, in: text) else { continue }
            if let date = parseDate(match) { return date }
        }
        return nil
    }

    /// Parses a bare wall-clock time such as `8:05` or `08:05` into minutes
    /// since midnight. Returns `nil` for out-of-range values.
    static func parseTimeOfDay(_ raw: String?) -> (hour: Int, minute: Int)? {
        guard let candidate = normalized(raw),
              let match = firstMatch(#"(\d{1,2}):(\d{2})"#, in: candidate, captureGroups: 2)
        else { return nil }
        let parts = match.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    // MARK: Formatting

    /// `14-Aug-2026` — the format W4's own forms and datepickers expect back.
    static func format(_ date: Date) -> String {
        outputDateFormatter.string(from: date)
    }

    /// `14-Aug-2026 12:04`.
    static func formatDateTime(_ date: Date) -> String {
        outputDateTimeFormatter.string(from: date)
    }

    /// `08:05`, Oslo wall clock.
    static func formatTime(_ date: Date) -> String {
        outputTimeFormatter.string(from: date)
    }

    // MARK: Calendar arithmetic

    /// Start of the Oslo day containing `date`.
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Builds an instant from Oslo wall-clock components.
    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = zone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// `date` shifted by whole Oslo days (DST-safe: 02:00 stays 02:00).
    static func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// The Oslo instant `minutes` after midnight on the day containing `day`.
    /// Clamped to the day so a nonsense pixel offset can never produce a date
    /// on another day.
    static func date(onDayOf day: Date, minutesFromMidnight minutes: Int) -> Date {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        let start = startOfDay(day)
        return calendar.date(byAdding: .minute, value: clamped, to: start)
            ?? start.addingTimeInterval(TimeInterval(clamped * 60))
    }

    /// Minutes since Oslo midnight for `date` (0...1439).
    static func minutesFromMidnight(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// ISO 8601 week-year and week number for `date`, in Oslo.
    /// `2026-08-10` -> `(year: 2026, week: 33)`.
    static func isoWeek(of date: Date) -> (year: Int, week: Int) {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? calendar.component(.year, from: date)
        let week = components.weekOfYear ?? 1
        return (year, week)
    }

    /// The Monday that starts ISO week `week` of `year`, at 00:00 Oslo.
    static func startOfISOWeek(year: Int, week: Int) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = zone
        components.weekday = 2 // Monday
        components.weekOfYear = week
        components.yearForWeekOfYear = year
        return calendar.date(from: components).map(startOfDay)
    }

    /// The Monday that starts the ISO week containing `date`, at 00:00 Oslo.
    static func startOfWeek(containing date: Date) -> Date {
        let iso = isoWeek(of: date)
        return startOfISOWeek(year: iso.year, week: iso.week) ?? startOfDay(date)
    }

    /// True when both instants fall on the same Oslo calendar day.
    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// English month name in Oslo ("August"), locale-independent.
    static func monthName(of date: Date) -> String {
        monthNames(full: true)[monthIndex(of: date)]
    }

    /// Short English month name in Oslo ("Aug"), locale-independent.
    static func shortMonthName(of date: Date) -> String {
        monthNames(full: false)[monthIndex(of: date)]
    }

    /// English weekday name in Oslo ("Monday"), locale-independent.
    static func weekdayName(of date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1 // 0 == Sunday
        let names = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]
        guard names.indices.contains(index) else { return "" }
        return names[index]
    }

    // MARK: - Private helpers

    /// 0-based month index in Oslo, clamped so a nonsense date cannot trap.
    private static func monthIndex(of date: Date) -> Int {
        let month = calendar.component(.month, from: date)
        return min(max(month - 1, 0), 11)
    }

    private static func monthNames(full: Bool) -> [String] {
        full
            ? ["January", "February", "March", "April", "May", "June",
               "July", "August", "September", "October", "November", "December"]
            : ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
               "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    }

    /// Trims, collapses inner whitespace, normalises non-breaking spaces and
    /// the stray `Sept` abbreviation. Returns `nil` for empty input.
    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        // W4 emits three-letter months; a stray "Sept" would otherwise fail.
        value = value.replacingOccurrences(
            of: "Sept",
            with: "Sep",
            options: [.caseInsensitive]
        )
        return value.isEmpty ? nil : value
    }

    /// Returns the whole first match of `pattern`, or (when `captureGroups > 0`)
    /// the joined capture groups separated by ":".
    private static func firstMatch(
        _ pattern: String,
        in text: String,
        captureGroups: Int = 0
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        if captureGroups == 0 {
            guard let whole = Range(match.range, in: text) else { return nil }
            return String(text[whole])
        }
        guard match.numberOfRanges > captureGroups else { return nil }
        var pieces: [String] = []
        for index in 1...captureGroups {
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            pieces.append(String(text[groupRange]))
        }
        return pieces.joined(separator: ":")
    }
}
