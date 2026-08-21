//
//  W4ClassParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance: myclasses.html, class-mtaa.html and class-ecox.html are
//  [I] SYNTHESIZED from the live class-list / class-details shape captured
//  19 Aug 2026. Identities are invented. Assertions prove the parser against
//  that markup, not against a live W4 session.
//

import XCTest
@testable import BetterW4

final class W4ClassParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testIndexListsClassesInDocumentOrder() throws {
        let classes = W4ClassParser.parseIndex(try fixture("myclasses"))
        XCTAssertEqual(
            classes.map(\.id),
            ["1ZAUDXCORE", "1EA16CECOX", "1YA25SLALI", "1DA13HMTAA"]
        )
        XCTAssertEqual(
            classes.map(\.subject),
            [
                "Core meetings",
                "Economics",
                "English Language & Literature",
                "Mathematics Analysis and Approaches"
            ]
        )
        XCTAssertTrue(classes.allSatisfy { !$0.loaded })
    }

    func testCaptionReadsTeacherFromWithClause() {
        let parsed = W4ClassParser.parseCaption(
            "1EA16CECOX: Economics 1st Year C level with Mona Eide Onstad in room A 1.6"
        )
        XCTAssertEqual(parsed?.subject, "Economics")
        XCTAssertEqual(parsed?.year, "1")
        XCTAssertEqual(parsed?.level, .combined)
        XCTAssertEqual(parsed?.teacher, "Mona Eide Onstad")
        XCTAssertEqual(parsed?.room, "A 1.6")
    }

    func testIndexReadsLevelTeacherAndRoomFromTheCaption() throws {
        let classes = W4ClassParser.parseIndex(try fixture("myclasses"))

        let math = try XCTUnwrap(classes.first { $0.id == "1DA13HMTAA" })
        XCTAssertEqual(math.level, .higher)
        XCTAssertEqual(math.displayLevel, "HL")
        XCTAssertEqual(math.year, "1")
        XCTAssertEqual(math.block, "D")
        XCTAssertEqual(math.subjectCode, "MTAA")
        XCTAssertEqual(math.teacherNames, "Jens Jensen")
        XCTAssertEqual(math.room?.name, "A 1.3")
        XCTAssertNil(math.room?.id)

        let english = try XCTUnwrap(classes.first { $0.id == "1YA25SLALI" })
        XCTAssertEqual(english.level, .standard)
        XCTAssertEqual(english.displayLevel, "SL")
        XCTAssertEqual(english.teacherNames, "Liusaidh Brown")

        let econ = try XCTUnwrap(classes.first { $0.id == "1EA16CECOX" })
        XCTAssertEqual(econ.level, .combined)
        XCTAssertEqual(econ.displayLevel, "HL/SL")

        let core = try XCTUnwrap(classes.first { $0.id == "1ZAUDXCORE" })
        XCTAssertEqual(core.level, .none)
        XCTAssertEqual(core.displayLevel, "")
        XCTAssertEqual(core.room?.name, "Auditorium")
    }

    func testClassPageReadsDetailsTeacherAndStudents() throws {
        let item = W4ClassParser.parseClass(try fixture("class-mtaa"))
        XCTAssertEqual(item.id, "1DA13HMTAA")
        XCTAssertEqual(item.subject, "Mathematics Analysis and Approaches")
        XCTAssertEqual(item.subjectCode, "MTAA")
        XCTAssertEqual(item.year, "1")
        XCTAssertEqual(item.block, "D")
        XCTAssertEqual(item.level, .higher)
        XCTAssertEqual(item.displayLevel, "HL")
        XCTAssertEqual(item.room?.id, "a13")
        XCTAssertEqual(item.room?.name, "A 1.3")
        XCTAssertTrue(item.loaded)

        let teacher = try XCTUnwrap(item.teachers.first)
        XCTAssertEqual(item.teachers.count, 1)
        XCTAssertEqual(teacher.id, "nc00jjen")
        XCTAssertEqual(teacher.name, "Jens Jensen")
        XCTAssertEqual(teacher.kind, .staff)
        XCTAssertTrue(teacher.photoURL?.absoluteString.contains("/files/user_photos/nc00jjen_photo.jpg") == true)

        XCTAssertEqual(item.students.map(\.id), ["nc00aaa", "nc00bbb", "nc00ccc"])
        XCTAssertEqual(item.students.first?.name, "Alex Andersen")
        XCTAssertEqual(item.students.first?.kind, .student)
        XCTAssertTrue(item.students.first?.photoURL?.absoluteString.contains("/files/user_photos/nc00aaa_photo.jpg") == true)
        XCTAssertNil(item.students.first { $0.id == "nc00bbb" }?.photoURL)
    }

    func testCombinedClassKeepsPerStudentHLSLOverlay() throws {
        let item = W4ClassParser.parseClass(try fixture("class-ecox"))
        XCTAssertEqual(item.level, .combined)
        XCTAssertEqual(item.levelLabel, "Combined")
        XCTAssertEqual(item.subject, "Economics")
        XCTAssertEqual(item.students.first { $0.id == "nc00ddd" }?.level, .higher)
        XCTAssertEqual(item.students.first { $0.id == "nc00eee" }?.level, .standard)
        XCTAssertEqual(item.students.first { $0.id == "nc00ddd" }?.person.subtitle, "HL")
    }

    func testMergePrefersListSubjectNameAndDetailRoster() throws {
        let listed = try XCTUnwrap(
            W4ClassParser.parseIndex(try fixture("myclasses")).first { $0.id == "1DA13HMTAA" }
        )
        let detail = W4ClassParser.parseClass(try fixture("class-mtaa"))
        let merged = W4ClassParser.merge(base: listed, detail: detail)
        XCTAssertEqual(merged.subject, "Mathematics Analysis and Approaches")
        XCTAssertEqual(merged.teachers.singleId, "nc00jjen")
        XCTAssertEqual(merged.students.count, 3)
        XCTAssertEqual(merged.room?.id, "a13")
        XCTAssertTrue(merged.loaded)
        XCTAssertFalse(listed.loaded)
    }

    func testClassIdAndRoomIdAreSiblingQueryKeys() {
        XCTAssertEqual(
            W4ClassParser.classIdFromHref("/index.php?r=academics/classes/class&class_id=1DA13HMTAA"),
            "1DA13HMTAA"
        )
        XCTAssertEqual(
            W4ClassParser.roomIdFromHref("/index.php?r=academics/timetable/room&room_id=a13"),
            "a13"
        )
    }

    func testLevelParseAcceptsHL_SLAndW4Letters() {
        XCTAssertEqual(ClassLevel.parse("H Higher"), .higher)
        XCTAssertEqual(ClassLevel.parse("SL"), .standard)
        XCTAssertEqual(ClassLevel.parse("C Combined"), .combined)
        XCTAssertEqual(ClassLevel.parse("HL/SL"), .combined)
        XCTAssertEqual(ClassLevel.parse("X None"), .none)
        XCTAssertEqual(ClassLevel.parse(""), .unknown)
    }
}

private extension Array where Element == ClassMember {
    var singleId: String? {
        count == 1 ? first?.id : nil
    }
}
