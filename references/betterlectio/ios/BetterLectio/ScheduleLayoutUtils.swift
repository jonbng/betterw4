//
//  ScheduleLayoutUtils.swift
//  BetterLectio
//

import Foundation

/// Layout information for a single event when rendering overlapping lessons in a timeline.
struct EventLayoutInfo {
    let event: ScheduleEvent
    let column: Int
    let totalColumns: Int
}

/// Calculates column assignments and overlap counts for events in a timeline.
/// Two events overlap if one starts before the other ends. Minimum display duration is 15 minutes.
func calculateEventOverlapLayouts(
    for events: [ScheduleEvent],
    timeToMinutes: (String) -> Int
) -> [EventLayoutInfo] {
    let minDuration = 29

    // Compute effective ranges, enforcing minimum duration
    let ranges = events.map { event -> (event: ScheduleEvent, start: Int, end: Int) in
        let start = timeToMinutes(event.startTime)
        let end = max(timeToMinutes(event.endTime), start + minDuration)
        return (event, start, end)
    }

    // Assign each event to the lowest available column using per-column end times
    var columnEndTimes: [Int: Int] = [:]
    var assignments: [(event: ScheduleEvent, column: Int, start: Int, end: Int)] = []

    for range in ranges {
        var column = 0
        while (columnEndTimes[column] ?? 0) > range.start { column += 1 }
        columnEndTimes[column] = range.end
        assignments.append((range.event, column, range.start, range.end))
    }

    return assignments.map { a in
        let maxColumn = assignments
            .filter { $0.start < a.end && a.start < $0.end }
            .map(\.column)
            .max() ?? 0
        return EventLayoutInfo(event: a.event, column: a.column, totalColumns: maxColumn + 1)
    }
}
