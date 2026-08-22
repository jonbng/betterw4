import XCTest
@testable import BetterW4

final class ClassNextLessonTests: XCTestCase {

    private let monday = W4Dates.date(year: 2026, month: 8, day: 24)!
    private let wednesday = W4Dates.date(year: 2026, month: 8, day: 26)!

    func testPicksTheSoonestFutureBlockForTheClass() throws {
        let week = week(
            events: [
                event(
                    id: "math-mon",
                    subject: "Mathematics",
                    day: monday,
                    minutes: 8 * 60 + 15,
                    classId: "1DA13HMTAA",
                    room: "A 1.3"
                ),
                event(
                    id: "econ-mon",
                    subject: "Economics",
                    day: monday,
                    minutes: 9 * 60 + 25,
                    classId: "1EA16CECOX",
                    room: "A 1.6"
                ),
                event(
                    id: "math-wed",
                    subject: "Mathematics",
                    day: wednesday,
                    minutes: 8 * 60 + 15,
                    classId: "1DA13HMTAA",
                    room: "A 1.3"
                )
            ]
        )
        let now = W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60)
        let next = try XCTUnwrap(
            ClassNextLessons.next(in: week, classId: "1DA13HMTAA", now: now)
        )
        XCTAssertTrue(W4Dates.isSameDay(next.start, wednesday))
        XCTAssertEqual(next.room, "A 1.3")
        XCTAssertEqual(next.dayTimeLabel(now: now), "Wed 08:15")
        XCTAssertEqual(next.detailLabel(now: now), "Wed 08:15 · A 1.3")
    }

    func testFallsBackToTheFirstBlockWhenTheWeekHasAlreadyPassed() throws {
        let week = week(
            events: [
                event(
                    id: "math-mon",
                    subject: "Mathematics",
                    day: monday,
                    minutes: 8 * 60 + 15,
                    classId: "1DA13HMTAA",
                    room: "A 1.3"
                )
            ]
        )
        let fridayEvening = W4Dates.date(onDayOf: monday, minutesFromMidnight: 20 * 60)
            .addingTimeInterval(4 * 24 * 60 * 60)
        let next = try XCTUnwrap(
            ClassNextLessons.next(in: week, classId: "1da13hmtaa", now: fridayEvening)
        )
        XCTAssertTrue(W4Dates.isSameDay(next.start, monday))
        XCTAssertEqual(next.dayTimeLabel(now: monday), "Today 08:15")
    }

    func testSkipsBreakfastAndCancelledBlocks() {
        let week = week(
            events: [
                TimetableEvent(
                    id: "breakfast",
                    title: "Breakfast",
                    subject: "Breakfast",
                    source: .academics,
                    start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 7 * 60),
                    end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
                    date: monday
                ),
                event(
                    id: "math-cancelled",
                    subject: "Mathematics",
                    day: monday,
                    minutes: 8 * 60 + 15,
                    classId: "1DA13HMTAA",
                    status: .cancelled
                ),
                event(
                    id: "math-live",
                    subject: "Mathematics",
                    day: wednesday,
                    minutes: 8 * 60 + 15,
                    classId: "1DA13HMTAA",
                    room: "A 1.3"
                )
            ]
        )
        let now = W4Dates.date(onDayOf: monday, minutesFromMidnight: 7 * 60)
        let next = ClassNextLessons.next(in: week, classId: "1DA13HMTAA", now: now)
        XCTAssertEqual(next?.room, "A 1.3")
        XCTAssertTrue(W4Dates.isSameDay(next?.start ?? .distantPast, wednesday))
    }

    func testEmptyWeekReturnsNil() {
        let week = ScheduleWeek(year: 2026, week: 35, source: .academics, days: [
            ScheduleDay(date: monday, events: [])
        ])
        XCTAssertNil(ClassNextLessons.next(in: week, classId: "1DA13HMTAA", now: monday))
        XCTAssertTrue(ClassNextLessons.map(in: week, now: monday).isEmpty)
    }

    private func week(events: [TimetableEvent]) -> ScheduleWeek {
        let byDay = Dictionary(grouping: events, by: \.date)
        let days = byDay.keys.sorted().map { date in
            ScheduleDay(date: date, events: byDay[date] ?? [])
        }
        return ScheduleWeek(year: 2026, week: 35, source: .academics, days: days)
    }

    private func event(
        id: String,
        subject: String,
        day: Date,
        minutes: Int,
        classId: String,
        room: String? = nil,
        status: EventStatus = .normal
    ) -> TimetableEvent {
        TimetableEvent(
            id: id,
            title: subject,
            subject: subject,
            source: .academics,
            start: W4Dates.date(onDayOf: day, minutesFromMidnight: minutes),
            end: W4Dates.date(onDayOf: day, minutesFromMidnight: minutes + 50),
            date: day,
            room: room,
            status: status,
            href: "/index.php?r=academics/classes/class&class_id=\(classId)"
        )
    }
}
