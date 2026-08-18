//
//  ScheduleIdentity.swift
//  BetterW4
//
//  Week and lesson identity for the W4 timetable (port plan Wave 5.1, D-9/D-11/D-18).
//
//  Everything here is derived from `W4Dates`, i.e. ISO weeks in `Europe/Oslo`. The previous
//  implementation built its own `Calendar(identifier: .iso8601)` pinned to `TimeZone.current`,
//  which meant a phone set to Auckland put Monday's lessons in the wrong week — and the wrong
//  cache key. There is exactly one week numbering in this app and it is W4's.
//

import Foundation

enum ScheduleIdentity {

    // MARK: - Week identity

    /// `"2026-W33"` — the cache-key and `LessonRecord.weekKey` spelling of an ISO week.
    static func weekKey(year: Int, week: Int) -> String {
        String(format: "%04d-W%02d", year, week)
    }

    /// The ISO week key of the Oslo week containing `date`.
    static func weekKey(for date: Date) -> String {
        let iso = W4Dates.isoWeek(of: date)
        return weekKey(year: iso.year, week: iso.week)
    }

    /// Parses `"2026-W33"` back into its parts. Returns `nil` for anything else, so a corrupt
    /// key read off disk degrades instead of pretending to be week 0 of year 0.
    static func week(forKey key: String) -> (year: Int, week: Int)? {
        let parts = key.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[1].hasPrefix("W"),
              let year = Int(parts[0]),
              let week = Int(parts[1].dropFirst()),
              (1...53).contains(week)
        else { return nil }
        return (year, week)
    }

    /// Monday 00:00 Oslo of the week `key` names.
    static func startOfWeek(forKey key: String) -> Date? {
        guard let iso = week(forKey: key) else { return nil }
        return W4Dates.startOfISOWeek(year: iso.year, week: iso.week)
    }

    /// True when `date` falls in the ISO week `key` names.
    static func weekKey(_ key: String, contains date: Date) -> Bool {
        weekKey(for: date) == key
    }

    // MARK: - Lesson identity

    /// W4 event ids are already unique and source-prefixed (`"ac-w4-42"`, D-9 / `parsers.md` B20),
    /// so the lesson key is the id. It survives as its own concept because `Timetable.store` rows
    /// are keyed on it and `uniqueKey` composes it with the student.
    static func lessonKey(for event: TimetableEvent) -> String {
        event.id
    }

    /// Row key inside `Timetable.store`: `"<uwcId>|<lessonKey>"`.
    static func uniqueKey(uwcId: String, lessonKey: String) -> String {
        "\(uwcId)|\(lessonKey)"
    }
}
