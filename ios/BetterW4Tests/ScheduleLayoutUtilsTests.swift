import XCTest
@testable import BetterW4

final class ScheduleLayoutUtilsTests: XCTestCase {

    func testSchoolCalendarYieldsPrimaryColumnToALesson() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let lesson = TimetableEvent(
            id: "ac-w4-econ",
            title: "Economics",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60 + 15),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 5),
            date: monday
        )
        let calendar = TimetableEvent(
            id: "gcal-assembly",
            title: "Assembly",
            source: .schoolCalendar,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 12 * 60),
            date: monday
        )

        let layouts = calculateEventOverlapLayouts(for: [calendar, lesson])
        let lessonLayout = try XCTUnwrap(layouts.first { $0.event.id == "ac-w4-econ" })
        let calendarLayout = try XCTUnwrap(layouts.first { $0.event.id == "gcal-assembly" })

        XCTAssertEqual(lessonLayout.widthFraction, 0.70, accuracy: 0.001)
        XCTAssertEqual(lessonLayout.xFraction, 0, accuracy: 0.001)
        XCTAssertEqual(calendarLayout.widthFraction, 0.30, accuracy: 0.001)
        XCTAssertEqual(calendarLayout.xFraction, 0.70, accuracy: 0.001)
    }

    func testTwoLiveOverlapsStillSplitEqually() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let a = TimetableEvent(
            id: "ac-a",
            title: "A",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
            date: monday
        )
        let b = TimetableEvent(
            id: "ac-b",
            title: "B",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
            date: monday
        )

        let layouts = calculateEventOverlapLayouts(for: [a, b])
        XCTAssertEqual(layouts.count, 2)
        XCTAssertEqual(layouts[0].widthFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(layouts[1].widthFraction, 0.5, accuracy: 0.001)
    }

    func testAdjacentBreakStaysFullWidthBetweenLessons() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let math = TimetableEvent(
            id: "ac-math",
            title: "Mathematics",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 5),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 55),
            date: monday
        )
        let pause = TimetableEvent(
            id: "ac-break",
            title: "Break",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 55),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60 + 10),
            date: monday
        )
        let tok = TimetableEvent(
            id: "ac-tok",
            title: "TOK",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60 + 10),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 11 * 60 + 30),
            date: monday
        )

        let layouts = calculateEventOverlapLayouts(for: [math, pause, tok])
        XCTAssertEqual(layouts.count, 3)
        for layout in layouts {
            XCTAssertEqual(layout.widthFraction, 1, accuracy: 0.001)
            XCTAssertEqual(layout.column, 0)
        }

        let breakLayout = try XCTUnwrap(layouts.first { $0.event.id == "ac-break" })
        XCTAssertEqual(breakLayout.endMinutes - breakLayout.startMinutes, 15)
        XCTAssertEqual(
            ScheduleTimelineGeometry.visualEndMinutes(of: breakLayout, among: layouts),
            breakLayout.endMinutes
        )
    }

    func testIsolatedShortBlockGrowsVisuallyWithoutInventingOverlap() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let pause = TimetableEvent(
            id: "ac-break",
            title: "Break",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 55),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60 + 10),
            date: monday
        )

        let layouts = calculateEventOverlapLayouts(for: [pause])
        let breakLayout = try XCTUnwrap(layouts.first)
        XCTAssertEqual(breakLayout.widthFraction, 1, accuracy: 0.001)
        XCTAssertEqual(breakLayout.endMinutes - breakLayout.startMinutes, 15)
        XCTAssertEqual(
            ScheduleTimelineGeometry.visualEndMinutes(of: breakLayout, among: layouts),
            breakLayout.startMinutes + ScheduleTimelineGeometry.minimumVisualMinutes
        )
    }

    func testShortBlockGrowsOnlyIntoTheGapBeforeTheNextLesson() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let pause = TimetableEvent(
            id: "ac-break",
            title: "Break",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 55),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60 + 10),
            date: monday
        )
        let tok = TimetableEvent(
            id: "ac-tok",
            title: "TOK",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60 + 20),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 11 * 60 + 30),
            date: monday
        )

        let layouts = calculateEventOverlapLayouts(for: [pause, tok])
        let breakLayout = try XCTUnwrap(layouts.first { $0.event.id == "ac-break" })
        let tokLayout = try XCTUnwrap(layouts.first { $0.event.id == "ac-tok" })
        XCTAssertEqual(breakLayout.widthFraction, 1, accuracy: 0.001)
        XCTAssertEqual(
            ScheduleTimelineGeometry.visualEndMinutes(of: breakLayout, among: layouts),
            tokLayout.startMinutes
        )
    }

    func testSchoolCalendarBeforeALessonKeepsFullWidth() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let calendar = TimetableEvent(
            id: "gcal-briefing",
            title: "Briefing",
            source: .schoolCalendar,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 7 * 60 + 30),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            date: monday
        )
        let lesson = TimetableEvent(
            id: "ac-w4-econ",
            title: "Economics",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60 + 15),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 5),
            date: monday
        )

        let layouts = calculateEventOverlapLayouts(for: [calendar, lesson])
        XCTAssertEqual(layouts.count, 2)
        XCTAssertEqual(layouts[0].widthFraction, 1, accuracy: 0.001)
        XCTAssertEqual(layouts[1].widthFraction, 1, accuracy: 0.001)
    }
}
