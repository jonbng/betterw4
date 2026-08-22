import XCTest
@testable import BetterW4

final class PersonBirthdayTests: XCTestCase {

    func testParsesW4ShortMonth() throws {
        let parsed = try XCTUnwrap(PersonBirthday.parse("28-Jan"))
        XCTAssertEqual(parsed.month, 1)
        XCTAssertEqual(parsed.day, 28)
        XCTAssertEqual(parsed.display, "28 January")
    }

    func testParsesStaffShortMonth() throws {
        let parsed = try XCTUnwrap(PersonBirthday.parse("17-Nov"))
        XCTAssertEqual(parsed.month, 11)
        XCTAssertEqual(parsed.day, 17)
        XCTAssertEqual(parsed.display, "17 November")
    }

    func testParsesLongMonthAndStripsYear() throws {
        let parsed = try XCTUnwrap(PersonBirthday.parse("1 January 2008"))
        XCTAssertEqual(parsed.month, 1)
        XCTAssertEqual(parsed.day, 1)
        XCTAssertEqual(parsed.display, "1 January")
    }

    func testDaysUntilTodayAndTomorrow() throws {
        let today = try XCTUnwrap(W4Dates.date(year: 2026, month: 8, day: 21))
        let same = try XCTUnwrap(PersonBirthday.parse("21-Aug"))
        XCTAssertEqual(same.daysUntil(from: today), 0)
        XCTAssertEqual(same.relativeLabel(from: today), "Today")

        let tomorrow = try XCTUnwrap(PersonBirthday.parse("22-Aug"))
        XCTAssertEqual(tomorrow.daysUntil(from: today), 1)
        XCTAssertEqual(tomorrow.relativeLabel(from: today), "Tomorrow")

        let january = try XCTUnwrap(PersonBirthday.parse("28-Jan"))
        XCTAssertEqual(january.daysUntil(from: today), 160)
        XCTAssertEqual(january.relativeLabel(from: today), "In 160 days")
    }

    func testFeb29ClampsInCommonYear() throws {
        let today = try XCTUnwrap(W4Dates.date(year: 2026, month: 2, day: 28))
        let parsed = try XCTUnwrap(PersonBirthday.parse("29-Feb"))
        XCTAssertEqual(parsed.daysUntil(from: today), 0)
    }
}
