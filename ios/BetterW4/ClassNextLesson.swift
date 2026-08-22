//
//  ClassNextLesson.swift
//  BetterW4
//
//  The next (or this week's first) timetable block for a class, from a week
//  that is already in the cache. No network.
//

import Foundation

struct ClassNextLesson: Equatable, Sendable {
    let start: Date
    let room: String?

    /// `Today 10:00` when the block is today in Oslo, otherwise `Wed 10:00`.
    func dayTimeLabel(now: Date) -> String {
        let time = W4Dates.formatTime(start)
        if W4Dates.isSameDay(start, now) {
            return "Today \(time)"
        }
        let weekday = W4Dates.weekdayName(of: start)
        let short = weekday.count >= 3 ? String(weekday.prefix(3)) : weekday
        return "\(short) \(time)"
    }

    func detailLabel(now: Date) -> String {
        let dayTime = dayTimeLabel(now: now)
        if let room, !room.isEmpty {
            return "\(dayTime) · \(room)"
        }
        return dayTime
    }
}

enum ClassNextLessons {
    /// Earliest block for `classId` with `start >= now`, else the first block
    /// of the week. `nil` when this week has no linked class brick.
    static func next(in week: ScheduleWeek, classId: String, now: Date) -> ClassNextLesson? {
        map(in: week, now: now)[classId.lowercased()]
    }

    /// One entry per class id found on the week, keyed lowercased.
    static func map(in week: ScheduleWeek, now: Date) -> [String: ClassNextLesson] {
        var grouped: [String: [TimetableEvent]] = [:]
        for event in week.allEvents {
            guard let classId = ClassRoster.classId(from: event.href) else { continue }
            guard let start = event.start, !event.isAllDay else { continue }
            if event.status == .cancelled { continue }
            grouped[classId.lowercased(), default: []].append(event)
        }
        var result: [String: ClassNextLesson] = [:]
        for (id, events) in grouped {
            guard let picked = pick(events, now: now) else { continue }
            result[id] = ClassNextLesson(
                start: picked.start ?? now,
                room: picked.room?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }
        return result
    }

    private static func pick(_ events: [TimetableEvent], now: Date) -> TimetableEvent? {
        let ordered = events.sorted { lhs, rhs in
            (lhs.start ?? .distantFuture) < (rhs.start ?? .distantFuture)
        }
        if let upcoming = ordered.first(where: { ($0.start ?? .distantPast) >= now }) {
            return upcoming
        }
        return ordered.first
    }
}
