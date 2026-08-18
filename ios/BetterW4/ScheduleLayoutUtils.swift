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
    /// Minutes from Oslo midnight to the block's real end. Visual min-height is applied later
    /// and never fed back into overlap columns.
    let endMinutes: Int
    /// Leading edge of the card as a fraction of the lane width.
    let xFraction: CGFloat
    /// Card width as a fraction of the lane width.
    let widthFraction: CGFloat

    var id: String { event.id }
}

/// Shared measurements for both timeline styles.
enum ScheduleTimelineGeometry {
    /// W4 renders its grid at one pixel per minute; the app keeps that scale so a lesson's height
    /// is its real duration.
    static let pointsPerMinute: CGFloat = 1

    /// Floor on a rendered card, used only when growing would not collide with the next block.
    static let minimumBlockHeight: CGFloat = 36

    /// Isolated shorts may grow this many minutes. Adjacent blocks keep their real duration.
    static var minimumVisualMinutes: Int {
        Int((minimumBlockHeight / pointsPerMinute).rounded(.up))
    }

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
        guard let last = layouts.map({ visualEndMinutes(of: $0, among: layouts) }).max() else { return 0 }
        return max(0, CGFloat(last - originMinutes)) * pointsPerMinute + trailingPadding
    }

    /// Minutes from midnight at which this card should stop painting.
    ///
    /// Isolated shorts grow to [minimumVisualMinutes] so a lone sliver is still tappable.
    /// If another event starts at or after this one's real end, the card is clipped there —
    /// otherwise a 15-minute break between two lessons would paint over the next module.
    static func visualEndMinutes(of layout: EventLayoutInfo, among layouts: [EventLayoutInfo]) -> Int {
        let grown = max(layout.endMinutes, layout.startMinutes + minimumVisualMinutes)
        let nextStart = layouts
            .filter { $0.id != layout.id && $0.startMinutes >= layout.endMinutes }
            .map(\.startMinutes)
            .min()
        let capped = nextStart.map { min(grown, $0) } ?? grown
        return max(layout.startMinutes + 1, capped)
    }

    static func visualHeight(of layout: EventLayoutInfo, among layouts: [EventLayoutInfo]) -> CGFloat {
        let minutes = visualEndMinutes(of: layout, among: layouts) - layout.startMinutes
        return max(1, CGFloat(minutes)) * pointsPerMinute
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
/// School-calendar events still get a column (the greedy pass has to run in start-time order),
/// but [overlapPlacement] then parks them in the trailing strip so a real lesson keeps the
/// primary lane. Blocks with no start time are dropped — they belong in the all-day strip.
func calculateEventOverlapLayouts(for events: [TimetableEvent]) -> [EventLayoutInfo] {
    let ranges = events
        .compactMap { event -> (event: TimetableEvent, start: Int, end: Int)? in
            guard let start = event.startMinutesFromMidnight else { return nil }
            let rawEnd = event.endMinutesFromMidnight ?? start
            // Real clock range only. A 15-minute break that merely *touches* the next
            // lesson is not an overlap — stretching it to a min-height here is what
            // used to shove it into a side lane.
            let end = max(rawEnd, start + 1)
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

    let withColumns: [(event: TimetableEvent, column: Int, start: Int, end: Int, total: Int)] =
        assignments.map { assignment in
            let widest = assignments
                .filter { $0.start < assignment.end && assignment.start < $0.end }
                .map(\.column)
                .max() ?? 0
            return (assignment.event, assignment.column, assignment.start, assignment.end, widest + 1)
        }

    return withColumns.map { assignment in
        let cluster = withColumns.filter { other in
            other.start < assignment.end && assignment.start < other.end
        }
        let place = overlapPlacement(for: assignment, in: cluster)
        return EventLayoutInfo(
            event: assignment.event,
            column: assignment.column,
            totalColumns: assignment.total,
            startMinutes: assignment.start,
            endMinutes: assignment.end,
            xFraction: place.x,
            widthFraction: place.width
        )
    }
}

/// Live lessons keep most of the lane. Cancelled leftovers and school-calendar events share a
/// narrow trailing strip so they never steal the primary column.
func overlapPlacement(
    for layout: (event: TimetableEvent, column: Int, start: Int, end: Int, total: Int),
    in cluster: [(event: TimetableEvent, column: Int, start: Int, end: Int, total: Int)]
) -> (x: CGFloat, width: CGFloat) {
    let live = cluster
        .filter { $0.event.status != .cancelled && !SchoolCalendar.isSchoolCalendarEvent($0.event) }
        .sorted { lhs, rhs in
            lhs.column == rhs.column ? lhs.event.id < rhs.event.id : lhs.column < rhs.column
        }
    let leftover = cluster
        .filter { $0.event.status == .cancelled || SchoolCalendar.isSchoolCalendarEvent($0.event) }
        .sorted { lhs, rhs in
            let leftCalendar = SchoolCalendar.isSchoolCalendarEvent(lhs.event)
            let rightCalendar = SchoolCalendar.isSchoolCalendarEvent(rhs.event)
            if leftCalendar != rightCalendar { return !leftCalendar }
            if lhs.column != rhs.column { return lhs.column < rhs.column }
            return lhs.event.id < rhs.event.id
        }

    if !live.isEmpty && !leftover.isEmpty {
        let liveShare: CGFloat = 0.70
        let leftoverShare: CGFloat = 0.30
        if layout.event.status == .cancelled || SchoolCalendar.isSchoolCalendarEvent(layout.event) {
            let index = leftover.firstIndex { $0.event.id == layout.event.id } ?? 0
            return (
                liveShare + leftoverShare * CGFloat(index) / CGFloat(leftover.count),
                leftoverShare / CGFloat(leftover.count)
            )
        }
        let index = live.firstIndex { $0.event.id == layout.event.id } ?? 0
        return (
            liveShare * CGFloat(index) / CGFloat(live.count),
            liveShare / CGFloat(live.count)
        )
    }

    let columns = CGFloat(max(1, layout.total))
    return (CGFloat(layout.column) / columns, 1 / columns)
}
