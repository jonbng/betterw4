import XCTest
@testable import BetterW4

final class ScheduleNowClockTests: XCTestCase {

    func testCapturedHomePageNowLineSitsAt394From0700() throws {
        let friday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 14, hour: 13, minute: 34))
        let week = ScheduleWeek(
            year: 2026,
            week: 33,
            source: .academics,
            startHour: 7,
            endHour: 22,
            days: [ScheduleDay(date: W4Dates.startOfDay(friday), dayName: "Friday")]
        )

        XCTAssertEqual(week.nowMinutesFromStart(now: friday), 394)
        XCTAssertEqual(
            ScheduleTimelineGeometry.offset(forMinutesFromMidnight: 13 * 60 + 34, originMinutes: 7 * 60),
            394
        )
    }

    func testNowLineIsHiddenOnAnotherDayAndBeforeTheOrigin() throws {
        let friday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 14, hour: 13, minute: 34))
        let thursday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 13))
        let week = ScheduleWeek(
            year: 2026,
            week: 33,
            source: .academics,
            startHour: 7,
            endHour: 22,
            days: [ScheduleDay(date: thursday, dayName: "Thursday")]
        )

        XCTAssertNil(week.nowMinutesFromStart(now: friday))
        XCTAssertNil(
            ScheduleTimelineGeometry.offset(forMinutesFromMidnight: 7 * 60 + 45, originMinutes: 8 * 60)
        )
    }

    func testSecondsUntilNextOsloMinuteIsTheRemainder() throws {
        let onTheMinute = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 14, hour: 13, minute: 34))
        XCTAssertEqual(TimeProvider.secondsUntilNextMinute(after: onTheMinute), 60, accuracy: 0.01)

        let midMinute = onTheMinute.addingTimeInterval(15)
        XCTAssertEqual(TimeProvider.secondsUntilNextMinute(after: midMinute), 45, accuracy: 0.01)

        let lastSecond = onTheMinute.addingTimeInterval(59)
        XCTAssertEqual(TimeProvider.secondsUntilNextMinute(after: lastSecond), 1, accuracy: 0.01)
    }

    func testCountdownRoundsUpAndClearsAtTheEnd() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let lesson = TimetableEvent(
            id: "ac-math",
            title: "Mathematics",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
            date: monday
        )

        let halfHour = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10, hour: 8, minute: 30))
        XCTAssertEqual(lesson.minutesRemaining(at: halfHour), 30)
        XCTAssertEqual(lesson.minutesRemaining(at: halfHour.addingTimeInterval(1)), 30)
        XCTAssertEqual(
            lesson.minutesRemaining(at: try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10, hour: 8, minute: 59)).addingTimeInterval(1)),
            1
        )

        let start = try XCTUnwrap(lesson.start)
        XCTAssertTrue(lesson.isLive(at: start))
        let end = try XCTUnwrap(lesson.end)
        XCTAssertFalse(lesson.isLive(at: end))
        XCTAssertNil(lesson.minutesRemaining(at: end))
    }

    func testCancelledAndSchoolCalendarNeverDriveTheCountdown() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10))
        let cancelled = TimetableEvent(
            id: "ac-old",
            title: "Old Maths",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
            date: monday,
            status: .cancelled
        )
        let assembly = TimetableEvent(
            id: "gcal-assembly",
            title: "Assembly",
            source: .schoolCalendar,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 12 * 60),
            date: monday
        )
        let math = TimetableEvent(
            id: "ac-math",
            title: "Mathematics",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 10 * 60),
            date: monday
        )

        XCTAssertFalse(cancelled.drivesCountdown)
        XCTAssertFalse(assembly.drivesCountdown)
        XCTAssertTrue(math.drivesCountdown)

        let duringCancelled = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 10, hour: 8, minute: 30))
        XCTAssertFalse(cancelled.isLive(at: duringCancelled))
        XCTAssertFalse(assembly.isLive(at: duringCancelled))
        XCTAssertEqual(math.minutesUntilStart(from: duringCancelled), 30)
    }
}
