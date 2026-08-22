//
//  CustomEvents.swift
//  BetterW4
//
//  Device-local timetable events. W4 has no private-appointment form, so these
//  never leave the phone. Overlay geometry reuses `SchoolCalendar.overlay`.
//

import Foundation
import SwiftUI

enum CustomEvents {

    static let idPrefix = EventSource.local.idPrefix + "-"

    /// Distinct from subject hues and the college-calendar green.
    static let accent = Color(red: 94 / 255, green: 53 / 255, blue: 177 / 255) // #5E35B1

    static func isCustomEvent(_ event: TimetableEvent) -> Bool {
        if event.source == .local { return true }
        return event.id.lowercased().hasPrefix(idPrefix.lowercased())
    }

    /// Strips any previous local overlay, then lays `extra` over the week.
    static func overlay(_ week: ScheduleWeek, with extra: [TimetableEvent]) -> ScheduleWeek {
        let stripped = week.withDays(
            week.days.map { day in
                day.withEvents(day.events.filter { !isCustomEvent($0) })
            }
        )
        return SchoolCalendar.overlay(stripped, with: extra)
    }

    static func makeEvent(
        id: String = "local-\(UUID().uuidString)",
        title: String,
        notes: String?,
        start: Date,
        end: Date,
        isAllDay: Bool
    ) -> TimetableEvent {
        let startDay = W4Dates.startOfDay(start)
        let resolvedEnd = end < start ? start.addingTimeInterval(3600) : end
        let eventStart: Date
        let eventEnd: Date
        if isAllDay {
            eventStart = W4Dates.startOfDay(start)
            let lastDay = W4Dates.startOfDay(resolvedEnd)
            eventEnd = W4Dates.adding(days: 1, to: lastDay)
        } else {
            eventStart = start
            eventEnd = resolvedEnd
        }
        return TimetableEvent(
            id: id,
            title: title,
            subject: title,
            source: .local,
            start: eventStart,
            end: eventEnd,
            date: startDay,
            isAllDay: isAllDay,
            notes: notes?.nilIfEmpty
        )
    }

    /// Next 15-minute slot on `day`, or 08:00 when `day` is not today.
    static func defaultStart(on day: Date, now: Date = TimeProvider.now) -> Date {
        if !W4Dates.isSameDay(day, now) {
            return W4Dates.date(onDayOf: day, minutesFromMidnight: 8 * 60)
        }
        let minutes = W4Dates.minutesFromMidnight(now)
        let remainder = minutes % 15
        let rounded = remainder == 0 ? minutes + 15 : minutes + (15 - remainder)
        if rounded >= 24 * 60 {
            return W4Dates.date(onDayOf: day, minutesFromMidnight: 23 * 60 + 45)
        }
        return W4Dates.date(onDayOf: day, minutesFromMidnight: rounded)
    }
}
