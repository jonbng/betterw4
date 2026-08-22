//
//  W4BirthdayParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance: birthdays.html is [I] SYNTHESIZED from the live
//  people/birthdays shape captured 21 Aug 2026. Identities are invented.
//

import XCTest
@testable import BetterW4

final class W4BirthdayParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testReadsMonthYearAndAdjacentLinks() throws {
        let month = W4BirthdayParser.parse(try fixture("birthdays"))
        XCTAssertEqual(month.monthLabel, "August 2026")
        XCTAssertEqual(month.year, 2026)
        XCTAssertEqual(month.month, 8)
        XCTAssertEqual(month.previous, BirthdayMonthRef(year: 2026, month: 7))
        XCTAssertEqual(month.next, BirthdayMonthRef(year: 2026, month: 9))
    }

    func testReadsNamedPeopleAndKindFromEachHref() throws {
        let month = W4BirthdayParser.parse(try fixture("birthdays"))
        let first = try XCTUnwrap(month.days.first { $0.dayNumber == 1 })
        XCTAssertEqual(first.people.map(\.uwcId), ["nc00aaa", "nc00bbb"])
        XCTAssertEqual(first.people.map(\.displayName), ["Alex Andersen", "Bea Beltran"])
        XCTAssertEqual(first.people.map(\.isStaff), [false, false])

        let second = try XCTUnwrap(month.days.first { $0.dayNumber == 2 })
        XCTAssertEqual(second.people.map(\.uwcId), ["nc00ccc", "nc00ddd"])
        XCTAssertEqual(second.people.map(\.isStaff), [true, false])
        XCTAssertEqual(second.people.last?.displayName, "Ann Ong'uti")
        XCTAssertEqual(second.date, W4Dates.date(year: 2026, month: 8, day: 2))
    }

    func testPlaceholderPhotoIsDroppedAndThumbsAreUpgraded() throws {
        let month = W4BirthdayParser.parse(try fixture("birthdays"))
        let placeholder = try XCTUnwrap(month.days.first { $0.dayNumber == 8 }?.people.first)
        XCTAssertEqual(placeholder.displayName, "Eli Eriksen")
        XCTAssertNil(placeholder.photoURL)

        let named = try XCTUnwrap(month.days.first { $0.dayNumber == 21 }?.people.first)
        XCTAssertEqual(named.photoURL?.absoluteString, "https://w4.uwcrcn.no/files/user_photos/nc00ggg_photo.jpg")
    }

    func testMixedDayKeepsStaffAndStudentsTogether() throws {
        let month = W4BirthdayParser.parse(try fixture("birthdays"))
        let day = try XCTUnwrap(month.days.first { $0.dayNumber == 27 })
        XCTAssertEqual(day.people.map(\.uwcId), ["nc00fff", "nc00hhh", "nc00iii"])
        XCTAssertEqual(day.people.map(\.isStaff), [true, false, false])
        XCTAssertEqual(day.people.first?.roleLabel, "Staff")
    }

    func testEmptyDayIsKeptAndNoDayCellsAreSkipped() throws {
        let month = W4BirthdayParser.parse(try fixture("birthdays"))
        XCTAssertTrue(month.days.contains { $0.dayNumber == 3 && $0.people.isEmpty })
        XCTAssertFalse(month.days.contains { $0.dayNumber == 0 })
        XCTAssertEqual(
            month.daysWithPeople().map(\.dayNumber),
            [1, 2, 8, 21, 27, 31]
        )
    }

    func testFilterDropsTheOtherKind() throws {
        let month = W4BirthdayParser.parse(try fixture("birthdays")).filtered(by: .staff)
        XCTAssertEqual(month.people.map(\.uwcId), ["nc00ccc", "nc00fff"])
        XCTAssertTrue(month.days.first { $0.dayNumber == 21 }?.people.isEmpty ?? false)
    }

    func testUnparseableHtmlIsEmpty() {
        let month = W4BirthdayParser.parse("")
        XCTAssertTrue(month.isEmpty)
        XCTAssertNil(month.year)
    }
}
