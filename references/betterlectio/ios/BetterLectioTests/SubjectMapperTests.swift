import XCTest
@testable import BetterLectio

final class SubjectMapperTests: XCTestCase {
    override func tearDown() {
        SubjectMapper.mappingProvider = nil
        SubjectMapper.subjectInfoProvider = nil
        super.tearDown()
    }

    func testCanonicalKeyGradeBasedPrefixes() {
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1x MA"), "ma")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "2.4 MA"), "ma")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "L2d MA"), "ma")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "IB1 En B"), "en")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "3hx-u DA"), "da")
    }

    func testCanonicalKeyNamedClassPrefixes() {
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "BShannon DA"), "da")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "BShannon PU"), "pu")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "BHamilton MA"), "ma")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Epsilon DA"), "da")
    }
}
