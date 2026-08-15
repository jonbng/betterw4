import XCTest
@testable import BetterLectio

final class FeedbackLogBufferTests: XCTestCase {
    func testRedactsCredentialsHeadersCookiesTokensAndHomePath() {
        let input = """
        ASP.NET_SessionId=secret autologinkeyV2: another
        Authorization: Bearer abc.def refresh_token=refresh-secret
        Cookie: foo=bar; private=yes
        apikey=public-looking-but-sensitive token_hash=magic
        https://example.test/callback?code=one-time-code&safe=yes
        message=private message body
        student@example.com
        /home/alice/Documents/file.txt
        """

        let output = FeedbackLogBuffer.redact(input)

        XCTAssertFalse(output.contains("secret"))
        XCTAssertFalse(output.contains("abc.def"))
        XCTAssertFalse(output.contains("foo=bar"))
        XCTAssertFalse(output.contains("public-looking-but-sensitive"))
        XCTAssertFalse(output.contains("one-time-code"))
        XCTAssertFalse(output.contains("private message body"))
        XCTAssertFalse(output.contains("student@example.com"))
        XCTAssertFalse(output.contains("alice"))
        XCTAssertTrue(output.contains("[REDACTED]"))
        XCTAssertTrue(output.contains("/[USER]/"))
    }

    func testCapacityKeepsNewestLines() {
        let buffer = FeedbackLogBuffer(capacity: 2)
        buffer.record("first")
        buffer.record("second")
        buffer.record("third")

        let snapshot = buffer.snapshot()
        XCTAssertFalse(snapshot.contains("first"))
        XCTAssertTrue(snapshot.contains("second"))
        XCTAssertTrue(snapshot.contains("third"))
    }

    func testSnapshotIsBoundedAndKeepsNewestContent() {
        let buffer = FeedbackLogBuffer(capacity: 10)
        buffer.record(String(repeating: "old", count: 100))
        buffer.record("newest marker")

        let snapshot = buffer.snapshot(maxCharacters: 40)

        XCTAssertLessThanOrEqual(snapshot.count, 70) // includes the truncation notice
        XCTAssertTrue(snapshot.contains("newest marker"))
        XCTAssertTrue(snapshot.contains("ældre loglinjer udeladt"))
    }
}
