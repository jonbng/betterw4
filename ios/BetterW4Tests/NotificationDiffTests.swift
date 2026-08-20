//
//  NotificationDiffTests.swift
//  BetterW4Tests
//

import XCTest
@testable import BetterW4

@MainActor
final class NotificationDiffTests: XCTestCase {

    private let day = W4Dates.date(year: 2026, month: 8, day: 20)!
    private let now = W4Dates.date(year: 2026, month: 8, day: 20, hour: 8, minute: 0)!

    func testLessonMove_sameClassSameDay_isMoved() {
        let previous = NotificationDiff.watchLessons(
            [lesson("Economics", hour: 9, room: "A12")],
            now: now
        )
        let current = NotificationDiff.watchLessons(
            [lesson("Economics", hour: 14, room: "A12")],
            now: now
        )
        let changes = NotificationDiff.diffLessons(previous: previous, current: current, now: now)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, .moved)
        XCTAssertEqual(changes.first?.title, "Economics")
    }

    func testLessonRoomChange_isRoom() {
        let previous = NotificationDiff.watchLessons(
            [lesson("Biology HL", hour: 9, room: "Lab 1")],
            now: now
        )
        let current = NotificationDiff.watchLessons(
            [lesson("Biology HL", hour: 9, room: "Lab 2")],
            now: now
        )
        let changes = NotificationDiff.diffLessons(previous: previous, current: current, now: now)
        XCTAssertEqual(changes.first?.kind, .room)
    }

    func testLessonDisappeared_isCancelled() {
        let previous = NotificationDiff.watchLessons(
            [lesson("TOK", hour: 11, room: "A1")],
            now: now
        )
        let changes = NotificationDiff.diffLessons(previous: previous, current: [], now: now)
        XCTAssertEqual(changes.first?.kind, .cancelled)
    }

    func testPastLessonMissing_isNotCancelled() {
        let sixFifty = W4Dates.date(year: 2026, month: 8, day: 20, hour: 6, minute: 50)!
        let previous = NotificationDiff.watchLessons(
            [lesson("History", hour: 7, room: "B2")],
            now: sixFifty
        )
        let later = W4Dates.date(year: 2026, month: 8, day: 20, hour: 9, minute: 0)!
        let changes = NotificationDiff.diffLessons(previous: previous, current: [], now: later)
        XCTAssertTrue(changes.isEmpty)
    }

    func testSchoolCalendarEvents_areIgnored() {
        let event = lesson("Assembly", hour: 9, room: "Hall", source: .schoolCalendar)
        let watched = NotificationDiff.watchLessons([event], now: now)
        XCTAssertTrue(watched.isEmpty)
    }

    func testNewPendingAssessment_isNew() {
        let item = assessment(id: "class:1", title: "Biology IA", overdue: false)
        let current = NotificationDiff.watchAssessments([item])
        let changes = NotificationDiff.diffAssessments(previous: [], current: current)
        XCTAssertEqual(changes.first?.kind, .new)
    }

    func testPendingBecomingOverdue_isOverdue() {
        let pending = assessment(id: "class:2", title: "Essay", overdue: false)
        let overdue = assessment(id: "class:2", title: "Essay", overdue: true)
        let previous = NotificationDiff.watchAssessments([pending])
        let current = NotificationDiff.watchAssessments([overdue])
        let changes = NotificationDiff.diffAssessments(previous: previous, current: current)
        XCTAssertEqual(changes.first?.kind, .overdue)
    }

    func testStudentCreatedAssessment_isIgnored() {
        let item = assessment(id: "student:9", title: "My reminder", overdue: false, kind: .studentCreated)
        let watched = NotificationDiff.watchAssessments([item])
        XCTAssertTrue(watched.isEmpty)
    }

    func testTripStatusChange_isStatus() {
        let previous = NotificationDiff.watchTrips([trip(id: "t1", name: "Bergen weekend", status: .planning)])
        let current = NotificationDiff.watchTrips([trip(id: "t1", name: "Bergen weekend", status: .approved)])
        let changes = NotificationDiff.diffTrips(previous: previous, current: current)
        XCTAssertEqual(changes.first?.kind, .status)
        XCTAssertEqual(changes.first?.status, "approved")
    }

    func testNewTrip_isNew() {
        let current = NotificationDiff.watchTrips([trip(id: "t2", name: "Kayaking", status: .planning)])
        let changes = NotificationDiff.diffTrips(previous: [], current: current)
        XCTAssertEqual(changes.first?.kind, .new)
    }

    func testEncodeRoundTrip_preservesIdentity() {
        let snapshot = NotificationDiff.Snapshot(
            lessons: NotificationDiff.watchLessons([lesson("Economics", hour: 9, room: "A12")], now: now),
            assessments: NotificationDiff.watchAssessments([assessment(id: "class:1", title: "IA", overdue: false)]),
            trips: NotificationDiff.watchTrips([trip(id: "t1", name: "Bergen weekend", status: .planning)])
        )
        let restored = NotificationDiff.decode(NotificationDiff.encode(snapshot))
        XCTAssertEqual(restored.lessons.first?.identity, snapshot.lessons.first?.identity)
        XCTAssertEqual(restored.assessments.first?.id, "class:1")
        XCTAssertEqual(restored.trips.first?.status, "planning")
    }

    private func lesson(
        _ title: String,
        hour: Int,
        room: String,
        source: EventSource = .academics
    ) -> TimetableEvent {
        let start = W4Dates.date(onDayOf: day, minutesFromMidnight: hour * 60)
        let end = W4Dates.date(onDayOf: day, minutesFromMidnight: (hour + 1) * 60)
        return TimetableEvent(
            id: "ac-w4-\(title)",
            title: title,
            subject: title,
            source: source,
            start: start,
            end: end,
            date: day,
            room: room
        )
    }

    private func assessment(
        id: String,
        title: String,
        overdue: Bool,
        kind: AssessmentKind = .classAssigned
    ) -> Assessment {
        Assessment(
            id: id,
            rawId: id.split(separator: ":").last.map(String.init) ?? id,
            kind: kind,
            rawKind: kind.rawValue,
            title: title,
            subject: "Biology",
            status: .pending,
            rawStatus: "pending",
            isOverdue: overdue
        )
    }

    private func trip(id: String, name: String, status: TripStatus) -> Trip {
        Trip(
            id: id,
            name: name,
            outgoingLabel: "20-Sep-2026 08:00",
            returningLabel: "21-Sep-2026 18:00",
            destination: "Bergen",
            type: "Optional",
            participants: 12,
            status: status,
            statusLabel: status.displayName
        )
    }
}
