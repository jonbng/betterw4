//
//  W4TeacherParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance: myteachers.html is [I] SYNTHESIZED from the live
//  people/students/staff capture of 21 Aug 2026. Identities are invented.
//  Assertions prove the parser against that markup, not against a live session.
//

import XCTest
@testable import BetterW4

final class W4TeacherParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testListsTeachersInDocumentOrder() throws {
        let teachers = W4TeacherParser.parse(try fixture("myteachers"))
        XCTAssertEqual(
            teachers.map(\.id),
            ["nc00aore", "nc00ccc", "nc00lbro", "wk00lbon", "nc00fff", "nc00mons", "nc00pszy"]
        )
        XCTAssertEqual(
            teachers.map(\.name),
            [
                "Avery Ortega",
                "Chris Chen",
                "Lila Brown",
                "Yara Young",
                "Frankie Fossum",
                "Zane Zhao",
                "Priya Shah"
            ]
        )
    }

    func testReadsRoleCaptionAndTrailingLevel() throws {
        let teachers = W4TeacherParser.parse(try fixture("myteachers"))

        let core = try XCTUnwrap(teachers.first { $0.id == "nc00aore" })
        XCTAssertEqual(core.role, "Core meetings")
        XCTAssertEqual(core.level, .unknown)

        let advisor = try XCTUnwrap(teachers.first { $0.id == "nc00ccc" })
        XCTAssertEqual(advisor.role, "Advisor group")
        XCTAssertEqual(advisor.level, .unknown)

        let english = try XCTUnwrap(teachers.first { $0.id == "nc00lbro" })
        XCTAssertEqual(english.role, "English Language & Literature")
        XCTAssertEqual(english.level, .standard)
        XCTAssertEqual(english.displayLevel, "SL")

        let math = try XCTUnwrap(teachers.first { $0.id == "nc00pszy" })
        XCTAssertEqual(math.role, "Mathematics Analysis and Approaches")
        XCTAssertEqual(math.level, .higher)
        XCTAssertEqual(math.displayLevel, "HL")
    }

    func testKeepsNonNcStaffIds() throws {
        let teachers = W4TeacherParser.parse(try fixture("myteachers"))
        let danish = try XCTUnwrap(teachers.first { $0.id == "wk00lbon" })
        XCTAssertEqual(danish.name, "Yara Young")
        XCTAssertEqual(danish.role, "Danish Literature")
        XCTAssertEqual(
            danish.photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/wk00lbon_photo.jpg"
        )
    }

    func testUpgradesThumbToFullPortrait() throws {
        let teachers = W4TeacherParser.parse(try fixture("myteachers"))
        let chris = try XCTUnwrap(teachers.first { $0.id == "nc00ccc" })
        XCTAssertEqual(
            chris.photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00ccc_photo.jpg"
        )
    }

    func testPlaceholderPhotoIsNil() {
        let html = """
            <div id="content_inner">
              <ul class="user-list">
                <li>
                  <a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc">
                    <img class="photo" src="/images/user.png" alt="Photo of nc00ccc" />
                  </a>
                  <a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc">Chris Chen</a>
                  <br />Advisor group
                </li>
              </ul>
            </div>
            """
        let teachers = W4TeacherParser.parse(html)
        XCTAssertEqual(teachers.count, 1)
        XCTAssertNil(teachers.first?.photoURL)
        XCTAssertEqual(teachers.first?.role, "Advisor group")
    }

    func testStaffIdReadsUwcIdWithoutNcShape() {
        XCTAssertEqual(
            W4TeacherParser.staffId(fromHref: "/index.php?r=people/staff/staff&uwc_id=WK00LBON"),
            "wk00lbon"
        )
        XCTAssertEqual(
            W4TeacherParser.staffId(
                fromHref: "https://w4.uwcrcn.no/index.php?r=people%2Fstaff%2Fstaff&uwc_id=nc00ccc"
            ),
            "nc00ccc"
        )
        XCTAssertNil(W4TeacherParser.staffId(fromHref: "/index.php?r=site/index"))
    }

    func testParseRoleSplitsTrailingLevel() {
        let math = W4TeacherParser.parseRole("Mathematics Analysis and Approaches HL")
        XCTAssertEqual(math.role, "Mathematics Analysis and Approaches")
        XCTAssertEqual(math.level, .higher)

        let english = W4TeacherParser.parseRole("English Language & Literature SL")
        XCTAssertEqual(english.role, "English Language & Literature")
        XCTAssertEqual(english.level, .standard)

        let core = W4TeacherParser.parseRole("Core meetings")
        XCTAssertEqual(core.role, "Core meetings")
        XCTAssertEqual(core.level, .unknown)

        XCTAssertNil(W4TeacherParser.parseRole("").role)
        XCTAssertNil(W4TeacherParser.parseRole(nil).role)
    }

    func testEmptyAndGarbageDoNotThrow() {
        XCTAssertTrue(W4TeacherParser.parse("").isEmpty)
        XCTAssertTrue(W4TeacherParser.parse("<html></html>").isEmpty)
        XCTAssertTrue(W4TeacherParser.parse("not html at all").isEmpty)
        let empty = """
            <div id="content_inner">
              <h2>My Teachers and Group Leaders</h2>
              <div class="note">No users found</div>
            </div>
            """
        XCTAssertTrue(W4TeacherParser.parse(empty).isEmpty)
    }

    func testEachPersonAppearsOnceDespiteTwoAnchors() throws {
        let teachers = W4TeacherParser.parse(try fixture("myteachers"))
        XCTAssertEqual(Set(teachers.map(\.id)).count, teachers.count)
    }
}
