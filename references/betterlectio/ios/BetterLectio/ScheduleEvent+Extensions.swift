//
//  ScheduleEvent+Extensions.swift
//  BetterLectio
//
//  Created by Antigravity on 14/03/2026.
//

import Foundation

extension ScheduleEvent {
    /// Converts a time string (e.g., "08:10" or "08.10") to minutes since midnight
    func timeToMinutes(_ time: String) -> Int {
        let separator = time.contains(":") ? ":" : "."
        let parts = time.split(separator: Character(separator)).compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    /// Minutes until the lesson starts relative to a given date
    func minutesUntilStart(relativeTo date: Date) -> Int {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentTimeMinutes = currentHour * 60 + currentMinute
        let startMinutes = timeToMinutes(startTime)
        return max(0, startMinutes - currentTimeMinutes)
    }

    /// Minutes remaining in the lesson relative to a given date
    func minutesRemaining(relativeTo date: Date) -> Int {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentTimeMinutes = currentHour * 60 + currentMinute
        let endMinutes = timeToMinutes(endTime)
        return max(0, endMinutes - currentTimeMinutes)
    }

    /// Progress through the lesson (0.0 to 1.0) relative to a given date
    func progress(relativeTo date: Date) -> Double {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentTimeMinutes = currentHour * 60 + currentMinute

        let startMinutes = timeToMinutes(startTime)
        let endMinutes = timeToMinutes(endTime)
        let totalDuration = endMinutes - startMinutes

        guard totalDuration > 0 else { return 0 }

        let elapsed = currentTimeMinutes - startMinutes
        return min(1.0, max(0.0, Double(elapsed) / Double(totalDuration)))
    }
}

extension Array where Element == ScheduleEvent {
    /// Events that belong on the timed timeline (excludes all-day).
    var timed: [ScheduleEvent] { filter { !$0.isAllDay } }

    /// Events to render in the all-day strip above the timeline.
    var allDay: [ScheduleEvent] { filter { $0.isAllDay } }
}
