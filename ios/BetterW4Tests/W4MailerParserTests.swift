//
//  W4MailerParserTests.swift
//  BetterW4Tests
//
//  Covers `W4MailerParser` (the inbox/archive Yii grid) and `W4MailDetailParser`
//  (`mailer/view&id=N`).
//
//  ── FIXTURE PROVENANCE — READ THIS BEFORE ADDING AN ASSERTION ──────────────────────────────
//
//  NOT ONE BYTE OF W4's MAILER HAS EVER BEEN CAPTURED.
//
//  `docs/spec/parsers.md` §7 and §18 (capture wishlist item 3), `docs/spec/reviewer-notes.md`
//  §7 and plan OQ-4 all say the same thing: the only real captures this project owns are the
//  Home page, three side-menu pages and the Documents page. `mailer/inbox`, `mailer/archive`
//  and `mailer/view` are none of those.
//
//  Therefore every fixture this file loads —
//      mailer-inbox.html · mailer-archive.html · mailer-empty.html · mailer-view.html
//  — is **[I] SYNTHESIZED**: hand-written from the Yii 1 `CGridView` convention
//  (`parsers.md` §0.4), README §6's column prose, and the page chrome that *is* verified. Each
//  file repeats that warning in its own header comment, and marks the individual pieces that
//  are pure invention ([U]): the `unread` class, the attachment link shape, the pager parameter
//  name, and the entire structure of the detail page.
//
//  So: **every assertion below verifies BetterW4's parsers. None of them verifies W4.** A green
//  suite here means "the parser does what it was designed to do with the markup we guessed",
//  never "we know what W4 sends". When a real capture lands, these fixtures get replaced and
//  these assertions are expected to change.
//
//  The one thing these tests can prove independently of the markup is *behaviour under change*:
//  that a missing column yields nil instead of shifting its neighbours (item 4.3's "Done"
//  criterion), that ids come from `[?&]id=` and never from a subject hash (bug B18), that all
//  four empty-state shapes are recognised (bug B9), and that pagination is surfaced rather than
//  silently truncated (bug B10). Those hold whatever the real column labels turn out to be.
//

import XCTest
@testable import BetterW4

final class W4MailerParserTests: XCTestCase {

    // MARK: - Helpers

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func osloDateTime(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) throws -> Date {
        try XCTUnwrap(W4Dates.date(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    /// Wraps grid markup in the minimum chrome the parser looks for.
    /// **[I]** Synthesized. Verifies the parser, not W4.
    private static func page(_ inner: String) -> String {
        """
        <html><body><div id="content_frame"><div id="content_main">
        <div id="content_inner">\(inner)</div>
        </div></div></body></html>
        """
    }

    /// A three-column inbox grid around the supplied `<tbody>` contents.
    /// **[I]** Synthesized. Verifies the parser, not W4.
    private static func inboxGrid(bodyRows: String) -> String {
        page("""
        <div class="grid-view"><table class="items">
        <thead><tr><th>Received</th><th>From</th><th>Subject</th></tr></thead>
        <tbody>\(bodyRows)</tbody>
        </table></div>
        """)
    }

    // MARK: - Inbox fixture — [I] synthesized markup

    func testInboxFixtureParsesBothRowsInDocumentOrder() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-inbox"), folder: .inbox)

        XCTAssertEqual(page.outcome, .parsed)
        XCTAssertEqual(page.messages.count, 2)
        XCTAssertEqual(page.messages.map(\.id), ["12", "7"], "DOM order is preserved")
        XCTAssertEqual(
            page.messages.map(\.subject),
            ["Welcome to term 1", "Kitchen booking"]
        )
        XCTAssertEqual(page.messages.map(\.from), ["House Leader", "W4 Mailer"])
        XCTAssertEqual(page.messages.map(\.folderID), ["inbox", "inbox"])
    }

    func testInboxTimestampsAreOsloWallClock() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-inbox"), folder: .inbox)

        XCTAssertEqual(page.messages.first?.receivedAt, try osloDateTime(2026, 8, 14, 12, 4))
        XCTAssertEqual(page.messages.last?.receivedAt, try osloDateTime(2026, 8, 13, 9, 0))
    }

    /// D-11: a device in another timezone must still read the Oslo wall clock.
    func testInboxTimestampsIgnoreTheDeviceTimeZone() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-inbox"), folder: .inbox)
        let received = try XCTUnwrap(page.messages.first?.receivedAt)

        var oslo = Calendar(identifier: .gregorian)
        oslo.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let parts = oslo.dateComponents([.year, .month, .day, .hour, .minute], from: received)

        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.day, 14)
        XCTAssertEqual(parts.hour, 12)
        XCTAssertEqual(parts.minute, 4)
    }

    /// Columns come from the header row's *text*, never from a position. The trailing
    /// button column has an empty label and must claim no role at all.
    func testInboxColumnsAreMatchedByHeaderText() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-inbox"), folder: .inbox)

        XCTAssertEqual(page.columns.headers, ["received", "from", "subject", ""])
        XCTAssertEqual(page.columns.received, 0)
        XCTAssertEqual(page.columns.from, 1)
        XCTAssertEqual(page.columns.subject, 2)
        XCTAssertNil(page.columns.attachment, "an empty header label claims no role")
    }

    func testInboxHrefIsKeptVerbatimForRefetching() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-inbox"), folder: .inbox)

        XCTAssertEqual(page.messages.first?.href, "/index.php?r=mailer/view&id=12")
    }

    /// **[U]** No unread marker and no attachment marker have ever been captured. The fixture's
    /// `tr.unread` is invented; this pins the parser's contract, not W4's markup.
    func testInboxUnreadAndAttachmentFlagsFollowTheMarkup() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-inbox"), folder: .inbox)

        XCTAssertEqual(page.messages.map(\.isUnread), [true, false])
        XCTAssertEqual(
            page.messages.map(\.hasAttachment),
            [false, false],
            "no attachment column and no attachment-looking link in either row"
        )
    }

    /// Bug B10: a pager must be surfaced, never silently ignored — page 1 is not the mailbox.
    func testInboxPaginationIsDetected() throws {
        let html = try fixture("mailer-inbox")
        let page = W4MailerParser.parseList(html, folder: .inbox)
        let pagination = try XCTUnwrap(page.pagination)

        XCTAssertTrue(pagination.hasMorePages)
        XCTAssertTrue(page.hasMorePages)
        XCTAssertEqual(pagination.currentPage, 1)
        XCTAssertEqual(pagination.pageCount, 3)
        XCTAssertEqual(pagination.summary, "Displaying 1-2 of 5 results.")
        XCTAssertEqual(
            pagination.nextPageHref?.contains("Mailer_page=2"),
            true,
            "the next-page link is captured verbatim"
        )
    }

    func testParsePaginationAgreesWithParseList() throws {
        let html = try fixture("mailer-inbox")

        XCTAssertEqual(
            W4MailerParser.parsePagination(html),
            W4MailerParser.parseList(html, folder: .inbox).pagination
        )
    }

    // MARK: - Archive fixture — item 4.3's "Done" criterion, [I] synthesized markup

    /// The archive grid has **no From column at all**. `from` must be nil, and the subject must
    /// still be found by matching the header text — not by landing on index 2 and getting lucky.
    func testArchiveWithoutFromColumnYieldsNilSenderAndStillMatchesSubject() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-archive"), folder: .archive)

        XCTAssertEqual(page.outcome, .parsed)
        XCTAssertEqual(page.columns.headers, ["send date", "subject", "attachment"])
        XCTAssertNil(page.columns.from, "there is no sender column to match")
        XCTAssertFalse(page.columns.hasSenderColumn)
        XCTAssertEqual(page.columns.received, 0)
        XCTAssertEqual(
            page.columns.subject,
            1,
            "the subject sits at index 1 here — a positional parser tuned to the inbox would "
            + "have read the attachment column instead"
        )
        XCTAssertEqual(page.columns.attachment, 2)

        XCTAssertEqual(page.messages.count, 2)
        XCTAssertEqual(page.messages.map(\.from), [nil, nil])
        XCTAssertEqual(
            page.messages.map(\.subject),
            ["Kayak trip permission", "Room change request"]
        )
        XCTAssertEqual(page.messages.map(\.id), ["55", "41"])
        XCTAssertEqual(page.messages.first?.receivedAt, try osloDateTime(2026, 8, 12, 16, 20))
        XCTAssertEqual(page.messages.map(\.folderID), ["archive", "archive"])
    }

    /// **[U]** The attachment column's contents are invented; what is being verified is that the
    /// header-matched column drives the flag rather than a guess at the row.
    func testArchiveAttachmentColumnDrivesTheAttachmentFlag() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-archive"), folder: .archive)

        XCTAssertEqual(page.messages.map(\.hasAttachment), [true, false])
    }

    /// A summary that accounts for every result, with no pager, means there is nothing more.
    func testArchiveSummaryWithoutPagerReportsNoMorePages() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-archive"), folder: .archive)
        let pagination = try XCTUnwrap(page.pagination)

        XCTAssertFalse(pagination.hasMorePages)
        XCTAssertEqual(pagination.summary, "Displaying 1-2 of 2 results.")
        XCTAssertNil(pagination.nextPageHref)
        XCTAssertNil(pagination.currentPage)
    }

    // MARK: - Empty states (bug B9)

    func testEmptyFixtureIsAnEmptyStateNotAParseFailure() throws {
        let page = W4MailerParser.parseList(try fixture("mailer-empty"), folder: .inbox)

        XCTAssertTrue(page.messages.isEmpty)
        XCTAssertTrue(page.isEmpty)
        XCTAssertEqual(
            page.outcome,
            .emptyState,
            "an empty inbox is a normal state — never report it as unreadable markup"
        )
        XCTAssertEqual(page.columns.headers, ["received", "from", "subject", ""],
                       "the header row is still read even with no data rows")
    }

    /// Bug B9: the Kotlin port only checks `td.empty`. All four shapes must count.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testAllFourEmptyMarkersAreRecognised() {
        let tdEmpty = Self.inboxGrid(bodyRows: #"<tr><td colspan="3" class="empty"></td></tr>"#)
        let spanEmpty = Self.inboxGrid(
            bodyRows: #"<tr><td colspan="3"><span class="empty">Nothing here</span></td></tr>"#
        )
        let noResultsText = Self.inboxGrid(
            bodyRows: #"<tr><td colspan="3">No results found.</td></tr>"#
        )
        // The non-grid half of B9: `#content_inner > div.note`, the one [V] empty pattern
        // (references/pages/Current applicants at UWCRCN.html renders "No users found").
        let note = Self.page(#"<div class="note">No users found</div>"#)

        for (label, html) in [
            ("td.empty", tdEmpty),
            ("span.empty", spanEmpty),
            ("No results found.", noResultsText),
            ("div.note", note)
        ] {
            let page = W4MailerParser.parseList(html, folder: .inbox)
            XCTAssertTrue(page.messages.isEmpty, "\(label) produced rows")
            XCTAssertEqual(page.outcome, .emptyState, "\(label) was not read as an empty state")
        }
    }

    /// "We could not read this" must never be dressed up as "you have no mail".
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testUnreadableMarkupIsUnrecognisedNotEmpty() {
        let blankRows = Self.inboxGrid(
            bodyRows: "<tr class=\"odd\"><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>"
        )
        let noGrid = Self.page("<p>Something else entirely</p>")

        XCTAssertEqual(W4MailerParser.parseList(blankRows, folder: .inbox).outcome, .unrecognised)
        XCTAssertEqual(W4MailerParser.parseList(noGrid, folder: .inbox).outcome, .unrecognised)
    }

    // MARK: - Message identity (bug B18)

    /// Two rows with the *same* subject must not become the same message. The id is the `id=`
    /// in the row's link — never `tr[id]` (Yii emits none) and never `subject.hashCode()`.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testIdentityComesFromTheHrefNeverFromTheSubject() {
        let html = Self.inboxGrid(bodyRows: """
            <tr><td>14-Aug-2026 12:04</td><td>House Leader</td>
              <td><a href="/index.php?r=mailer/view&amp;id=12">Duplicate subject</a></td></tr>
            <tr><td>14-Aug-2026 12:05</td><td>House Leader</td>
              <td><a href="/index.php?r=mailer/view&amp;id=13">Duplicate subject</a></td></tr>
            """)

        let page = W4MailerParser.parseList(html, folder: .inbox)

        XCTAssertEqual(page.messages.map(\.subject), ["Duplicate subject", "Duplicate subject"])
        XCTAssertEqual(page.messages.map(\.id), ["12", "13"])
        XCTAssertEqual(Set(page.messages.map(\.id)).count, 2, "identical subjects, distinct ids")
    }

    /// `folder_id`, `uwc_id` and `page_id` all end in `id=`. None of them is a message id.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testForeignQueryKeysCannotMasqueradeAsAMessageID() {
        let html = Self.inboxGrid(bodyRows: """
            <tr><td>14-Aug-2026 12:04</td><td>House Leader</td>
              <td><a href="/index.php?r=documents/index&amp;folder_id=27">Handbook</a></td></tr>
            <tr><td>13-Aug-2026 09:00</td><td>W4 Mailer</td>
              <td><a href="/index.php?r=people/students/student&amp;uwc_id=nc26abcd&amp;page_id=3">Profile</a></td></tr>
            """)

        let page = W4MailerParser.parseList(html, folder: .inbox)

        XCTAssertEqual(page.messages.count, 2)
        for message in page.messages {
            XCTAssertTrue(
                message.id.hasPrefix("w4mail-"),
                "a row with no id= link gets a visibly substituted id, got \(message.id)"
            )
        }
        XCTAssertNotEqual(page.messages.first?.id, "27")
        XCTAssertNotEqual(page.messages.last?.id, "3")
    }

    /// The substituted id is a content hash of (folder, subject, date) — stable across parses,
    /// and different for two rows that differ only by date. `subject.hashCode()` is neither.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testSubstitutedIDIsStableAndDateSensitive() {
        let html = Self.inboxGrid(bodyRows: """
            <tr><td>14-Aug-2026 12:04</td><td>House Leader</td>
              <td><a href="/index.php?r=documents/index&amp;folder_id=27">Same subject</a></td></tr>
            <tr><td>15-Aug-2026 12:04</td><td>House Leader</td>
              <td><a href="/index.php?r=documents/index&amp;folder_id=27">Same subject</a></td></tr>
            """)

        let first = W4MailerParser.parseList(html, folder: .inbox)
        let second = W4MailerParser.parseList(html, folder: .inbox)

        XCTAssertEqual(first.messages.map(\.id), second.messages.map(\.id), "stable across parses")
        XCTAssertNotEqual(
            first.messages.first?.id,
            first.messages.last?.id,
            "same subject, different date ⇒ different message"
        )
    }

    // MARK: - Header-driven column matching

    /// Shuffle the columns and the values must follow the headers, not the indices.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testShuffledHeaderOrderStillMapsEveryColumn() {
        let html = Self.page("""
            <div class="grid-view"><table class="items">
            <thead><tr><th>Subject</th><th>From</th><th>Received</th></tr></thead>
            <tbody><tr>
              <td><a href="/index.php?r=mailer/view&amp;id=3">Trip briefing</a></td>
              <td>Ms. Andersen</td>
              <td>10-Aug-2026 07:30</td>
            </tr></tbody>
            </table></div>
            """)

        let page = W4MailerParser.parseList(html, folder: .inbox)
        let message = page.messages.first

        XCTAssertEqual(page.columns.subject, 0)
        XCTAssertEqual(page.columns.from, 1)
        XCTAssertEqual(page.columns.received, 2)
        XCTAssertEqual(message?.subject, "Trip briefing")
        XCTAssertEqual(message?.from, "Ms. Andersen")
        XCTAssertEqual(message?.id, "3")
    }

    /// A grid with no `thead`: the first row carrying `th` cells is the header row.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testHeaderRowIsFoundWithoutATheadElement() {
        let html = Self.page("""
            <div class="grid-view"><table class="items">
            <tr><th>Received</th><th>From</th><th>Subject</th></tr>
            <tr><td>10-Aug-2026 07:30</td><td>Ms. Andersen</td>
              <td><a href="/index.php?r=mailer/view&amp;id=4">Trip briefing</a></td></tr>
            </table></div>
            """)

        let page = W4MailerParser.parseList(html, folder: .inbox)

        XCTAssertEqual(page.columns.headers, ["received", "from", "subject"])
        XCTAssertEqual(page.messages.map(\.id), ["4"])
        XCTAssertEqual(page.messages.first?.from, "Ms. Andersen")
    }

    /// `&amp;` in a subject is an entity, not four characters.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testSubjectEntitiesAreDecoded() {
        let html = Self.inboxGrid(bodyRows: """
            <tr><td>10-Aug-2026 07:30</td><td>House Leader</td>
              <td><a href="/index.php?r=mailer/view&amp;id=9">Health &amp; Safety</a></td></tr>
            """)

        XCTAssertEqual(
            W4MailerParser.parseList(html, folder: .inbox).messages.first?.subject,
            "Health & Safety"
        )
    }

    /// A summary with no pager still tells us there is more mail than this page.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testSummaryAloneCanImplyMorePages() {
        let more = Self.page(#"<div class="summary">Displaying 1-20 of 37 results.</div>"#)
        let complete = Self.page(#"<div class="summary">Displaying 1-3 of 3 results.</div>"#)

        XCTAssertEqual(W4MailerParser.parsePagination(more)?.hasMorePages, true)
        XCTAssertEqual(W4MailerParser.parsePagination(complete)?.hasMorePages, false)
        XCTAssertNil(
            W4MailerParser.parsePagination(Self.page("<p>no pager, no summary</p>")),
            "no pager and no summary means we know nothing about paging"
        )
    }

    // MARK: - Malformed input

    func testEmptyAndGarbageInputDoNotThrow() {
        let empty = W4MailerParser.parseList("", folder: .inbox)
        XCTAssertTrue(empty.messages.isEmpty)
        XCTAssertEqual(empty.outcome, .unrecognised)

        let garbage = W4MailerParser.parseList("<html><body><p>nope</p></body></html>",
                                               folder: .archive)
        XCTAssertTrue(garbage.messages.isEmpty)
        XCTAssertEqual(garbage.outcome, .unrecognised)
        XCTAssertNil(garbage.pagination)
    }

    // MARK: - Detail parser — mailer/view, [I] synthesized markup throughout

    func testMailViewFixtureParsesTheHeaderFields() throws {
        let detail = W4MailDetailParser.parse(try fixture("mailer-view"), id: "12")

        XCTAssertEqual(detail.id, "12")
        XCTAssertEqual(detail.subject, "Welcome to term 1")
        XCTAssertEqual(detail.from, "House Leader")
        XCTAssertEqual(detail.recipients, ["Alex Andersen", "Second Year Students"])
        XCTAssertEqual(detail.sentAt, try osloDateTime(2026, 8, 14, 12, 4))
    }

    /// The body is handed on RAW, and — on this fixture — scoped to the message wrapper, so the
    /// header table and the attachment list are not repeated inside it.
    func testMailViewBodyIsRawHTMLScopedToTheMessageBody() throws {
        let detail = W4MailDetailParser.parse(try fixture("mailer-view"), id: "12")

        XCTAssertTrue(detail.bodyHTML.contains("<strong>"), "markup is preserved, not flattened")
        XCTAssertTrue(detail.bodyHTML.contains("<ul>"))
        XCTAssertTrue(detail.bodyHTML.contains("page_id=3"), "links survive verbatim")
        XCTAssertFalse(detail.bodyHTML.contains("<table"), "the header table is not body content")
        XCTAssertFalse(detail.bodyHTML.contains("14-Aug-2026"))
        XCTAssertFalse(detail.bodyHTML.contains("attachment_id"))
    }

    func testMailViewAttachmentsAreCollectedWithTheirOwnIDs() throws {
        let detail = W4MailDetailParser.parse(try fixture("mailer-view"), id: "12")

        XCTAssertEqual(detail.attachments.count, 2, "the in-body Documents link is not a file")
        XCTAssertEqual(detail.attachments.map(\.id), ["91", "92"])
        XCTAssertEqual(
            detail.attachments.map(\.name),
            ["term-1-schedule.pdf", "packing-list.docx"]
        )
        XCTAssertEqual(
            detail.attachments.first?.url,
            "/index.php?r=mailer/download&attachment_id=91",
            "the href is kept exactly as captured, entities decoded"
        )
    }

    /// Reuse, not a second renderer: the raw body goes through the shared `HTMLContentRenderer`.
    func testMailViewBodyRendersThroughTheSharedRenderer() throws {
        let detail = W4MailDetailParser.parse(try fixture("mailer-view"), id: "12")
        let blocks = W4MailDetailParser.blocks(of: detail)

        XCTAssertFalse(blocks.isEmpty)
        let text = HTMLContentRenderer.plainText(blocks)
        XCTAssertTrue(text.contains("Welcome back to Flekke"))
        XCTAssertTrue(text.contains("House meeting on Monday"))
    }

    /// The id the request was made with is authoritative. The parser never re-derives it from
    /// the page — that is the same class of mistake as bug B18.
    func testDetailNeverRederivesTheMessageIDFromThePage() throws {
        let detail = W4MailDetailParser.parse(try fixture("mailer-view"), id: "999")

        XCTAssertEqual(detail.id, "999")
    }

    /// Last rung of the ladder, and the behaviour `parsers.md` §7 prescribes for v1: with no
    /// recognisable body wrapper, hand back the whole content container.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testDetailFallsBackToTheWholeContentContainer() {
        let html = Self.page("<h2>No wrapper here</h2><p>Body text.</p>")
        let detail = W4MailDetailParser.parse(html, id: "5")

        XCTAssertEqual(detail.subject, "No wrapper here")
        XCTAssertTrue(detail.bodyHTML.contains("<h2>"))
        XCTAssertTrue(detail.bodyHTML.contains("Body text."))
        XCTAssertNil(detail.from)
        XCTAssertTrue(detail.recipients.isEmpty)
        XCTAssertNil(detail.sentAt)
    }

    /// Header lines as prose rather than a table. The innermost element wins, so the wrapper
    /// `div` that contains all three lines cannot swallow the "From" value.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testDetailReadsProseHeaderLines() throws {
        let html = Self.page("""
            <h1>Kayak trip permission</h1>
            <div class="header">
              <div><strong>From:</strong> House Leader</div>
              <div><strong>To:</strong> Alex Andersen; Outdoor Department</div>
              <div><strong>Received:</strong> 14-Aug-2026 12:04</div>
            </div>
            <div class="message-body"><p>Approved.</p></div>
            """)

        let detail = W4MailDetailParser.parse(html, id: "55")

        XCTAssertEqual(detail.subject, "Kayak trip permission")
        XCTAssertEqual(detail.from, "House Leader")
        XCTAssertEqual(detail.recipients, ["Alex Andersen", "Outdoor Department"])
        XCTAssertEqual(detail.sentAt, try osloDateTime(2026, 8, 14, 12, 4))
        XCTAssertTrue(detail.bodyHTML.contains("Approved."))
        XCTAssertFalse(detail.bodyHTML.contains("House Leader"), "headers are outside the body")
    }

    /// A body line that merely contains a colon is body text, not metadata.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testDetailDoesNotMistakeBodyProseForHeaders() {
        let html = Self.page("""
            <h2>Kitchen booking</h2>
            <div class="message-body">
              <p>Note: bring your own cutlery.</p>
              <p>Meeting at 19:00 sharp.</p>
            </div>
            """)

        let detail = W4MailDetailParser.parse(html, id: "7")

        XCTAssertNil(detail.from)
        XCTAssertNil(detail.sentAt, "\"19:00\" is a time in a sentence, not a Received header")
        XCTAssertTrue(detail.recipients.isEmpty)
        XCTAssertEqual(detail.subject, "Kitchen booking")
    }

    /// Script and style never reach the renderer or a web view.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testDetailStripsScriptAndStyleFromTheBody() {
        let html = Self.page("""
            <div class="message-body">
              <p>Hello.</p>
              <script>alert('nope');</script>
              <style>p { color: red; }</style>
            </div>
            """)

        let detail = W4MailDetailParser.parse(html, id: "8")

        XCTAssertTrue(detail.bodyHTML.contains("Hello."))
        XCTAssertFalse(detail.bodyHTML.contains("alert"))
        XCTAssertFalse(detail.bodyHTML.contains("<style"))
    }

    /// An attachment must never inherit the message's own id: two files sharing one id collapse
    /// into a single row (bug B18's failure mode, one level down).
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testAttachmentIDsNeverCollideWithTheMessageID() {
        let html = Self.page("""
            <div class="message-body"><p>See attached.</p></div>
            <div class="attachments">
              <a href="/index.php?r=mailer/download&amp;id=12">first.pdf</a>
              <a href="/index.php?r=mailer/download&amp;id=12&amp;seq=2">second.pdf</a>
            </div>
            """)

        let detail = W4MailDetailParser.parse(html, id: "12")

        XCTAssertEqual(detail.attachments.count, 2)
        XCTAssertEqual(Set(detail.attachments.map(\.id)).count, 2, "ids are distinct")
        XCTAssertFalse(detail.attachments.contains { $0.id == "12" }, "never the message id")
    }

    /// A file link with no anchor text still gets a usable name.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testAttachmentNameFallsBackToTheFileNameInTheURL() {
        let html = Self.page("""
            <div class="attachments">
              <a href="/files/handbook.pdf"><img src="/images/pdf.png" alt=""></a>
            </div>
            """)

        let detail = W4MailDetailParser.parse(html, id: "12")

        XCTAssertEqual(detail.attachments.count, 1)
        XCTAssertEqual(detail.attachments.first?.name, "handbook.pdf")
        XCTAssertEqual(detail.attachments.first?.url, "/files/handbook.pdf")
    }

    /// The same file linked twice is one attachment.
    /// **[I]** Synthesized markup — verifies the parser, not W4.
    func testDuplicateAttachmentLinksAreCollapsed() {
        let html = Self.page("""
            <div class="attachments">
              <a href="/index.php?r=mailer/download&amp;attachment_id=91">term-1-schedule.pdf</a>
              <a href="/index.php?r=mailer/download&amp;attachment_id=91">term-1-schedule.pdf</a>
            </div>
            """)

        XCTAssertEqual(W4MailDetailParser.parse(html, id: "12").attachments.count, 1)
    }

    func testDetailDegradesToAnEmptyMessageWithoutThrowing() {
        let empty = W4MailDetailParser.parse("", id: "12")

        XCTAssertEqual(empty.id, "12")
        XCTAssertEqual(empty.subject, "")
        XCTAssertTrue(empty.bodyHTML.isEmpty)
        XCTAssertNil(empty.from)
        XCTAssertTrue(empty.recipients.isEmpty)
        XCTAssertNil(empty.sentAt)
        XCTAssertTrue(empty.attachments.isEmpty)

        let garbage = W4MailDetailParser.parse("<<< not html >>>", id: "")
        XCTAssertEqual(garbage.id, "")
        XCTAssertTrue(garbage.attachments.isEmpty)
    }
}
