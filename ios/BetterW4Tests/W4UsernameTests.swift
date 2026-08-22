import XCTest
@testable import BetterW4

final class W4UsernameTests: XCTestCase {

    func testLeavesBareUsernameAlone() {
        XCTAssertEqual(W4Username.normalize("nc26jban"), "nc26jban")
        XCTAssertEqual(W4Username.normalize("  nc26jban \n"), "nc26jban")
    }

    func testStripsSchoolEmailDomain() {
        XCTAssertEqual(W4Username.normalize("nc26jban@uwcrcn.no"), "nc26jban")
        XCTAssertEqual(W4Username.normalize("  NC26JBAN@UWCRCN.NO  "), "NC26JBAN")
        XCTAssertEqual(W4Username.normalize("nc26jban@uwcrcn.no "), "nc26jban")
    }

    func testStripsAnyEmailDomain() {
        XCTAssertEqual(W4Username.normalize("nc26jban@gmail.com"), "nc26jban")
    }

    func testEmptyLocalPartIsEmpty() {
        XCTAssertEqual(W4Username.normalize("@uwcrcn.no"), "")
        XCTAssertEqual(W4Username.normalize("   "), "")
    }
}
