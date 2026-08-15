//
//  ScheduleIdentity.swift
//  BetterLectio
//
//  Created by Cursor on 16/02/2026.
//

import Foundation
import CryptoKit

enum ScheduleIdentity {
    static func weekKey(for date: Date) -> String {
        let calendar = isoCalendar
        let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", yearForWeek, week)
    }

    static func currentWeekNumber() -> Int {
        isoCalendar.component(.weekOfYear, from: TimeProvider.now)
    }

    /// Returns the Lectio week parameter format: WWYYYY (e.g., 082026 for week 8, 2026; 122026 for week 12, 2026)
    static func lectioWeekParameter(for date: Date) -> String {
        let year = isoCalendar.component(.yearForWeekOfYear, from: date)
        let week = isoCalendar.component(.weekOfYear, from: date)
        return String(format: "%02d%04d", week, year)
    }

    static func lessonKey(for event: ScheduleEvent, studentId: String) -> String {
        if !event.id.isEmpty {
            return event.id
        }

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = isoCalendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = isoCalendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let base = [
            studentId,
            dayFormatter.string(from: event.date),
            event.startTime.lowercased(),
            event.endTime.lowercased(),
            event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (event.teacher ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            (event.room ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            event.isAllDay ? "allday" : ""
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone.current
        return calendar
    }
}
