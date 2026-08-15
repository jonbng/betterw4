import XCTest
@testable import BetterLectio

final class MessageSignatureTests: XCTestCase {
    func testAppendsSignatureForStudentRecipients() {
        let result = MessageSignature.appendIfNeeded(
            to: "Hej",
            recipientIDs: ["S123"],
            enabled: true
        )

        XCTAssertEqual(result, "Hej" + MessageSignature.bbcode)
    }

    func testDoesNotAppendWhenDisabled() {
        XCTAssertEqual(
            MessageSignature.appendIfNeeded(to: "Hej", recipientIDs: ["S123"], enabled: false),
            "Hej"
        )
    }

    func testDoesNotAppendForTeacherOrMixedRecipients() {
        XCTAssertEqual(
            MessageSignature.appendIfNeeded(to: "Hej", recipientIDs: ["S123", "  T456"], enabled: true),
            "Hej"
        )
    }

    func testDoesNotDuplicateExistingSignatureCaseInsensitively() {
        let body = "Hej\n\nsEnDt MeD bEtTeRlEcTiO"

        XCTAssertEqual(
            MessageSignature.appendIfNeeded(to: body, recipientIDs: ["S123"], enabled: true),
            body
        )
    }

    func testAppendsWhenRecipientListIsEmpty() {
        XCTAssertEqual(
            MessageSignature.appendIfNeeded(to: "Hej", recipientIDs: [], enabled: true),
            "Hej" + MessageSignature.bbcode
        )
    }

    func testReplyDoesNotAppendWhenParticipantIdentityIsUnavailable() {
        XCTAssertEqual(
            MessageSignature.appendToReplyIfNeeded(to: "Hej", participantIDs: [], enabled: true),
            "Hej"
        )
    }

    func testTeacherDetectionIsCaseInsensitive() {
        XCTAssertEqual(
            MessageSignature.appendIfNeeded(to: "Hej", recipientIDs: [" t456"], enabled: true),
            "Hej"
        )
    }

    func testThreadParserCollectsRecipientAndSenderContextIDs() throws {
        let html = """
        <div id="s_m_Content_Content_MessageThreadCtrl_RecipientsReadMode">
          <span data-lectiocontextcard="S123">Elev</span>
        </div>
        <table id="s_m_Content_Content_MessageThreadCtrl_MessagesGV">
          <tr>
            <td>
              <div class="message-thread-message-sender">
                <span data-lectiocontextcard=" T456 ">Lærer</span>, 02-08-2026 10:00:00
              </div>
              <div class="message-thread-message-header">Emne</div>
              <div class="message-thread-message-content">Hej</div>
            </td>
          </tr>
        </table>
        """

        let detail = try MessageParser.parseMessageThreadDetail(from: html, threadId: "42")

        XCTAssertEqual(detail.recipientIDs, ["S123", "T456"])
    }

    func testLegacyCachedThreadDecodesWithoutRecipientIDs() throws {
        let json = #"{"threadId":"42","title":"Emne","recipients":"Elev","messages":[],"canReply":true}"#

        let detail = try JSONDecoder().decode(MessageThreadDetail.self, from: Data(json.utf8))

        XCTAssertEqual(detail.recipientIDs, [])
    }
}
