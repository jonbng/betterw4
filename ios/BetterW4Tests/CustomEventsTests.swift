//
//  CustomEventsTests.swift
//  BetterW4Tests
//

import XCTest
@testable import BetterW4

@MainActor
final class CustomEventsTests: XCTestCase {

    func testMakeEventMarksSourceLocal() {
        let start = W4Dates.date(year: 2026, month: 3, day: 10, hour: 9, minute: 0)!
        let end = W4Dates.date(year: 2026, month: 3, day: 10, hour: 10, minute: 0)!
        let event = CustomEvents.makeEvent(title: "Doctor", notes: "  ", start: start, end: end, isAllDay: false)
        XCTAssertEqual(event.source, .local)
        XCTAssertTrue(CustomEvents.isCustomEvent(event))
        XCTAssertTrue(event.id.hasPrefix("local-"))
        XCTAssertNil(event.notes)
    }

    func testDefaultStartRoundsTodayUpToTheNextQuarter() {
        let now = W4Dates.date(year: 2026, month: 3, day: 10, hour: 9, minute: 7)!
        let start = CustomEvents.defaultStart(on: now, now: now)
        XCTAssertEqual(W4Dates.minutesFromMidnight(start), 9 * 60 + 15)
    }

    func testDefaultStartOnAnotherDayIsEight() {
        let now = W4Dates.date(year: 2026, month: 3, day: 10, hour: 15, minute: 0)!
        let day = W4Dates.date(year: 2026, month: 3, day: 11)!
        let start = CustomEvents.defaultStart(on: day, now: now)
        XCTAssertEqual(W4Dates.minutesFromMidnight(start), 8 * 60)
    }

    func testAllDayUsesExclusiveMidnightEnd() {
        let day = W4Dates.date(year: 2026, month: 4, day: 1)!
        let event = CustomEvents.makeEvent(title: "Holiday", notes: nil, start: day, end: day, isAllDay: true)
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.start, W4Dates.startOfDay(day))
        XCTAssertEqual(event.end, W4Dates.adding(days: 1, to: W4Dates.startOfDay(day)))
    }

    func testOverlayAddsCustomEventsAndStripsPreviousOnes() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let biology = TimetableEvent(
            id: "ac-w4-1",
            title: "Biology HL",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
            date: monday
        )
        let stale = CustomEvents.makeEvent(
            id: "local-stale",
            title: "Old",
            notes: nil,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 12 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 13 * 60),
            isAllDay: false
        )
        let fresh = CustomEvents.makeEvent(
            id: "local-fresh",
            title: "Run",
            notes: nil,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 17 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 18 * 60),
            isAllDay: false
        )
        let week = ScheduleWeek(
            year: 2026,
            week: 33,
            source: .academics,
            days: [ScheduleDay(date: monday, dayName: "Monday", events: [biology, stale])]
        )

        let merged = CustomEvents.overlay(week, with: [fresh])
        let titles = merged.days[0].events.map(\.title)
        XCTAssertEqual(titles, ["Biology HL", "Run"])
        XCTAssertFalse(merged.allEvents.contains(where: { $0.id == "local-stale" }))
    }

    func testStoreIsScopedPerStudentAndSurvivesReactivate() {
        let suite = "CustomEventsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CustomEventsStore(defaults: defaults)

        store.activate(studentId: "nc16alice")
        let start = W4Dates.date(year: 2026, month: 3, day: 10, hour: 9, minute: 0)!
        store.save(title: "Dentist", notes: "", start: start, end: start.addingTimeInterval(3600), isAllDay: false)
        XCTAssertEqual(store.events.count, 1)

        store.activate(studentId: "nc16bob")
        XCTAssertTrue(store.events.isEmpty)

        store.activate(studentId: "nc16alice")
        XCTAssertEqual(store.events.map(\.title), ["Dentist"])

        defaults.removePersistentDomain(forName: suite)
    }

    func testStoreDeleteRemovesPersistedEvent() {
        let suite = "CustomEventsStoreTests.delete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CustomEventsStore(defaults: defaults)

        store.activate(studentId: "nc16alice")
        let start = W4Dates.date(year: 2026, month: 3, day: 10, hour: 9, minute: 0)!
        let created = store.save(title: "Gym", notes: "", start: start, end: start.addingTimeInterval(3600), isAllDay: false)
        store.delete(id: created.id)

        store.activate(studentId: "nc16alice")
        XCTAssertTrue(store.events.isEmpty)

        defaults.removePersistentDomain(forName: suite)
    }
}
