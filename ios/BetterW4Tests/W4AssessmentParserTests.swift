//
//  W4AssessmentParserTests.swift
//  BetterW4Tests
//
//  Tests for `W4AssessmentParser` (item 4.2) and the parts of `AssessmentModels` the parser
//  produces.
//
//  ⚠️ EVIDENCE — READ THIS BEFORE ADDING AN ASSERTION ⚠️
//
//  **EVERY ASSERTION IN THIS FILE ABOUT MARKUP IS [I] (INFERRED). NOT ONE OF THEM VERIFIES W4.**
//  (The two exceptions assert names, not markup: the POST field names and the write feature gate.)
//
//  `index.php?r=academics/deadlines` has never been captured — docs/spec/parsers.md section 6,
//  bug B12, docs/spec/reviewer-notes.md section 7. Both fixtures used here
//  (`Fixtures/W4/assessments.html`, `Fixtures/W4/assessments-empty.html`) are hand-written, and
//  they were hand-written from the *invented* `data-assessment-*` attribute names in
//  `android/.../feature/homework/W4AssessmentParser.kt`, whose own fixture is also hand-written.
//  So these tests prove that `W4AssessmentParser` behaves as designed against the shape we
//  guessed. They prove nothing about the markup W4 actually serves.
//
//  The only names on this surface with independent corroboration are the four FORM fields
//  (`assessment_id`, `student_assessment_id`, `student_deadline_date`,
//  `student_assessment_title`) and the button labels, which README section 5.2 read off a live
//  page. `testStatusFieldsAreKeyedOnKind` is the test that guards them, and it is the most
//  valuable test in this file: posting the wrong id field makes "Confirm done" a silent no-op.
//
//  When capture C-3 lands (`GET academics/deadlines` in term time plus one Confirm-done round
//  trip), expect the fixtures AND most of these assertions to change.
//

import XCTest
@testable import BetterW4

final class W4AssessmentParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(W4Dates.date(year: year, month: month, day: day))
    }

    private func item(_ items: [Assessment], id: String) throws -> Assessment {
        try XCTUnwrap(items.first { $0.id == id }, "no item with id \(id) in \(items.map(\.id))")
    }

    // MARK: - The synthesized month fixture

    /// **[I]** Both hand-written entries parse, in document order, with kind-prefixed ids.
    func testSynthesizedMonthParsesBothItems() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments"))

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.id), ["class:42", "student:99"],
                       "id is kind-prefixed: the two id spaces are independent on W4")
        XCTAssertEqual(items.map(\.rawId), ["42", "99"], "rawId is what W4 itself posts back")
    }

    /// **[I]** A class-assigned entry carries the teacher/subject/unit trio.
    func testSynthesizedClassAssignedItemFields() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments"))
        let lab = try item(items, id: "class:42")

        XCTAssertEqual(lab.kind, .classAssigned)
        XCTAssertEqual(lab.rawKind, "class")
        XCTAssertEqual(lab.title, "Lab report", "anchor text wins over unit and subject")
        XCTAssertEqual(lab.subject, "Biology")
        XCTAssertEqual(lab.classCode, "BIO HL")
        XCTAssertEqual(lab.teacher, "Jane Doe")
        XCTAssertEqual(lab.unit, "Cell biology")
        XCTAssertEqual(lab.daysLeft, 4)
        XCTAssertEqual(lab.status, .pending)
        XCTAssertEqual(lab.rawStatus, "pending")
        XCTAssertFalse(lab.isDone)
        XCTAssertFalse(lab.isOverdue, "data-css-class=\"new\" is not overdue")
        XCTAssertTrue(lab.isEditable)
        XCTAssertNil(lab.href, "href=\"#\" is not a destination")
        XCTAssertEqual(lab.dueDate, try osloDate(2026, 8, 10))
    }

    /// **[I]** A student-created entry has no class metadata at all, and it is `.done`.
    func testSynthesizedStudentCreatedItemFields() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments"))
        let essay = try item(items, id: "student:99")

        XCTAssertEqual(essay.kind, .studentCreated)
        XCTAssertEqual(essay.rawKind, "student")
        XCTAssertEqual(essay.title, "My essay")
        XCTAssertNil(essay.subject)
        XCTAssertNil(essay.classCode)
        XCTAssertNil(essay.teacher)
        XCTAssertNil(essay.unit)
        XCTAssertNil(essay.daysLeft, "a missing data-days-left is absent, not zero")
        XCTAssertEqual(essay.status, .done)
        XCTAssertTrue(essay.isDone)
        XCTAssertEqual(essay.dueDate, try osloDate(2026, 8, 11))
    }

    /// **[I]** D-11 holds here too: a due date is Oslo midnight, never the device's midnight.
    func testDueDatesAreOsloRegardlessOfDeviceTimeZone() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments"))
        let due = try XCTUnwrap(try item(items, id: "class:42").dueDate)

        var osloCalendar = Calendar(identifier: .gregorian)
        osloCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let components = osloCalendar.dateComponents([.year, .month, .day, .hour], from: due)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 0)
    }

    // MARK: - The empty month

    /// **[I]** An empty month is a completely normal state on this page: `[]`, no throw.
    func testEmptyMonthReturnsNoItemsAndDoesNotThrow() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments-empty"))
        XCTAssertTrue(items.isEmpty)
    }

    /// **[I]** W4 renders the write endpoints whether or not the month has items, so an empty
    /// month must still yield URLs — otherwise "add assessment" would disappear in a quiet month.
    func testEmptyMonthStillPublishesActionURLs() throws {
        let urls = try XCTUnwrap(try W4AssessmentParser.parseAjaxURLs(try fixture("assessments-empty")))

        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.create.contains("month=07"), "the endpoints carry the rendered month")
        XCTAssertTrue(urls.create.contains("year=2026"))
    }

    // MARK: - AJAX endpoints

    /// **[I]** The five endpoints are recovered verbatim, never rebuilt: they carry
    /// `&month=&year=&uwc_id=` and W4 regenerates them per render.
    func testActionURLsAreRecoveredFromTheInlineScript() throws {
        let urls = try XCTUnwrap(try W4AssessmentParser.parseAjaxURLs(try fixture("assessments")))

        XCTAssertEqual(urls.confirm,
                       "/index.php?r=academics/deadlines/confirm&month=08&year=2026&uwc_id=nc26abcd")
        XCTAssertEqual(urls.revert,
                       "/index.php?r=academics/deadlines/revert&month=08&year=2026&uwc_id=nc26abcd")
        XCTAssertEqual(urls.save,
                       "/index.php?r=academics/deadlines/edit&month=08&year=2026&uwc_id=nc26abcd")
        XCTAssertEqual(urls.create,
                       "/index.php?r=academics/deadlines/create&month=08&year=2026&uwc_id=nc26abcd")
        XCTAssertEqual(urls.delete,
                       "/index.php?r=academics/deadlines/delete&month=08&year=2026&uwc_id=nc26abcd")

        XCTAssertEqual(urls.url(for: .confirmDone), urls.confirm)
        XCTAssertEqual(urls.url(for: .revertToPending), urls.revert)
        XCTAssertEqual(urls.deleteURL, urls.delete)
    }

    /// **[I]** A page that publishes no endpoints returns `nil` — the signal to keep every write
    /// affordance hidden rather than POSTing to `""`.
    func testPageWithoutAjaxBlockYieldsNoActionURLs() throws {
        XCTAssertNil(try W4AssessmentParser.parseAjaxURLs("<html><body><p>nothing</p></body></html>"))
        XCTAssertNil(try W4AssessmentParser.parseAjaxURLs(""))
    }

    /// **[I]** Yii's `CJavaScript::encode` escapes `/` as `\x2F` — the campus-status endpoint in
    /// `references/pages/UWCRCN W4.html` is published as `site\x2Fsetstatus` **[V]**, so the same
    /// escaping is very likely here. `&amp;` shows up because script bodies are not entity-decoded.
    /// This test verifies the DECODER, not W4's assessment markup.
    func testEscapedSlashesAndEntitiesInActionURLsAreDecoded() throws {
        // "\\x2F" in Swift source is the two characters `\x2F` in the HTML.
        let html = Self.calendarPage(
            script: """
            var ajax_urls = {
              confirm: 'index.php?r=academics\\x2Fdeadlines\\x2Fconfirm&amp;month=08',
              'delete': 'index.php?r=academics\\x2Fdeadlines\\x2Fdelete&amp;month=08'
            };
            """,
            cells: ""
        )

        let urls = try XCTUnwrap(try W4AssessmentParser.parseAjaxURLs(html))
        XCTAssertEqual(urls.confirm, "index.php?r=academics/deadlines/confirm&month=08")
        XCTAssertEqual(urls.delete, "index.php?r=academics/deadlines/delete&month=08",
                       "`delete` is a JS reserved word and may arrive quoted")
        XCTAssertNil(urls.saveURL, "an endpoint W4 did not publish stays absent")
    }

    // MARK: - Write payloads (the corroborated part of this surface)

    /// The one test on this page that guards something we did NOT invent: README section 5.2 read
    /// `assessment_id` and `student_assessment_id` off a live page. Sending the wrong key makes W4
    /// accept the request and change nothing — "Confirm done" would silently do nothing.
    func testStatusFieldsAreKeyedOnKind() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments"))
        let classAssigned = try item(items, id: "class:42")
        let studentCreated = try item(items, id: "student:99")

        XCTAssertEqual(W4AssessmentParser.statusFields(for: classAssigned), ["assessment_id": "42"])
        XCTAssertEqual(W4AssessmentParser.statusFields(for: studentCreated),
                       ["student_assessment_id": "99"])

        // Stated the other way round, because this is the failure mode that matters.
        XCTAssertNil(W4AssessmentParser.statusFields(for: classAssigned)["student_assessment_id"])
        XCTAssertNil(W4AssessmentParser.statusFields(for: studentCreated)["assessment_id"])

        XCTAssertEqual(AssessmentKind.classAssigned.identifierFieldName,
                       AssessmentFieldNames.classAssessmentID)
        XCTAssertEqual(AssessmentKind.studentCreated.identifierFieldName,
                       AssessmentFieldNames.studentAssessmentID)
    }

    /// The kind-keyed builder used by callers that do not hold a whole `Assessment`, plus its
    /// refusal to build a payload with no id (which would post an empty field to W4).
    func testStatusFieldsRefuseAnEmptyIdentifier() {
        XCTAssertEqual(W4AssessmentParser.statusFields(kind: .studentCreated, rawId: " 17 "),
                       ["student_assessment_id": "17"], "the id is trimmed before it is posted")
        XCTAssertTrue(W4AssessmentParser.statusFields(kind: .classAssigned, rawId: "   ").isEmpty)
        XCTAssertTrue(W4AssessmentParser.statusFields(kind: .studentCreated, rawId: "").isEmpty)
    }

    /// The transition offered to the student follows the server's status, and it targets the
    /// matching endpoint.
    func testOfferedTransitionFollowsStatus() throws {
        let items = try W4AssessmentParser.parse(try fixture("assessments"))
        let pending = try item(items, id: "class:42")
        let done = try item(items, id: "student:99")

        XCTAssertEqual(pending.offeredTransition, .confirmDone)
        XCTAssertEqual(done.offeredTransition, .revertToPending)
        XCTAssertEqual(AssessmentTransition.confirmDone.resultingStatus, .done)
        XCTAssertEqual(AssessmentTransition.revertToPending.resultingStatus, .pending)
    }

    /// OQ-3: no *Confirm done* request has ever been observed, so writes stay off until capture
    /// C-3 lands. If this test fails, someone flipped the flag — make sure the capture exists.
    func testAssessmentWritesAreStillGatedOff() {
        XCTAssertFalse(AssessmentFeatureFlags.writesEnabled,
                       "flip this only when capture C-3 has verified the write payload")
    }

    // MARK: - Status mapping

    /// **[I]** Deliberately inverted from the Android port, which reads `done = status != "pending"`
    /// and therefore marks an item done on any string it does not recognise. Showing a finished
    /// item as pending is an annoyance; hiding an unfinished one is a missed deadline.
    func testUnknownStatusStaysPending() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: """
                <a class="assessment-link" data-assessment-id="1" data-status="completed">A</a>
                <a class="assessment-link" data-assessment-id="2" data-status="brand-new-token">B</a>
                <a class="assessment-link" data-assessment-id="3" data-status="">C</a>
                """)
        ))

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].status, .done, "\"completed\" is on the allow-list")
        XCTAssertEqual(items[1].status, .pending, "an unrecognised token is NOT done")
        XCTAssertEqual(items[1].rawStatus, "brand-new-token", "the raw value survives for diffing")
        XCTAssertEqual(items[2].status, .pending)
    }

    /// **[I]** "Overdue" is styling, not a status — and it arrives two different ways.
    func testOverdueIsReadFromEitherTheCssClassAttributeOrTheAnchorClasses() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: """
                <a class="assessment-link" data-assessment-id="1" data-css-class="overdue">A</a>
                <a class="assessment-link overdue" data-assessment-id="2">B</a>
                <a class="assessment-link" data-assessment-id="3" data-css-class="new">C</a>
                """)
        ))

        XCTAssertEqual(items.map(\.isOverdue), [true, true, false])
        XCTAssertEqual(items.map(\.status), [.pending, .pending, .pending],
                       "overdue must never be smuggled in as a third status")
    }

    // MARK: - Titles and hrefs

    /// **[I]** Title falls back anchor text → unit → subject → a generic label, so a row is never
    /// rendered blank.
    func testTitleFallsBackThroughUnitAndSubject() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: """
                <a class="assessment-link" data-assessment-id="1" data-unit="Cell biology"
                   data-subject-name="Biology"></a>
                <a class="assessment-link" data-assessment-id="2" data-subject-name="Biology"></a>
                <a class="assessment-link" data-assessment-id="3"></a>
                """)
        ))

        XCTAssertEqual(items.map(\.title), ["Cell biology", "Biology", "Assessment"])
    }

    /// **[I]** A placeholder anchor is not a destination.
    func testHrefIsNormalized() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: """
                <a class="assessment-link" data-assessment-id="1" href="#">A</a>
                <a class="assessment-link" data-assessment-id="2" href="javascript:void(0)">B</a>
                <a class="assessment-link" data-assessment-id="3"
                   href="/index.php?r=academics/deadlines/view&amp;id=3">C</a>
                """)
        ))

        XCTAssertNil(items[0].href)
        XCTAssertNil(items[1].href)
        XCTAssertEqual(items[2].href, "/index.php?r=academics/deadlines/view&id=3",
                       "SwiftSoup decodes &amp; in an attribute value")
    }

    // MARK: - Date fallback (bug B11)

    /// **[I]** Bug B11: the Android regex `month=(\d+)` never matched `var month = 08 - 1;` and
    /// only worked by accident off the ajax URLs. An item with no `data-assessment-date` must
    /// still get a date, from its calendar cell plus the page's own month/year — and the literal
    /// in `08 - 1` is the 1-based month (the `- 1` only feeds JavaScript's 0-based `Date`).
    func testItemWithoutItsOwnDateFallsBackToTheCalendarCell() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1;\nvar year = 2026;",
            cells: Self.dayCell(day: 14, anchors: """
                <a class="assessment-link" data-assessment-id="7" data-status="pending">Essay</a>
                """)
        ))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].dueDate, try osloDate(2026, 8, 14),
                       "August, not September: `08 - 1` declares a 1-based month")
    }

    /// **[I]** The other half of B11: a page that declares its month only inside the ajax URLs
    /// still resolves the fallback date.
    func testMonthAndYearCanComeFromTheActionURLsAlone() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: """
            var ajax_urls = {
              confirm: '/index.php?r=academics/deadlines/confirm&month=09&year=2026&uwc_id=nc26abcd'
            };
            """,
            cells: Self.dayCell(day: 3, anchors: """
                <a class="assessment-link" data-assessment-id="8">Presentation</a>
                """)
        ))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.dueDate, try osloDate(2026, 9, 3))
    }

    /// **[I]** No cell day and no item date means no date — the parser must not guess "today".
    func testItemWithNeitherOwnDateNorDayCellHasNoDueDate() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: """
            <td class="no-day">
              <a class="assessment-link" data-assessment-id="9">Orphan</a>
            </td>
            """
        ))

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].dueDate)
    }

    /// **[I]** An out-of-range day number is rejected rather than rolled over into the next month.
    func testDayNumberOutOfRangeForTheMonthIsRejected() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            // February 2026 has 28 days.
            script: "var month = 02 - 1; var year = 2026;",
            cells: Self.dayCell(day: 31, anchors: """
                <a class="assessment-link" data-assessment-id="10">Impossible</a>
                """)
        ))

        XCTAssertEqual(items.count, 1, "the item itself still parses; only its date is refused")
        XCTAssertNil(items.first?.dueDate, "31 February must not become 3 March")
    }

    // MARK: - Degrading

    /// **[I]** A month grid can render the same item in more than one cell; identity wins.
    func testTheSameItemRenderedTwiceIsReturnedOnce() throws {
        let anchor = """
            <a class="assessment-link" data-assessment-id="42" data-assessment-type="class"
               data-assessment-date="10-Aug-2026">Lab report</a>
            """
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: anchor) + Self.dayCell(day: 11, anchors: anchor)
        ))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "class:42")
    }

    /// **[I]** A class-assigned and a student-created item may legitimately share the number 42;
    /// the kind prefix is what stops the dedupe from eating one of them.
    func testTheTwoIdSpacesDoNotCollide() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: """
                <a class="assessment-link" data-assessment-id="42" data-assessment-type="class">A</a>
                <a class="assessment-link" data-assessment-id="42" data-assessment-type="student">B</a>
                """)
        ))

        XCTAssertEqual(items.map(\.id), ["class:42", "student:42"])
    }

    /// **[I]** An anchor with no id is not an assessment.
    func testAnchorWithoutAnIdIsSkipped() throws {
        let items = try W4AssessmentParser.parse(Self.calendarPage(
            script: "var month = 08 - 1; var year = 2026;",
            cells: Self.dayCell(day: 10, anchors: """
                <a class="assessment-link" data-status="pending">No id</a>
                <a class="assessment-link" data-assessment-id="5">Real</a>
                """)
        ))

        XCTAssertEqual(items.map(\.rawId), ["5"])
    }

    /// The degrade contract: nothing here throws and nothing here crashes, whatever arrives.
    func testEmptyAndGarbageInputDegradeToAnEmptyList() throws {
        XCTAssertTrue(try W4AssessmentParser.parse("").isEmpty)
        XCTAssertTrue(try W4AssessmentParser.parse("<html><body><p>nope</p></body></html>").isEmpty)
        XCTAssertTrue(try W4AssessmentParser.parse("<a class=\"assessment-link\">").isEmpty)
        XCTAssertTrue(try W4AssessmentParser.parse("<<<not html>>> & & &").isEmpty)
    }

    // MARK: - [I] Synthetic page builder

    /// Mirrors the hand-written fixture's structure: an inline CDATA script plus a
    /// `table.calendar` whose day cells carry a `.day-header`. Every attribute name it emits is
    /// invented — see the file header.
    private static func calendarPage(script: String, cells: String) -> String {
        """
        <html><head>
        <script type="text/javascript">
        /*<![CDATA[*/
        \(script)
        /*]]>*/
        </script>
        </head><body>
        <div id="content_inner">
          <div class="calendar-div">
            <table class="calendar">
              <tr><th>Monday</th><th>Tuesday</th></tr>
              <tr class="days">\(cells)</tr>
            </table>
          </div>
        </div>
        </body></html>
        """
    }

    private static func dayCell(day: Int, anchors: String) -> String {
        """
        <td class="day">
          <div class="day-header">\(day)</div>
          <div class="day-content"><div class="assessments">\(anchors)</div></div>
        </td>
        """
    }
}
