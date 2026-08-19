import XCTest
@testable import BetterW4

final class W4OtpCodeTests: XCTestCase {

    func testExtractsLiveW4Codes() {
        let codes = [
            "5Z4IccMB",
            "abSHlAcY",
            "jYSaRbGT",
            "VYTkVHeR",
            "9LPKSSSX",
            "zGhIItWl",
            "w3RSqC6f",
            "KRxMTc9v",
        ]
        for code in codes {
            XCTAssertEqual(W4OtpCode.extract(code), code)
            XCTAssertEqual(W4OtpCode.extract("  \(code) \n"), code)
            XCTAssertEqual(W4OtpCode.extract("\"\(code)\""), code)
            XCTAssertEqual(W4OtpCode.extract("\(code)."), code)
        }
    }

    func testRejectsUsernamesAndOtherClipboardNoise() {
        XCTAssertNil(W4OtpCode.extract("nc26abcd"))
        XCTAssertNil(W4OtpCode.extract("NC26AbCd"))
        XCTAssertNil(W4OtpCode.extract("Nc00jjen"))
        XCTAssertNil(W4OtpCode.extract("nC99XXXX"))
        XCTAssertNil(W4OtpCode.extract("12345678"))
        XCTAssertNil(W4OtpCode.extract("5Z4IccM"))
        XCTAssertNil(W4OtpCode.extract("5Z4IccMBX"))
        XCTAssertNil(W4OtpCode.extract("Your code is 5Z4IccMB"))
        XCTAssertNil(W4OtpCode.extract(""))
        XCTAssertNil(W4OtpCode.extract(nil))
        XCTAssertNil(W4OtpCode.extract("password1"))
    }

    func testSanitizeStripsWhitespaceAndCapsLength() {
        XCTAssertEqual(W4OtpCode.sanitizeInput(" 5Z4IccMB\n"), "5Z4IccMB")
        XCTAssertEqual(W4OtpCode.sanitizeInput("5Z4IccMBXXXX"), "5Z4IccMB")
    }
}
