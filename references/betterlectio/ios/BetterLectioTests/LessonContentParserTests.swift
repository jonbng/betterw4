import XCTest
import SwiftSoup
@testable import BetterLectio

final class LessonContentParserTests: XCTestCase {

    // MARK: - Backward-compat decoding

    func testDecodesOldJSONWithBodyFieldAsEmptyBlocks() throws {
        let json = """
        {
          "id": "ACH123",
          "title": "Old title",
          "note": null,
          "body": "Some legacy text",
          "links": [],
          "isHomework": true
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(LessonContentItem.self, from: json)
        XCTAssertEqual(item.id, "ACH123")
        XCTAssertEqual(item.title, "Old title")
        XCTAssertEqual(item.blocks, [])
    }

    func testDecodesNewJSONWithBlocksField() throws {
        let json = """
        {
          "id": "ACH456",
          "title": null,
          "note": null,
          "blocks": [],
          "links": [],
          "isHomework": false
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(LessonContentItem.self, from: json)
        XCTAssertEqual(item.id, "ACH456")
        XCTAssertEqual(item.blocks, [])
    }

    // MARK: - parseInlines

    func testParseInlines_plainText() throws {
        let html = "<h1>Hello world</h1>"
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("h1").first())
        let result = try ScheduleParser.parseInlines(el)
        XCTAssertEqual(result, [.text("Hello world")])
    }

    func testParseInlines_linkOnly() throws {
        let html = #"<p><a href="/lectio/94/res/file.docx" data-lc-display-linktype="file">file.docx</a></p>"#
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("p").first())
        let result = try ScheduleParser.parseInlines(el)
        XCTAssertEqual(result, [.link(text: "file.docx", url: "/lectio/94/res/file.docx", type: .file)])
    }

    func testParseInlines_textAndLink() throws {
        let html = #"<h1>Read this: <a href="/lectio/94/res/file.docx" data-lc-display-linktype="file">file.docx</a></h1>"#
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("h1").first())
        let result = try ScheduleParser.parseInlines(el)
        XCTAssertEqual(result, [
            .text("Read this: "),
            .link(text: "file.docx", url: "/lectio/94/res/file.docx", type: .file)
        ])
    }

    func testParseInlines_externalLink() throws {
        let html = #"<h3><a href="https://youtube.com/watch?v=abc" data-lc-display-linktype="external">Watch video</a></h3>"#
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("h3").first())
        let result = try ScheduleParser.parseInlines(el)
        XCTAssertEqual(result, [.link(text: "Watch video", url: "https://youtube.com/watch?v=abc", type: .external)])
    }

    func testParseInlines_skipsLectioIconImages() throws {
        let html = #"<h1>Text <img src="https://www.lectio.dk/lectio/img/file16x16.auto"> more</h1>"#
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("h1").first())
        let result = try ScheduleParser.parseInlines(el)
        let texts = result.compactMap { if case .text(let s) = $0 { return s } else { return nil } }
        XCTAssertFalse(texts.isEmpty)
        XCTAssertFalse(result.contains(where: { if case .image = $0 { return true } else { return false } }))
    }

    func testParseInlines_contentImageIncluded() throws {
        let html = #"<p><img alt="Poster" src="/lectio/94/lc/123/res/456/image.jpeg"></p>"#
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("p").first())
        let result = try ScheduleParser.parseInlines(el)
        XCTAssertEqual(result, [.image(url: "/lectio/94/lc/123/res/456/image.jpeg", alt: "Poster")])
    }

    func testParseInlines_skipsNbspOnlyNodes() throws {
        let html = "<p>\u{00A0}</p>"
        let doc = try SwiftSoup.parse(html)
        let el = try XCTUnwrap(doc.select("p").first())
        let result = try ScheduleParser.parseInlines(el)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - parseTooltip "Hele dagen"

    func testParseTooltip_heleDagenOnDateLine_marksAsAllDay() {
        let tooltip = """
        15/5-2026 Hele dagen
        Hold: 1x Fy
        Lærer: Anders And
        """
        let result = ScheduleParser.parseTooltip(tooltip)
        XCTAssertTrue(result.isAllDay, "Tooltip with 'Hele dagen' on the date line should be marked as all-day")
    }

    func testParseTooltip_heleDagenOnSeparateLine_marksAsAllDay() {
        let tooltip = """
        Skolens fødselsdag
        Hele dagen
        Hold: Alle 1. G. elever
        """
        let result = ScheduleParser.parseTooltip(tooltip)
        XCTAssertTrue(result.isAllDay)
    }

    func testParseTooltip_normalLessonIsNotAllDay() {
        let tooltip = """
        2/2-2026 09:00 til 09:50
        Hold: 1x Fy
        Lærer: Anders And
        Lokale: K12
        """
        let result = ScheduleParser.parseTooltip(tooltip)
        XCTAssertFalse(result.isAllDay)
        XCTAssertEqual(result.timeInfo, "2/2-2026 09:00 til 09:50")
    }

    // MARK: - parseSchedule (s2infoHeader all-day row)

    func testParseSchedule_missingScheduleTableThrows() {
        XCTAssertThrowsError(try ScheduleParser.parseSchedule(from: "<html><body>Login page</body></html>")) { error in
            guard case LectioError.parsingError(let message) = error else {
                return XCTFail("Expected parsingError, got \(error)")
            }
            XCTAssertEqual(message, "Schedule table not found")
        }
    }

    /// Minimal schedule table with one timed event Monday and two all-day chips
    /// on Tuesday in the s2infoHeader row.
    private let sampleScheduleHTML = """
    <table class="s2skema">
      <tbody>
        <tr class="s2dayHeader">
          <td></td>
          <td>Mandag (4/5)</td>
          <td>Tirsdag (5/5)</td>
        </tr>
        <tr>
          <td class="s2infoHeader"></td>
          <td class="s2infoHeader s2skemabrikcontainer"><div></div></td>
          <td class="s2infoHeader s2skemabrikcontainer">
            <div>
              <a class="s2skemabrik s2normal" data-tooltip="Røper P. fodbold kl. 15.30
    5/5-2026 Hele dagen"><div><div class="s2skemabrikcontent"><span>Røper P. fodbold kl. 15.30</span></div></div></a>
              <a class="s2skemabrik s2normal" data-tooltip="PR-møde
    5/5-2026 Hele dagen"><div><div class="s2skemabrikcontent"><span>PR-møde</span></div></div></a>
            </div>
          </td>
        </tr>
        <tr>
          <td></td>
          <td data-date="2026-05-04">
            <a href="/lectio/94/aktivitet.aspx?absid=1" class="s2skemabrik s2bgbox s2normal s2brik" data-brikid="ABS1" data-tooltip="4/5-2026 08:10 til 09:50
    Hold: 1x Fy
    Lærer: Anders And
    Lokale: K12"><div><div class="s2skemabrikcontent">x</div></div></a>
          </td>
          <td data-date="2026-05-05"></td>
        </tr>
      </tbody>
    </table>
    """

    func testParseSchedule_extractsAllDayEventsFromInfoHeader() throws {
        let events = try ScheduleParser.parseSchedule(from: sampleScheduleHTML)

        let allDay = events.filter { $0.isAllDay }
        XCTAssertEqual(allDay.count, 2, "Should extract two Hele dagen events from the info header row")

        let titles = Set(allDay.map { $0.title })
        XCTAssertTrue(titles.contains("Røper P. fodbold kl. 15.30"))
        XCTAssertTrue(titles.contains("PR-møde"))

        for event in allDay {
            XCTAssertTrue(event.startTime.isEmpty)
            XCTAssertTrue(event.endTime.isEmpty)
            XCTAssertEqual(event.subtitle, "Hele dagen")
            XCTAssertFalse(event.id.isEmpty, "All-day event must have a stable id")
        }

        // All-day events on Tuesday must be dated to Tuesday (matched via column index).
        let calendar = Calendar.current
        var comps = DateComponents(); comps.year = 2026; comps.month = 5; comps.day = 5
        let expectedDate = calendar.date(from: comps)!
        for event in allDay {
            XCTAssertTrue(calendar.isDate(event.date, inSameDayAs: expectedDate))
        }

        // Timed event still parsed normally.
        let timed = events.filter { !$0.isAllDay }
        XCTAssertEqual(timed.count, 1)
        XCTAssertEqual(timed.first?.startTime, "08:10")
    }

    func testParseSchedule_skipsDuplicateTimedEventsInInfoHeader() throws {
        // Mirrors the real Lectio HTML where a timed evening event also has a
        // chip in the info row — that chip's tooltip lacks "Hele dagen", so we
        // should skip it (the timed grid handles it).
        let html = """
        <table class="s2skema">
          <tbody>
            <tr class="s2dayHeader"><td></td><td>Tirsdag (5/5)</td></tr>
            <tr>
              <td class="s2infoHeader"></td>
              <td class="s2infoHeader s2skemabrikcontainer">
                <a class="s2skemabrik s2normal" data-tooltip="Eksamensorientering
        5/5-2026 Hele dagen"></a>
                <a href="/lectio/94/aktivitet.aspx?absid=42" class="s2skemabrik s2normal s2brik" data-brikid="ABS42" data-tooltip="Krea-aften
        5/5-2026 18:30 til 21:00
        Hold: Alle 1. STX-elever"></a>
              </td>
            </tr>
            <tr>
              <td></td>
              <td data-date="2026-05-05">
                <a href="/lectio/94/aktivitet.aspx?absid=42" class="s2skemabrik s2bgbox s2normal s2brik" data-brikid="ABS42" data-tooltip="Krea-aften
        5/5-2026 18:30 til 21:00
        Hold: Alle 1. STX-elever"></a>
              </td>
            </tr>
          </tbody>
        </table>
        """

        let events = try ScheduleParser.parseSchedule(from: html)

        // Should produce exactly: 1 all-day Eksamensorientering + 1 timed Krea-aften (no duplicate).
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.filter { $0.isAllDay }.count, 1)
        XCTAssertEqual(events.filter { !$0.isAllDay }.count, 1)
        XCTAssertEqual(events.filter { !$0.isAllDay }.first?.startTime, "18:30")
    }

    // MARK: - parseLessonContent blocks

    private let sampleArticleHTML = """
    <div id="homeworkContentContainer">
      <div id="s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv">
        <div>
          <h1 class="ls-paper-section-heading">Lektier</h1>
        </div>
        <div id="ACH001">
          <article class="lc-display-fragment">
            <h1 id="h1" style="background-image: url(/lectio/img/doc-homework.auto)">
              I timen: Skriveøvelse\u{00A0}<a href="/lectio/94/res/file.docx" data-lc-display-linktype="file">:Österreich.docx</a>
            </h1>
            <p>
              <a href="/lectio/94/res/other.docx" data-lc-display-linktype="file">other.docx</a>
            </p>
            <h1 id="h2">Quiz: <a href="https://quiz.example.com" data-lc-display-linktype="external">quiz</a></h1>
            <h3><a href="https://youtube.com/watch?v=abc" data-lc-display-linktype="external">Watch video</a></h3>
            <p><img alt="Poster" src="/lectio/94/lc/123/res/456/image.jpeg"></p>
            <hr>
            <p>Plain text paragraph.</p>
          </article>
        </div>
      </div>
    </div>
    """

    func testParseLessonContent_blockCount() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        XCTAssertEqual(content.items.count, 1)
        let item = content.items[0]
        // Expected blocks: paragraph(other.docx), heading(h2 quiz), heading(h3 youtube),
        //                  image(poster), divider, paragraph(plain text)
        XCTAssertEqual(item.blocks.count, 6)
    }

    func testParseLessonContent_titleExtracted() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        let item = content.items[0]
        XCTAssertTrue(item.title?.contains("I timen") == true)
    }

    func testParseLessonContent_firstBlockIsParagraphWithLink() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        let item = content.items[0]
        guard case .paragraph(let inlines) = item.blocks[0] else {
            return XCTFail("Expected paragraph, got \(item.blocks[0])")
        }
        XCTAssertTrue(inlines.contains(where: {
            if case .link(_, let url, _) = $0 { return url.contains("other.docx") } else { return false }
        }))
    }

    func testParseLessonContent_h3BlockIsHeadingLevel3() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        let item = content.items[0]
        guard case .heading(let level, let inlines) = item.blocks[2] else {
            return XCTFail("Expected heading, got \(item.blocks[2])")
        }
        XCTAssertEqual(level, 3)
        XCTAssertTrue(inlines.contains(where: {
            if case .link(_, let url, _) = $0 { return url.contains("youtube") } else { return false }
        }))
    }

    func testParseLessonContent_imageBlock() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        let item = content.items[0]
        guard case .image(let url, _) = item.blocks[3] else {
            return XCTFail("Expected image, got \(item.blocks[3])")
        }
        XCTAssertTrue(url.contains("image.jpeg"))
    }

    func testParseLessonContent_dividerBlock() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        let item = content.items[0]
        XCTAssertEqual(item.blocks[4], .divider)
    }

    func testParseLessonContent_plainTextParagraph() throws {
        let content = try ScheduleParser.parseLessonContent(from: sampleArticleHTML)
        let item = content.items[0]
        guard case .paragraph(let inlines) = item.blocks[5] else {
            return XCTFail("Expected paragraph, got \(item.blocks[5])")
        }
        XCTAssertTrue(inlines.contains(where: {
            if case .text(let s) = $0 { return s.contains("Plain text") } else { return false }
        }))
    }

    // MARK: - Teacher note without homework content

    private let teacherNoteOnlyHTML = """
    <div id="homeworkContentContainer" class="ls-paper">
      <div id="s_m_Content_Content_tocAndToolbar_actHeader">
        <div class="ls-std-rowblock-top-ltr ls-section-title-heading">
          <div><a class="s2skemabrik">Vækstkritik &amp; Doughnut-økonomi</a></div>
        </div>
        <span class="nowrap">
          <textarea name="ActNoteTB" class="activity-note">Vi skal bruge timen på at diskutere klimakrisen.</textarea>
        </span>
      </div>
      <div id="s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv">
        <p class="ls-hidden-smallscreen">Aktiviteten har ikke noget indhold.</p>
      </div>
    </div>
    """

    func testParseLessonContent_teacherNotePreservedWhenNoHomework() throws {
        let content = try ScheduleParser.parseLessonContent(from: teacherNoteOnlyHTML)
        XCTAssertEqual(content.items.count, 0)
        XCTAssertEqual(content.teacherNote, "Vi skal bruge timen på at diskutere klimakrisen.")
    }
}
