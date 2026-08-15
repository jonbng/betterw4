import XCTest
@testable import BetterLectio

final class MessageEditAuditTests: XCTestCase {
    func testExtractsTerminalAuditAsCopenhagenTime() throws {
        let html = """
        <p>Hej <strong>verden</strong></p>
        <div>Redigeret af Jonathan Arthur Hojer Bangert(k) (2x 17), d. 3/8-2026 09:54</div>
        """
        let result = MessageEditAudit.extract(from: html)

        XCTAssertEqual(result.html, "<p>Hej <strong>verden</strong></p>")
        let editedAt = try XCTUnwrap(result.editedAt)
        XCTAssertEqual(editedAt.timeIntervalSince1970, 1_785_743_640, accuracy: 0.5)
    }

    func testKeepsMalformedAndNonTerminalAuditText() {
        let invalid = "<p>Hej</p><div>Redigeret af Elev, d. 31/2-2026 09:54</div>"
        XCTAssertEqual(MessageEditAudit.extract(from: invalid).html, invalid)
        XCTAssertNil(MessageEditAudit.extract(from: invalid).editedAt)

        let followed = "<p>Hej</p><div>Redigeret af Elev, d. 3/8-2026 09:54</div><p>Eftertekst</p>"
        XCTAssertEqual(MessageEditAudit.extract(from: followed).html, followed)
        XCTAssertNil(MessageEditAudit.extract(from: followed).editedAt)
    }

    func testRelativeAndAbsoluteBoundary() throws {
        let editedAt = Date(timeIntervalSince1970: 1_785_743_640)
        XCTAssertEqual(
            MessageEditedTimeFormatter.label(
                for: editedAt,
                now: editedAt.addingTimeInterval(30),
                locale: Locale(identifier: "da_DK")
            ),
            .justNow
        )
        XCTAssertEqual(
            MessageEditedTimeFormatter.label(
                for: editedAt,
                now: editedAt.addingTimeInterval(5 * 60 + 30),
                locale: Locale(identifier: "da_DK")
            ),
            .value("for 5 minutter siden")
        )

        guard case .value(let absolute) = MessageEditedTimeFormatter.label(
            for: editedAt,
            now: editedAt.addingTimeInterval(7 * 24 * 60 * 60),
            locale: Locale(identifier: "en_US")
        ) else { return XCTFail("Expected absolute value") }
        XCTAssertFalse(absolute.contains("ago"))
    }
}
