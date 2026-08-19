//
//  NotificationDiff.swift
//  BetterW4
//
//  On-device diffs for OS notifications.
//
//  W4 has no Lectio-style cancelled/changed brick classes. Timetable "moved"
//  is a fingerprint of start/end/room for the same class on the same day.
//

import Foundation

enum NotificationDiff: Sendable {

    static let horizonHours: Double = 48
    static let maxPerCategory = 5

    enum LessonChangeKind: String, Sendable {
        case cancelled
        case moved
        case room
        case changed
    }

    enum AssessmentChangeKind: String, Sendable {
        case new
        case overdue
    }

    enum TripChangeKind: String, Sendable {
        case new
        case status
    }

    struct LessonWatch: Equatable, Sendable {
        let identity: String
        let title: String
        let timeLabel: String
        let room: String?
        let fingerprint: String
        let start: Date
        let end: Date
    }

    struct AssessmentWatch: Equatable, Sendable {
        let id: String
        let title: String
        let subtitle: String?
        let state: String
    }

    struct TripWatch: Equatable, Sendable {
        let id: String
        let name: String
        let status: String
    }

    struct Snapshot: Equatable, Sendable {
        var lessons: [LessonWatch] = []
        var assessments: [AssessmentWatch] = []
        var trips: [TripWatch] = []
    }

    struct LessonChange: Equatable, Sendable {
        let identity: String
        let title: String
        let kind: LessonChangeKind
        let timeLabel: String
        let detail: String?
    }

    struct AssessmentChange: Equatable, Sendable {
        let id: String
        let title: String
        let kind: AssessmentChangeKind
        let subtitle: String?
    }

    struct TripChange: Equatable, Sendable {
        let id: String
        let name: String
        let kind: TripChangeKind
        let status: String
    }

    // MARK: - Watch

    static func watchLessons(
        _ events: [TimetableEvent],
        now: Date = TimeProvider.now,
        horizonHours: Double = horizonHours
    ) -> [LessonWatch] {
        let horizon = now.addingTimeInterval(horizonHours * 3600)
        var grouped: [String: [TimetableEvent]] = [:]
        var order: [String] = []
        for event in events {
            if event.isAllDay { continue }
            if event.source == .schoolCalendar || event.source == .local { continue }
            guard let start = event.start else { continue }
            let end = event.end ?? start.addingTimeInterval(45 * 60)
            if end <= now { continue }
            if start > horizon { continue }
            let identity = lessonIdentity(event)
            if grouped[identity] == nil {
                order.append(identity)
            }
            grouped[identity, default: []].append(event)
        }
        return order.compactMap { identity in
            guard let group = grouped[identity], !group.isEmpty else { return nil }
            let ordered = group.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
            let first = ordered[0]
            guard let start = first.start else { return nil }
            let end = ordered.last?.end ?? start
            return LessonWatch(
                identity: identity,
                title: first.title,
                timeLabel: timeLabel(ordered),
                room: uniqueRooms(ordered),
                fingerprint: fingerprint(ordered),
                start: start,
                end: end
            )
        }
    }

    static func watchAssessments(_ items: [Assessment]) -> [AssessmentWatch] {
        items.compactMap { item in
            if item.kind == .studentCreated { return nil }
            let state: String
            if item.isDone {
                state = "done"
            } else if item.isOverdue {
                state = "overdue"
            } else {
                state = "pending"
            }
            return AssessmentWatch(
                id: item.id,
                title: item.title,
                subtitle: item.subject,
                state: state
            )
        }
    }

    static func watchTrips(_ trips: [Trip]) -> [TripWatch] {
        trips.map { trip in
            TripWatch(
                id: trip.id,
                name: trip.name,
                status: trip.status == .unknown
                    ? normalizeTripStatus(trip.statusLabel)
                    : trip.status.rawValue
            )
        }
    }

    // MARK: - Diff

    static func diffLessons(
        previous: [LessonWatch],
        current: [LessonWatch],
        now: Date = TimeProvider.now
    ) -> [LessonChange] {
        let currentById = Dictionary(uniqueKeysWithValues: current.map { ($0.identity, $0) })
        var changes: [LessonChange] = []
        for before in previous {
            if before.end <= now { continue }
            guard let after = currentById[before.identity] else {
                changes.append(
                    LessonChange(
                        identity: before.identity,
                        title: before.title,
                        kind: .cancelled,
                        timeLabel: before.timeLabel,
                        detail: before.room
                    )
                )
                continue
            }
            if after.fingerprint == before.fingerprint { continue }
            changes.append(
                LessonChange(
                    identity: before.identity,
                    title: after.title,
                    kind: lessonKind(before: before, after: after),
                    timeLabel: after.timeLabel,
                    detail: after.room
                )
            )
        }
        return Array(changes.prefix(maxPerCategory))
    }

    static func diffAssessments(
        previous: [AssessmentWatch],
        current: [AssessmentWatch]
    ) -> [AssessmentChange] {
        let previousById = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        var changes: [AssessmentChange] = []
        for item in current {
            if item.state == "done" { continue }
            let before = previousById[item.id]
            if before == nil, item.state == "pending" {
                changes.append(AssessmentChange(id: item.id, title: item.title, kind: .new, subtitle: item.subtitle))
            } else if before == nil, item.state == "overdue" {
                changes.append(AssessmentChange(id: item.id, title: item.title, kind: .overdue, subtitle: item.subtitle))
            } else if let before, before.state != "overdue", item.state == "overdue" {
                changes.append(AssessmentChange(id: item.id, title: item.title, kind: .overdue, subtitle: item.subtitle))
            }
        }
        return Array(changes.prefix(maxPerCategory))
    }

    static func diffTrips(
        previous: [TripWatch],
        current: [TripWatch]
    ) -> [TripChange] {
        let previousById = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        var changes: [TripChange] = []
        for trip in current {
            if previousById[trip.id] == nil {
                changes.append(TripChange(id: trip.id, name: trip.name, kind: .new, status: trip.status))
            } else if previousById[trip.id]?.status != trip.status {
                changes.append(TripChange(id: trip.id, name: trip.name, kind: .status, status: trip.status))
            }
        }
        return Array(changes.prefix(maxPerCategory))
    }

    // MARK: - Persistence

    static func encode(_ snapshot: Snapshot) -> [String] {
        var keys: [String] = []
        for lesson in snapshot.lessons {
            keys.append(
                ["L", lesson.identity, lesson.fingerprint, lesson.title, lesson.timeLabel,
                 lesson.room ?? "", String(lesson.start.timeIntervalSince1970),
                 String(lesson.end.timeIntervalSince1970)].joined(separator: rs)
            )
        }
        for item in snapshot.assessments {
            keys.append(
                ["A", item.id, item.state, item.title, item.subtitle ?? ""].joined(separator: rs)
            )
        }
        for trip in snapshot.trips {
            keys.append(["T", trip.id, trip.status, trip.name].joined(separator: rs))
        }
        return keys
    }

    static func decode(_ keys: [String]) -> Snapshot {
        var lessons: [LessonWatch] = []
        var assessments: [AssessmentWatch] = []
        var trips: [TripWatch] = []
        for raw in keys {
            let parts = raw.split(separator: Character(rs), omittingEmptySubsequences: false).map(String.init)
            switch parts.first {
            case "L" where parts.count >= 8:
                let start = Date(timeIntervalSince1970: Double(parts[6]) ?? 0)
                let end = Date(timeIntervalSince1970: Double(parts[7]) ?? 0)
                lessons.append(
                    LessonWatch(
                        identity: parts[1],
                        title: parts[3],
                        timeLabel: parts[4],
                        room: parts[5].isEmpty ? nil : parts[5],
                        fingerprint: parts[2],
                        start: start,
                        end: end
                    )
                )
            case "A" where parts.count >= 5:
                assessments.append(
                    AssessmentWatch(
                        id: parts[1],
                        title: parts[3],
                        subtitle: parts[4].isEmpty ? nil : parts[4],
                        state: parts[2]
                    )
                )
            case "T" where parts.count >= 4:
                trips.append(TripWatch(id: parts[1], name: parts[3], status: parts[2]))
            default:
                continue
            }
        }
        return Snapshot(lessons: lessons, assessments: assessments, trips: trips)
    }

    static func lessonIdentity(_ event: TimetableEvent) -> String {
        let classKey = event.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let day = W4Dates.format(event.date)
        return "\(event.source.rawValue)|\(day)|\(classKey)"
    }

    static func normalizeTripStatus(_ raw: String) -> String {
        let mapped = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        let text = String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if text.contains("pending") || text.contains("awaiting")
            || text.contains("for confirmation") || text.contains("submitted") {
            return "pendingConfirmation"
        }
        if text.contains("cancel") || text.contains("rejected") || text.contains("declined")
            || text.contains("withdrawn") || text.contains("not approved") {
            return "cancelled"
        }
        if text.contains("approved") || text.contains("confirmed") || text.contains("accepted") {
            return "approved"
        }
        if text.contains("planning") || text.contains("planned") || text.contains("draft") {
            return "planning"
        }
        return text.isEmpty ? "unknown" : text
    }

    // MARK: - Private

    private static let rs = "\u{001e}"

    private static func fingerprint(_ events: [TimetableEvent]) -> String {
        events.map { event in
            let start = event.start.map(W4Dates.formatTime) ?? ""
            let end = event.end.map(W4Dates.formatTime) ?? ""
            let room = (event.room ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(start)-\(end)|\(room)"
        }.joined(separator: ";")
    }

    private static func timeLabel(_ events: [TimetableEvent]) -> String {
        guard let first = events.first?.start else { return "" }
        let last = events.last?.end ?? events.last?.start ?? first
        return "\(W4Dates.formatTime(first))–\(W4Dates.formatTime(last))"
    }

    private static func uniqueRooms(_ events: [TimetableEvent]) -> String? {
        var seen = Set<String>()
        var unique: [String] = []
        for event in events {
            let trimmed = event.room?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            unique.append(trimmed)
        }
        if unique.count == 1 { return unique[0] }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private static func lessonKind(before: LessonWatch, after: LessonWatch) -> LessonChangeKind {
        if before.start != after.start || before.timeLabel != after.timeLabel {
            return .moved
        }
        if before.room != after.room {
            return .room
        }
        return .changed
    }
}
