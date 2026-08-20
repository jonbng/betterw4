//
//  ClassRosterTests.swift
//  BetterW4Tests
//
//  class-mtaa.html is [I] SYNTHESIZED from the live class page shape
//  (dl.class-details + ul.student-list). These tests verify class-id
//  extraction and that the people parser reads a class-shaped page.
//

import XCTest
@testable import BetterW4

final class ClassRosterTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testClassIdComesFromTheBrickHref() {
        XCTAssertEqual(
            ClassRoster.classId(from: "/index.php?r=academics/classes/class&class_id=1EA16CECOX"),
            "1EA16CECOX"
        )
        XCTAssertEqual(
            ClassRoster.classId(from: "index.php?r=academics/classes/class&class_id=1DA13HMTAA"),
            "1DA13HMTAA"
        )
    }

    func testBreakfastAndBlankHrefsHaveNoClass() {
        XCTAssertNil(ClassRoster.classId(from: nil))
        XCTAssertNil(ClassRoster.classId(from: ""))
        XCTAssertNil(ClassRoster.classId(from: "/index.php?r=academics/timetable/room&room_id=a16"))
    }

    /// **[I]** The class page is a people list: staff first, then students, kind
    /// from each row's href.
    func testClassPageYieldsTeacherAndStudents() throws {
        let page = W4PeopleParser.parseList(try fixture("class-mtaa"))
        XCTAssertEqual(page.people.map(\.uwcId), ["nc00jjen", "nc00aaa", "nc00bbb", "nc00ccc"])
        XCTAssertEqual(page.people.first?.kind, .staff)
        XCTAssertEqual(page.people.first?.name, "Jens Jensen")
        XCTAssertEqual(page.people[1].kind, .student)
        XCTAssertEqual(page.people[1].name, "Alex Andersen")
        XCTAssertNil(page.people.first { $0.uwcId == "nc00bbb" }?.photoURL)
    }
}
