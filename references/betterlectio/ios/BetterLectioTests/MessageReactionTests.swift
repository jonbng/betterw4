import XCTest
@testable import BetterLectio

final class MessageReactionTests: XCTestCase {
    private let target = MessageLocator(
        senderKey: "id:U72721772844",
        sentAt: "2026-03-05T14:33:09",
        occurrence: 0
    )

    func testRoundTripsEveryEmojiAndUsesFragmentOnly() throws {
        for emoji in MessageReactionEmoji.allCases {
            let envelope = MessageReactionEnvelope.set(emoji: emoji, target: target)
            XCTAssertEqual(MessageReactionProtocol.decode(MessageReactionProtocol.encode(envelope)), envelope)
            let url = MessageReactionProtocol.carrierURL(for: envelope)
            XCTAssertTrue(url.hasPrefix("https://betterlectio.dk/download#blr1."))
            XCTAssertNil(URLComponents(string: url)?.query)
            XCTAssertEqual(MessageReactionProtocol.parseCarrierURL(url), envelope)
        }
    }

    func testClearContainsNoPreviousEmoji() {
        let envelope = MessageReactionEnvelope.clear(target: target)
        let body = MessageReactionProtocol.carrierBody(for: envelope, showSignature: false)
        XCTAssertTrue(body.contains("Fjernede sin reaktion"))
        XCTAssertFalse(body.contains("❤️"))
        XCTAssertEqual(MessageReactionProtocol.decode(MessageReactionProtocol.encode(envelope)), envelope)
    }

    func testResolverHidesLatestOwnedClearAndKeepsMalformedCarrier() {
        let original = rawMessage(
            id: "original",
            senderID: "U72721772844",
            sender: "Target Person",
            date: "05-03-2026 14:33:09",
            html: "<p>Original</p>"
        )
        let set = MessageReactionEnvelope.set(emoji: .heart, target: target)
        let clear = MessageReactionEnvelope.clear(target: target)
        let setCarrier = rawMessage(
            id: "set",
            senderID: "U-own",
            sender: "Own Person",
            date: "05-03-2026 14:34:00",
            html: carrierHTML(set),
            editTarget: "row-set"
        )
        let clearCarrier = rawMessage(
            id: "clear",
            senderID: "U-own",
            sender: "Own Person",
            date: "05-03-2026 14:35:00",
            html: carrierHTML(clear),
            editTarget: "row-clear"
        )
        let malformed = rawMessage(
            id: "malformed",
            senderID: "U-other",
            sender: "Other Person",
            date: "05-03-2026 14:36:00",
            html: carrierHTML(set).replacingOccurrences(of: "Reagerede med", with: "Påstod at reagere med")
        )

        let result = MessageReactionProtocol.resolve([original, setCarrier, clearCarrier, malformed])
        XCTAssertEqual(result.hiddenCarrierCount, 2)
        XCTAssertEqual(result.messages.map(\.id), ["original", "malformed"])
        XCTAssertEqual(result.messages.first?.reactions, [])
        XCTAssertNil(result.messages.first?.ownReaction)
        XCTAssertEqual(result.ownCarriersByTarget[target]?.editPostbackTarget, "row-clear")
    }

    func testLegacyCachedMessageDecodesWithReactionDefaults() throws {
        let json = #"{"id":"1","senderName":"Elev","date":"05-03-2026 14:33:09","title":"Hej","content":"Test","attachments":[]}"#
        let message = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        XCTAssertNil(message.locator)
        XCTAssertNil(message.editedAt)
        XCTAssertEqual(message.reactions, [])
        XCTAssertNil(message.ownReaction)
    }

    func testEditedCarrierIgnoresLectioAuditLine() {
        let envelope = MessageReactionEnvelope.set(emoji: .thumbsUp, target: target)
        let html = carrierHTML(envelope) +
            "<div>Redigeret af Jonathan Arthur Hojer Bangert(k) (2x 17), d. 3/8-2026 09:54</div>"
        XCTAssertEqual(MessageReactionProtocol.parseCarrierHTML(html), envelope)
        XCTAssertNil(MessageReactionProtocol.parseCarrierHTML(html + "<div>extra text</div>"))
    }

    func testParsesRowScopedEditFields() throws {
        let target = "s$m$Content$MessagesGV$ctl03$EditModeToggleBtn"
        let html = """
        <table><tr>
          <input name="s$m$Content$MessagesGV$ctl03$EditModeHeaderTitleTB$tb" value="Re: Hej">
          <textarea name="s$m$Content$MessagesGV$ctl03$EditModeContentBBTB$TbxNAME$tb"></textarea>
          <a onclick="__doPostBack('s$m$Content$MessagesGV$ctl03$SaveMessageBtn','')">Gem</a>
        </tr></table>
        """
        let fields = try XCTUnwrap(LectioHTTPClient.parseReactionEditFields(from: html, editTarget: target))
        XCTAssertEqual(fields.saveTarget, "s$m$Content$MessagesGV$ctl03$SaveMessageBtn")
        XCTAssertEqual(fields.title, "Re: Hej")
    }

    func testEditParserFindsSaveTargetThroughNestedRowAncestors() throws {
        let prefix = "s$m$Content$MessagesGV$ctl09"
        let target = prefix + "$EditModeToggleBtn"
        let html = """
        <table><tr>
          <td><div><textarea name="\(prefix)$EditModeContentBBTB$TbxNAME$tb"></textarea></div></td>
          <td><input name="\(prefix)$EditModeHeaderTitleTB$tb" value="Re: Nested"></td>
          <td><a onclick="__doPostBack('\(prefix)$SaveMessageBtn','')">Gem</a></td>
        </tr></table>
        """

        let fields = try XCTUnwrap(LectioHTTPClient.parseReactionEditFields(from: html, editTarget: target))
        XCTAssertEqual(fields.saveTarget, prefix + "$SaveMessageBtn")
        XCTAssertEqual(fields.title, "Re: Nested")
    }

    func testEditParserPreservesWhitespaceAndRejectsCancelAsSave() throws {
        let prefix = "s$m$Content$MessagesGV$ctl17"
        let target = prefix + "$EditModeToggleBtn"
        let html = """
        <table><tr>
          <input name="\(prefix)$EditModeHeaderTitleTB$tb" value="Ret &amp; gem">
          <textarea name="\(prefix)$EditModeContentBBTB$TbxNAME$tb">første linje
  anden linje</textarea>
          <a onclick="__doPostBack('\(prefix)$BackMessageBtn','')">Annuller</a>
          <a href="javascript:__doPostBack('\(prefix)$UpdateMessageBtn','')">Gem</a>
        </tr></table>
        """

        let fields = try XCTUnwrap(LectioHTTPClient.parseReactionEditFields(from: html, editTarget: target))
        XCTAssertEqual(fields.saveTarget, prefix + "$UpdateMessageBtn")
        XCTAssertEqual(fields.body, "første linje\n  anden linje")
    }

    func testEditSignatureIsPreservedByteForByte() {
        let signature = "\n\n[url=https://betterlectio.dk/download]Sendt med BetterLectio[/url]"
        let split = LectioHTTPClient.splitEditableSignature("Hej\nigen" + signature)
        XCTAssertEqual(split.body, "Hej\nigen")
        XCTAssertEqual(split.signature, signature)
    }

    func testMessageEditorRoundTripsSupportedBBCode() {
        let source = "[b]Fed[/b] [i]kursiv[/i] [u]streg[/u] [url=https://betterlectio.dk]Link[/url]"
        XCTAssertEqual(BBCodeCodec.encode(BBCodeCodec.decode(source)), source)

        let bareURL = "[url]https://betterlectio.dk/download[/url]"
        XCTAssertEqual(BBCodeCodec.encode(BBCodeCodec.decode(bareURL)), bareURL)
    }

    private func carrierHTML(_ envelope: MessageReactionEnvelope) -> String {
        let sentence: String
        switch envelope {
        case .set(let emoji, _): sentence = "Reagerede med “\(emoji.rawValue)”"
        case .clear: sentence = "Fjernede sin reaktion"
        }
        return "<p>\(sentence)</p><p><a href=\"\(MessageReactionProtocol.carrierURL(for: envelope))\">Sendt med BetterLectio</a></p>"
    }

    private func rawMessage(
        id: String,
        senderID: String,
        sender: String,
        date: String,
        html: String,
        editTarget: String = ""
    ) -> MessageReactionProtocol.RawMessage {
        MessageReactionProtocol.RawMessage(
            message: Message(
                id: id,
                senderName: sender,
                date: date,
                title: "",
                content: html,
                attachments: [],
                senderEntityID: senderID
            ),
            rawContentHTML: html,
            editPostbackTarget: editTarget
        )
    }
}
