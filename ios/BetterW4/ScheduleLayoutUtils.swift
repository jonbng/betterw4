//
//  ScheduleLayoutUtils.swift
//  BetterW4
//
//  Pure geometry for the timetable timeline: which lesson sits in which column when two of them
//  overlap, and where the top of a day's timeline is.
//
//  W4's own grid is `tt_start_hour`…`tt_end_hour` — 07:00 to 22:00 in every capture — laid out at
//  one pixel per minute (`W4TimetableGeometry`). Rendering all fifteen hours would open every day
//  on ninety minutes of empty gutter, so the timeline's *origin* is the hour containing the day's
//  first block, never earlier than the grid's own start hour. The now-line is measured from that
//  same origin, which is why it lives here and not in a view.
//

import CoreGraphics
import Foundation

/// Layout information for a single lesson when rendering overlapping blocks in a timeline.
struct EventLayoutInfo: Identifiable, Equatable {
    let event: TimetableEvent
    /// 0-based column this block was assigned within its overlap cluster.
    let column: Int
    /// How many columns the widest cluster this block belongs to needs.
    let totalColumns: Int
    /// Minutes from Oslo midnight to the block's start.
    let startMinutes: Int
    /// Minutes from Oslo midnight to the block's end, widened to the minimum readable duration.
    let endMinutes: Int

    var id: String { event.id }
}

/// Shared measurements for both timeline styles.
enum ScheduleTimelineGeometry {
    /// W4 renders its grid at one pixel per minute; the app keeps that scale so a lesson's height
    /// is its real duration.
    static let pointsPerMinute: CGFloat = 1

    /// A block shorter than this is unreadable, so it is widened for layout purposes only.
    static let minimumBlockMinutes = W4TimetableGeometry.minimumBlockMinutes

    /// Floor on a rendered card, independent of the minute maths.
    static let minimumBlockHeight: CGFloat = 36

    /// Breathing room under the last block of the day.
    static let trailingPadding: CGFloat = 24

    /// Minutes from Oslo midnight at the very top of the timeline.
    ///
    /// The hour containing the first block, clamped to the grid's own start hour. An empty day
    /// falls back to the grid start so the hour ruler still looks like W4's.
    static func originMinutes(startHour: Int, layouts: [EventLayoutInfo]) -> Int {
        let gridStart = max(0, startHour) * 60
        guard let first = layouts.map(\.startMinutes).min() else { return gridStart }
        return max(gridStart, (first / 60) * 60)
    }

    /// Height in points of the content between `originMinutes` and the end of the last block.
    static func contentHeight(layouts: [EventLayoutInfo], originMinutes: Int) -> CGFloat {
        guard let last = layouts.map(\.endMinutes).max() else { return 0 }
        return max(0, CGFloat(last - originMinutes)) * pointsPerMinute + trailingPadding
    }

    /// Vertical offset of `minutesFromMidnight` below the timeline's origin, or `nil` when it sits
    /// above it (i.e. before the first lesson of the day).
    static func offset(forMinutesFromMidnight minutes: Int, originMinutes: Int) -> CGFloat? {
        let delta = minutes - originMinutes
        guard delta >= 0 else { return nil }
        return CGFloat(delta) * pointsPerMinute
    }
}

/// Assigns overlapping lessons to columns so two blocks at the same time render side by side.
///
/// Blocks with no start time are dropped — they belong in the all-day strip, not on a clock. The
/// input is sorted by start time first, because the greedy column assignment below is only correct
/// on a sorted sequence and `W4TimetableParser` makes no ordering promise.
func calculateEventOverlapLayouts(for events: [TimetableEvent]) -> [EventLayoutInfo] {
    let ranges = events
        .compactMap { event -> (event: TimetableEvent, start: Int, end: Int)? in
            guard let start = event.startMinutesFromMidnight else { return nil }
            let rawEnd = event.endMinutesFromMidnight ?? start
            let end = max(rawEnd, start + ScheduleTimelineGeometry.minimumBlockMinutes)
            return (event, start, end)
        }
        .sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.event.id < rhs.event.id : lhs.start < rhs.start
        }

    var columnEndTimes: [Int: Int] = [:]
    var assignments: [(event: TimetableEvent, column: Int, start: Int, end: Int)] = []

    for range in ranges {
        var column = 0
        while (columnEndTimes[column] ?? Int.min) > range.start { column += 1 }
        columnEndTimes[column] = range.end
        assignments.append((range.event, column, range.start, range.end))
    }

    return assignments.map { assignment in
        let widest = assignments
            .filter { $0.start < assignment.end && assignment.start < $0.end }
            .map(\.column)
            .max() ?? 0
        return EventLayoutInfo(
            event: assignment.event,
            column: assignment.column,
            totalColumns: widest + 1,
            startMinutes: assignment.start,
            endMinutes: assignment.end
        )
    }
}
