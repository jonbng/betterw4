import XCTest
@testable import BetterW4

final class PersonClassesTests: XCTestCase {

    func testLinkedClassBricksAreListedAndBreakfastIsDropped() throws {
        let monday = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 24))
        let breakfast = TimetableEvent(
            id: "ac-breakfast",
            title: "Breakfast",
            subject: "Breakfast",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 7 * 60),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60 + 15),
            date: monday
        )
        let economics = TimetableEvent(
            id: "ac-econ",
            title: "Economics",
            subject: "Economics",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 8 * 60 + 15),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 5),
            date: monday,
            href: "/index.php?r=academics/classes/class&class_id=1EA16CECOX"
        )
        let math = TimetableEvent(
            id: "ac-math",
            title: "Mathematics Analysis and Approaches",
            subject: "Mathematics Analysis and Approaches",
            source: .academics,
            start: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 5),
            end: W4Dates.date(onDayOf: monday, minutesFromMidnight: 9 * 60 + 55),
            date: monday,
            href: "/index.php?r=academics/classes/class&class_id=1DA13HMTAA"
        )
        let week = ScheduleWeek(
            year: 2026,
            week: 35,
            source: .academics,
            days: [ScheduleDay(date: monday, events: [breakfast, economics, math])]
        )
        XCTAssertEqual(
            PersonClasses.from(week: week),
            [
                PersonClass(classId: "1EA16CECOX", name: "Economics"),
                PersonClass(classId: "1DA13HMTAA", name: "Mathematics Analysis and Approaches")
            ]
        )
    }

    func testCaptionParsesSubjectYearLevelAndRoom() {
        let parsed = PersonClasses.parseCaption(
            "1EA16CECOX: Economics 1st Year C level in room A 1.6"
        )
        XCTAssertEqual(parsed?.subject, "Economics")
        XCTAssertEqual(parsed?.year, "1")
        XCTAssertEqual(parsed?.levelLabel, "HL/SL")
        XCTAssertEqual(parsed?.room, "A 1.6")
    }

    func testMergeIsCaseInsensitiveAndSorted() {
        XCTAssertEqual(
            PersonClasses.merge(
                [PersonClass(classId: "ECO", name: "Economics")],
                [
                    PersonClass(classId: "BIO", name: "biology"),
                    PersonClass(classId: "ECO", name: "Economics")
                ]
            ),
            [
                PersonClass(classId: "BIO", name: "biology"),
                PersonClass(classId: "ECO", name: "Economics")
            ]
        )
    }
}
