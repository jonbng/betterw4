import XCTest
@testable import BetterLectio

final class MessageAttachmentUploadTests: XCTestCase {
    private func fixture(_ name: String, extension fileExtension: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: fileExtension)
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesSerializedIDFromJSON() {
        let data = Data(#"{"serializedId":"abc-123"}"#.utf8)
        XCTAssertEqual(LectioHTTPClient.parseUploadedDocumentID(from: data), "abc-123")
    }

    func testParsesSerializedIDFromTextResponse() {
        let data = Data(#"window.result = { serializedId: "doc-456" };"#.utf8)
        XCTAssertEqual(LectioHTTPClient.parseUploadedDocumentID(from: data), "doc-456")
    }

    func testFindsDynamicAttachmentPostbackFields() throws {
        let html = #"<input name="s$m$Content$MessagesGV$ctl18$AttachmentDocChooser$selectedDocumentId" value="">"#
        let fields = try XCTUnwrap(LectioHTTPClient.findAttachmentPostbackFields(in: html))
        XCTAssertEqual(fields.documentID, "s$m$Content$MessagesGV$ctl18$AttachmentDocChooser$selectedDocumentId")
        XCTAssertEqual(fields.target, "s$m$Content$MessagesGV$ctl18$AttachmentDocChooser")
    }

    func testMissingAttachmentChooserDoesNotInventAField() {
        XCTAssertNil(LectioHTTPClient.findAttachmentPostbackFields(in: "<html></html>"))
    }

    func testComposeFixtureResolvesLiveFormControls() throws {
        let html = try fixture("message-compose-open", extension: "html")
        let attachment = try XCTUnwrap(LectioHTTPClient.findAttachmentPostbackFields(in: html))
        XCTAssertTrue(attachment.target.hasSuffix("AttachmentDocChooser"))
        XCTAssertNotNil(MessageParser.parseMessageReplyFieldNames(from: html))
    }

    func testRecipientPostbackFixtureConfirmsRecipient() throws {
        let html = try fixture("message-recipient-postback", extension: "html")
        XCTAssertEqual(LectioHTTPClient.parseComposeRecipientNames(from: html), ["Test Elev"])
    }

    func testReplyFixtureResolvesDynamicRowControls() throws {
        let html = try fixture("message-reply-open", extension: "html")
        let fields = try XCTUnwrap(MessageParser.parseMessageReplyFieldNames(from: html))
        XCTAssertTrue(fields.sendButton.contains("ctl06"))
        XCTAssertEqual(LectioHTTPClient.messageCount(inThreadHTML: html), 1)
    }

    func testUnderscoreIDFallbackResolvesAttachmentTarget() throws {
        let html = #"<input id="s_m_Content_Content_MessageThreadCtrl_MessagesGV_ctl08_AttachmentDocChooser_selectedDocumentId">"#
        let fields = try XCTUnwrap(LectioHTTPClient.findAttachmentPostbackFields(in: html))
        XCTAssertEqual(fields.target, "s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl08$AttachmentDocChooser")
    }

    func testAttachmentPostbackMustContainExpectedFile() throws {
        let html = try fixture("message-attachment-postback", extension: "html")
        XCTAssertEqual(LectioHTTPClient.parseAttachedFileNames(from: html), ["Rapport øvelse.pdf"])
        XCTAssertTrue(LectioHTTPClient.attachmentPostbackSucceeded(
            html: html,
            expectedFileName: "Rapport øvelse.pdf"
        ))
        XCTAssertFalse(LectioHTTPClient.attachmentPostbackSucceeded(
            html: html,
            expectedFileName: "En anden fil.pdf"
        ))
    }

    func testRejectedAttachmentPostbackIsNotAccepted() throws {
        let html = try fixture("message-attachment-rejected", extension: "html")
        XCTAssertFalse(LectioHTTPClient.attachmentPostbackSucceeded(
            html: html,
            expectedFileName: "Rapport.pdf"
        ))
    }

    func testCapturedUploadResponse() throws {
        let response = try fixture("message-upload-response", extension: "json")
        XCTAssertEqual(
            LectioHTTPClient.parseUploadedDocumentID(from: Data(response.utf8)),
            "sanitized-upload-id"
        )
    }

    func testMultipartBodyPreservesFilenameAndContents() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let payload = Data("sanitized file contents".utf8)
        try payload.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let attachment = OutgoingMessageAttachment(
            displayName: "Rapport øvelse.pdf",
            mimeType: "application/pdf",
            size: Int64(payload.count),
            localURL: source
        )

        let multipart = try LectioHTTPClient.makeMultipartBodyFile(
            for: attachment,
            boundary: "TestBoundary"
        )
        defer { try? FileManager.default.removeItem(at: multipart) }
        let data = try Data(contentsOf: multipart)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("filename=\"Rapport øvelse.pdf\""))
        XCTAssertTrue(text.contains("Content-Type: application/pdf"))
        XCTAssertTrue(text.contains("sanitized file contents"))
        XCTAssertTrue(text.hasSuffix("--TestBoundary--\r\n"))
    }

    func testFinalSendFixtureIsAThreadPage() throws {
        let html = try fixture("message-final-send", extension: "html")
        XCTAssertFalse(LectioHTTPClient.messagePostbackHasValidationError(html))
        XCTAssertEqual(LectioHTTPClient.extractThreadId(from: nil, html: html), "123456")
        XCTAssertEqual(LectioHTTPClient.messageCount(inThreadHTML: html), 1)
    }

    func testCountsOnlySentMessagesAndIgnoresReplyEditor() {
        let html = """
        <table id="MessagesGV">
          <tr><td><div class="message-thread-message-content">Første</div></td></tr>
          <tr><td><div class="message-thread-message-content">Anden</div></td></tr>
          <tr><td><textarea>Et svar under redigering</textarea></td></tr>
        </table>
        """

        XCTAssertEqual(LectioHTTPClient.messageCount(inThreadHTML: html), 2)
    }

    func testMissingMessageTableHasNoConfirmedMessages() {
        XCTAssertEqual(LectioHTTPClient.messageCount(inThreadHTML: "<html></html>"), 0)
    }

    func testTemporaryPhotoIsSanitizedAndRemoved() throws {
        let attachment = try OutgoingMessageAttachment.createFromPhotoData(
            Data([0x01, 0x02]),
            fileName: "../foto\n.jpg",
            type: nil
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.localURL.path))
        XCTAssertFalse(attachment.localURL.lastPathComponent.contains("\n"))
        XCTAssertFalse(attachment.localURL.lastPathComponent.contains("/"))

        attachment.removeTemporaryFile()

        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.localURL.path))
    }
}
