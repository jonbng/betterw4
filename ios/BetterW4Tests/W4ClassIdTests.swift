import XCTest
@testable import BetterW4

final class W4ClassIdTests: XCTestCase {

    func testParsesCapturedAcademicCodes() {
        let math = try! XCTUnwrap(W4ClassId.parse("1DA13HMTAA"))
        XCTAssertEqual(math.year, 1)
        XCTAssertEqual(math.block, "D")
        XCTAssertEqual(math.roomCode, "A13")
        XCTAssertEqual(math.level, "H")
        XCTAssertEqual(math.subjectCode, "MTAA")
        XCTAssertEqual(math.levelLabel, "HL")

        let econ = try! XCTUnwrap(W4ClassId.parse("1EA16CECOX"))
        XCTAssertEqual(econ.block, "E")
        XCTAssertEqual(econ.roomCode, "A16")
        XCTAssertEqual(econ.level, "C")
        XCTAssertEqual(econ.subjectCode, "ECOX")

        let core = try! XCTUnwrap(W4ClassId.parse("1ZAUDXCORE"))
        XCTAssertEqual(core.block, "Z")
        XCTAssertEqual(core.roomCode, "AUD")
        XCTAssertEqual(core.level, "X")
        XCTAssertEqual(core.subjectCode, "CORE")

        let theatre = try! XCTUnwrap(W4ClassId.parse("1CMUSCTHEX"))
        XCTAssertEqual(theatre.roomCode, "MUS")
        XCTAssertEqual(theatre.subjectCode, "THEX")

        let french = try! XCTUnwrap(W4ClassId.parse("2YK11SFRAB"))
        XCTAssertEqual(french.block, "Y")
        XCTAssertEqual(french.roomCode, "K11")
        XCTAssertEqual(french.subjectCode, "FRAB")
    }

    func testRejectsAdvisorFirstNamesAndFurniture() {
        XCTAssertNil(W4ClassId.parse("Dona"))
        XCTAssertNil(W4ClassId.parse("Breakfast"))
        XCTAssertNil(W4ClassId.parse("Economics"))
        XCTAssertNil(W4ClassId.parse(""))
    }
}
