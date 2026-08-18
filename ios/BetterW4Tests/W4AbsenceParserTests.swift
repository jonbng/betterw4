//
//  W4AbsenceParserTests.swift
//  BetterW4Tests
//
//  Tests for `W4AbsenceParser` (item 4.4): the two Home attendance meters and the AC / EA
//  registration lists.
//
//  FIXTURE PROVENANCE — the two halves of this file rest on very different evidence.
//
//  [V] `Fixtures/W4/home.html` is a REAL CAPTURE (sanitized: identities replaced). It contains
//      `<div id="absences">` with `#academic-absences` and `#ea-absences`, and BOTH read
//      "You have 0 absences and 0 latenesses so far"
//      (references/pages/UWCRCN W4.html:239-249). Zero is therefore the only meter reading that
//      has ever been observed, and the tests in the first section assert exactly that. They are
//      the only assertions in this file backed by W4's own bytes.
//
//  [I] `Fixtures/W4/absences.html` is HAND-WRITTEN, and so is every inline snippet below. **The
//      absence list page has never been captured** — not one row, not one header, not one column
//      label (docs/spec/parsers.md section 8: "List page — [U]. Never captured."). The column
//      set, the header labels, the summary and the pager markup are all inferred from the Yii 1
//      CGridView convention. A test that passes against them proves `W4AbsenceParser` behaves as
//      designed; it proves NOTHING about what W4 serves.
//
//      The things about this page that ARE verified, and that the [I] tests exercise:
//        * the routes `people/students/absences` / `people/students/eaabsences` (captured side
//          menus and captured Home meter links),
//        * `tr.prearranged_1` / `tr.prearranged_2` / `tr.medical_1` / `tr.medical_2` are styled by
//          W4's own `css/tables.css` (bug B14) — so a row's category is carried by its class, not
//          only by a "Type" column,
//        * `.grid-view table.items` and `a.sort_asc` / `a.sort_desc` are styled by W4's own CSS
//          too (parsers.md section 0.4), which is why the grid shape — but NOT its columns — is
//          taken as given.
//
//  Replace `absences.html` the moment a real `GET index.php?r=people/students/absences` is
//  captured, and expect the [I] assertions to change.
//

import XCTest
@testable import BetterW4

final class W4AbsenceParserTests: XCTestCase {

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

    // MARK: - [V] The real Home capture

    /// **[V]** The captured Home page renders both meters, and both read zero. This is the entire
    /// factual basis for the meter parser, so it is asserted literally: two meters present, both
    /// `0 absences and 0 latenesses`.
    func testCapturedHomePageReportsZeroOnBothMeters() throws {
        let meters = W4AbsenceParser.parseHomeMeters(try fixture("home"))

        XCTAssertFalse(meters.isEmpty, "#academic-absences and #ea-absences are both in the capture")
        XCTAssertEqual(meters.academic, AttendanceMeter(absences: 0, latenesses: 0))
        XCTAssertEqual(meters.extraAcademic, AttendanceMeter(absences: 0, latenesses: 0))
        XCTAssertEqual(meters.academic?.total, 0)
        XCTAssertTrue(meters.extraAcademic?.isClean ?? false)
    }

    /// **[V]** The same two readings through the single-meter entry point, which is what a caller
    /// holding only one source uses.
    func testCapturedHomePageMetersAreAddressableBySource() throws {
        let home = try fixture("home")

        XCTAssertEqual(W4AbsenceParser.parseMeter(home, source: .academics), AttendanceMeter.zero)
        XCTAssertEqual(W4AbsenceParser.parseMeter(home, source: .extraAcademics), AttendanceMeter.zero)

        let meters = W4AbsenceParser.parseHomeMeters(home)
        XCTAssertEqual(meters.meter(for: .academics), meters.academic)
        XCTAssertEqual(meters.meter(for: .extraAcademics), meters.extraAcademic)
    }

    /// **[I]** (synthesized empty page — it asserts a design contract, not W4's markup.) A meter
    /// W4 did not render is *absent*, which is a different fact from a meter that reads zero: the
    /// UI has to tell them apart, so `nil` must never be flattened into `.zero` in the parser.
    func testAMissingMeterIsNilRatherThanZero() {
        let meters = W4AbsenceParser.parseHomeMeters("<html><body><div id=\"main\"></div></body></html>")

        XCTAssertTrue(meters.isEmpty)
        XCTAssertNil(meters.academic)
        XCTAssertNil(meters.extraAcademic)
        XCTAssertNotEqual(meters.academic, AttendanceMeter.zero)
    }

    /// **[V]** Home is not a list page: it has no grid at all. Running the list parser over it
    /// must yield zero records while still recovering the (captured, zero) meter — never rows
    /// invented out of page furniture.
    func testCapturedHomePageYieldsNoRecordsButKeepsTheMeter() throws {
        let list = W4AbsenceParser.parseList(try fixture("home"), source: .academics)

        XCTAssertEqual(list.source, .academics)
        XCTAssertTrue(list.records.isEmpty)
        XCTAssertTrue(list.isEmpty)
        XCTAssertEqual(list.meter, AttendanceMeter.zero)
        XCTAssertFalse(list.hasMorePages)
    }

    // MARK: - [I] The synthesized list fixture

    /// **[I]** Four hand-written rows parse into four records. Nothing here is evidence about W4.
    func testSynthesizedListParsesEveryRow() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)

        XCTAssertEqual(list.records.count, 4)
        XCTAssertEqual(list.source, .academics)
        XCTAssertNil(list.emptyMessage, "a list with rows has no empty-state message")
        XCTAssertTrue(list.records.allSatisfy { $0.source == .academics })
    }

    /// **[I]** D-13: the meter comes from the meter sentence and from nowhere else. The fixture
    /// says "3 absences and 1 lateness" while rendering FOUR rows, precisely so that a parser that
    /// counted rows would fail this test.
    func testListMeterComesFromTheProseNotFromTheRowCount() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)

        XCTAssertEqual(list.meter, AttendanceMeter(absences: 3, latenesses: 1))
        XCTAssertEqual(list.records.count, 4, "four rows, three absences — they must not agree")
        XCTAssertEqual(W4AbsenceParser.parseMeter(try fixture("absences"), source: .academics),
                       AttendanceMeter(absences: 3, latenesses: 1))
    }

    /// **[I]** Header-driven column matching: every field lands where the header says it does.
    func testHeaderDrivenColumnsMapEveryField() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)
        let first = try XCTUnwrap(list.records.first)

        XCTAssertEqual(first.displayDate, "10-Aug-2026")
        XCTAssertEqual(first.date, try osloDate(2026, 8, 10))
        XCTAssertEqual(first.period, "P1")
        XCTAssertEqual(first.subject, "Mathematics HL")
        XCTAssertEqual(first.kind, .absence)
        XCTAssertEqual(first.status, "Unexcused", "D-13: the raw status is carried verbatim")
        XCTAssertEqual(first.teacher, "A. Teacher")
        XCTAssertNil(first.note, "an empty comment cell is absent, not \"\"")
        XCTAssertFalse(first.isEditable, "absence rows are read-only for students")
    }

    /// **[I]** `d-MMM-yy` / `dd-MMM-yy` are two of the seven input formats `W4Dates` documents
    /// (plan D-11), so a short year should still yield a date in 2026.
    ///
    /// ⚠️ KNOWN BUG — `W4Dates`, **not** `W4AbsenceParser`. `W4Dates.dateFormatters` tries
    /// `d-MMM-yyyy` before `d-MMM-yy`, and a non-lenient `DateFormatter` happily accepts a
    /// two-digit year for a `yyyy` field. `"11-Aug-26"` therefore parses as **11 August 0026** and
    /// the `yy` formatters are unreachable: a row dated `11-Aug-26` sorts two millennia into the
    /// past and renders as year 26. `W4AbsenceParser` is innocent — it delegates every date to
    /// `W4Dates` exactly as D-11 requires — so the fix belongs in `W4Dates` (require four digits
    /// for the `yyyy` formats, or try the `yy` formats first for inputs whose year token is two
    /// digits). Once it is fixed this test will report "expected failure not recorded": delete the
    /// `XCTExpectFailure` wrapper, keep the assertion.
    func testShortYearRowStillParsesItsDate() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)
        let lateness = try XCTUnwrap(list.records.first { $0.kind == .lateness })

        XCTAssertEqual(lateness.displayDate, "11-Aug-26", "the cell text is preserved verbatim")
        XCTAssertEqual(lateness.subject, "Biology SL")
        XCTAssertEqual(lateness.status, "Excused")
        XCTAssertEqual(lateness.note, "Arrived 10 minutes late")

        let expected = try osloDate(2026, 8, 11)
        XCTExpectFailure("W4Dates bug: `d-MMM-yyyy` swallows a two-digit year, so \"11-Aug-26\" "
                         + "parses as 11-Aug-0026 and the `d-MMM-yy` formatters never run") {
            XCTAssertEqual(lateness.date, expected)
        }
    }

    /// The same `W4Dates` bug, stated at its source so it is unmistakable which layer is wrong.
    /// Four-digit years are unaffected, which is why nothing else in the suite trips over it.
    func testTwoDigitYearsAreMisparsedByW4Dates() throws {
        XCTAssertEqual(W4Dates.parseDate("11-Aug-2026"), try osloDate(2026, 8, 11),
                       "four-digit years are fine")

        let expected = try osloDate(2026, 8, 11)
        XCTExpectFailure("W4Dates: the `yy` input formats documented in D-11 are unreachable") {
            XCTAssertEqual(W4Dates.parseDate("11-Aug-26"), expected)
        }
    }

    /// **[I]** Bug B14. `tr.prearranged_*` / `tr.medical_*` are the one part of this page W4's own
    /// CSS corroborates, so the row class must win over the "Type" column — both rows below are
    /// typed "Absence" and neither is a plain absence.
    func testRowClassBeatsTheTypeColumn() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)

        let prearranged = try XCTUnwrap(list.records.first { $0.subject == "English A HL" })
        XCTAssertEqual(prearranged.kind, .prearranged, "tr.prearranged_1 wins over Type=Absence")
        XCTAssertEqual(prearranged.status, "Approved", "the raw status still says what W4 said")

        let medical = try XCTUnwrap(list.records.first { $0.subject == "Chemistry SL" })
        XCTAssertEqual(medical.kind, .medical, "tr.medical_2 wins over Type=Absence")
        XCTAssertEqual(medical.status, "Health centre")

        XCTAssertEqual(list.records.map(\.kind), [.absence, .lateness, .prearranged, .medical])
    }

    /// **[I]** The stripe suffix is not part of the category, and Yii's own `odd` / `even` /
    /// `selected` classes must never be read as one.
    func testStripeAndYiiClassesAreNotCategories() {
        XCTAssertEqual(AttendanceKind.kind(forRowClasses: ["odd", "prearranged_1"]), .prearranged)
        XCTAssertEqual(AttendanceKind.kind(forRowClasses: ["even", "medical_2"]), .medical)
        XCTAssertNil(AttendanceKind.kind(forRowClasses: ["odd", "even", "selected"]))
        XCTAssertNil(AttendanceKind.kind(forRowClasses: []))
    }

    /// **[I]** Bug B10: a Yii pager, or a summary that says there are more results than this page
    /// shows, means the list is truncated. The UI says "more on W4" instead of pretending page 1
    /// is everything.
    func testPagerOnTheSynthesizedListIsReportedAsMorePages() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)
        XCTAssertTrue(list.hasMorePages, "the fixture carries a yiiPager AND \"1-4 of 12\"")
    }

    /// **[I]** …and a complete single page is not reported as truncated: a summary that accounts
    /// for every result, and a pager whose only links are placeholders, both mean "this is all".
    func testCompleteSinglePageIsNotReportedAsMorePages() {
        let firstRow = Self.row(
            classes: "odd",
            cells: ["10-Aug-2026", "P1", "Maths HL", "Absence", "Unexcused", "", ""]
        )
        let secondRow = Self.row(
            classes: "even",
            cells: ["11-Aug-2026", "P2", "Maths HL", "Absence", "Unexcused", "", ""]
        )
        let table = Self.table(rows: firstRow + secondRow)
        let pager = "<div class=\"pager\"><ul class=\"yiiPager\">"
            + "<li class=\"page selected\"><a href=\"#\">1</a></li></ul></div>"
        let html = Self.page("""
        <div class="grid-view" id="yw0">
          <div class="summary">Displaying 1-2 of 2 results.</div>
          \(table)
          \(pager)
        </div>
        """)

        let list = W4AbsenceParser.parseList(html, source: .academics)
        XCTAssertEqual(list.records.count, 2)
        XCTAssertFalse(list.hasMorePages)
    }

    // MARK: - [I] Identity (bug B19)

    /// **[I]** Bug B19: the row id is a content hash, never the row index. A Yii grid can be
    /// re-sorted (`a.sort_asc` / `a.sort_desc` are **[V]** — styled in W4's own CSS,
    /// parsers.md section 0.4) or paged, and an index-derived id would silently reassign every
    /// row's identity when it is.
    func testRecordIdsAreContentHashesNotRowIndexes() throws {
        let list = W4AbsenceParser.parseList(try fixture("absences"), source: .academics)
        let first = try XCTUnwrap(list.records.first)

        XCTAssertEqual(first.id, AttendanceRecord.identity(
            source: .academics,
            dateRaw: "10-Aug-2026",
            period: "P1",
            subject: "Mathematics HL",
            kind: .absence
        ))
        XCTAssertTrue(first.id.hasPrefix("ac-"))
        XCTAssertEqual(Set(list.records.map(\.id)).count, 4, "four distinct rows, four distinct ids")
        XCTAssertFalse(first.id.hasSuffix("-0"), "the first occurrence carries no occurrence suffix")
    }

    /// **[I]** The same rows served in a different order keep the same ids. This is the actual
    /// regression B19 describes: sort the grid by class instead of by date and every id must be
    /// unchanged.
    func testResortingTheGridDoesNotChangeAnyId() {
        let biology = Self.row(classes: "odd", cells: ["10-Aug-2026", "P1", "Biology SL", "Absence", "Unexcused", "A. Teacher", ""])
        let chemistry = Self.row(classes: "even", cells: ["11-Aug-2026", "P3", "Chemistry SL", "Lateness", "Excused", "B. Teacher", ""])
        let english = Self.row(classes: "odd", cells: ["12-Aug-2026", "P2", "English A HL", "Absence", "Approved", "C. Teacher", ""])

        let byDate = W4AbsenceParser.parseList(
            Self.page(Self.gridView(rows: biology + chemistry + english)), source: .academics
        )
        let bySubject = W4AbsenceParser.parseList(
            Self.page(Self.gridView(rows: english + chemistry + biology)), source: .academics
        )

        XCTAssertEqual(byDate.records.count, 3)
        XCTAssertEqual(bySubject.records.count, 3)
        XCTAssertEqual(Set(byDate.records.map(\.id)), Set(bySubject.records.map(\.id)))

        for record in byDate.records {
            let resorted = bySubject.records.first { $0.subject == record.subject }
            XCTAssertEqual(resorted?.id, record.id, "\(record.subject ?? "?") changed identity on re-sort")
        }
    }

    /// **[I]** Two rows whose content is byte-identical still need distinct ids, or a SwiftUI list
    /// collapses them. The second one gets an occurrence suffix.
    func testByteIdenticalRowsGetDistinctIds() {
        let duplicate = Self.row(classes: "odd", cells: ["10-Aug-2026", "P1", "Maths HL", "Absence", "Unexcused", "A. Teacher", ""])
        let list = W4AbsenceParser.parseList(
            Self.page(Self.gridView(rows: duplicate + duplicate)), source: .academics
        )

        XCTAssertEqual(list.records.count, 2)
        XCTAssertNotEqual(list.records[0].id, list.records[1].id)
        XCTAssertEqual(list.records[1].id, AttendanceRecord.identity(
            source: .academics,
            dateRaw: "10-Aug-2026",
            period: "P1",
            subject: "Maths HL",
            kind: .absence,
            occurrence: 1
        ))
    }

    /// **[I]** AC and EA are separate ledgers that can hold the very same row. The source is part
    /// of the identity, so merging the two lists cannot collapse them (D-9's rule, applied here).
    func testTheSameRowInBothLedgersGetsDifferentIds() {
        let row = Self.row(classes: "odd", cells: ["10-Aug-2026", "P1", "Kayaking", "Absence", "Unexcused", "A. Teacher", ""])
        let academics = W4AbsenceParser.parseList(Self.page(Self.gridView(rows: row)), source: .academics)
        let extraAcademics = W4AbsenceParser.parseList(Self.page(Self.gridView(rows: row)), source: .extraAcademics)

        let acRecord = academics.records.first
        let eaRecord = extraAcademics.records.first
        XCTAssertEqual(acRecord?.source, .academics)
        XCTAssertEqual(eaRecord?.source, .extraAcademics)
        XCTAssertTrue(eaRecord?.id.hasPrefix("ea-") ?? false)
        XCTAssertNotEqual(acRecord?.id, eaRecord?.id)
    }

    /// The hash itself must be deterministic across launches — Swift's own `hashValue` is seeded
    /// per process and would reshuffle every id on every launch.
    func testIdentityHashIsStableAndSeedIndependent() {
        XCTAssertEqual(AttendanceRecord.fnv1aHex("ac|10-Aug-2026|P1|Maths HL|absence"),
                       AttendanceRecord.fnv1aHex("ac|10-Aug-2026|P1|Maths HL|absence"))
        XCTAssertEqual(AttendanceRecord.fnv1aHex("").count, 16, "16 lowercase hex digits, always")
        XCTAssertNotEqual(AttendanceRecord.fnv1aHex("a"), AttendanceRecord.fnv1aHex("b"))
    }

    // MARK: - [I] Empty states (bug B9)

    /// **[I]** Yii 1 writes its empty state three different ways, and only checking `td.empty`
    /// misses two of them. All three must yield zero records and the verbatim message.
    func testAllThreeGridEmptyStatesAreRecognised() {
        let cases: [(name: String, rowHTML: String, expected: String)] = [
            ("td.empty", "<tr><td colspan=\"7\" class=\"empty\">No results found.</td></tr>", "No results found."),
            ("span.empty", "<tr><td colspan=\"7\"><span class=\"empty\">Nothing to show</span></td></tr>", "Nothing to show"),
            ("bare sentence", "<tr><td colspan=\"7\">No absences found.</td></tr>", "No absences found.")
        ]

        for testCase in cases {
            let list = W4AbsenceParser.parseList(
                Self.page(Self.gridView(rows: testCase.rowHTML)), source: .academics
            )
            XCTAssertTrue(list.records.isEmpty, "\(testCase.name): an empty state is not a record")
            XCTAssertEqual(list.emptyMessage, testCase.expected, "\(testCase.name)")
            XCTAssertFalse(list.hasMorePages, "\(testCase.name)")
        }
    }

    /// **[I]** The non-grid empty state: `#content_inner > div.note`. ("No users found" is the
    /// **[V]** example of this shape, from the captured applicants page — on a different route.)
    func testPageNoteIsUsedWhenThereIsNoGridAtAll() {
        let list = W4AbsenceParser.parseList(
            Self.page("<h2>My Absences</h2><div class=\"note\">No absences found</div>"),
            source: .extraAcademics
        )

        XCTAssertTrue(list.records.isEmpty)
        XCTAssertEqual(list.emptyMessage, "No absences found")
        XCTAssertEqual(list.source, .extraAcademics)
        XCTAssertNil(list.meter, "no meter sentence on the page means no meter, not zero")
    }

    // MARK: - [I] Structural fallbacks

    /// **[I]** With no header row at all the parser falls back to the column order parsers.md
    /// section 8 documents — itself inferred — rather than dropping the page.
    func testGridWithoutAHeaderFallsBackToTheInferredColumnOrder() {
        let rows = Self.row(
            classes: "odd",
            cells: ["10-Aug-2026", "P1", "Mathematics HL", "Absence", "Unexcused", "Overslept"]
        )
        let html = Self.page("""
        <div class="grid-view" id="yw0"><table class="items"><tbody>\(rows)</tbody></table></div>
        """)

        let list = W4AbsenceParser.parseList(html, source: .academics)
        let record = list.records.first

        XCTAssertEqual(list.records.count, 1)
        XCTAssertEqual(record?.displayDate, "10-Aug-2026")
        XCTAssertEqual(record?.period, "P1")
        XCTAssertEqual(record?.subject, "Mathematics HL")
        XCTAssertEqual(record?.kind, .absence)
        XCTAssertEqual(record?.status, "Unexcused")
        XCTAssertEqual(record?.note, "Overslept")
        XCTAssertNil(record?.teacher, "the inferred order has no teacher column to read")
    }

    /// **[I]** A category we have never seen is `.unknown`, and W4's own words are still shown.
    /// Inventing a category out of an unrecognised label would be worse than admitting ignorance.
    func testUnrecognisedTypeBecomesUnknownButKeepsTheRawStatus() {
        let rows = Self.row(
            classes: "odd",
            cells: ["14-Aug-2026", "P4", "Kayaking", "Off-campus leave", "Recorded by staff", "E. Staff", "Regatta"]
        )
        let list = W4AbsenceParser.parseList(Self.page(Self.gridView(rows: rows)), source: .extraAcademics)
        let record = list.records.first

        XCTAssertEqual(record?.kind, .unknown)
        XCTAssertEqual(record?.kind.displayName, "Registration")
        XCTAssertEqual(record?.status, "Recorded by staff")
        XCTAssertEqual(record?.note, "Regatta")
    }

    /// **[I]** A date cell that carries more than the date still yields a date, and the cell text
    /// is preserved exactly as W4 wrote it.
    func testDateIsRecoveredFromACellThatCarriesMoreThanTheDate() {
        let rows = Self.row(
            classes: "odd",
            cells: ["Mon 13-Aug-2026 (P5)", "P5", "Chemistry SL", "Absence", "Unexcused", "", ""]
        )
        let list = W4AbsenceParser.parseList(Self.page(Self.gridView(rows: rows)), source: .academics)

        XCTAssertEqual(list.records.first?.displayDate, "Mon 13-Aug-2026 (P5)")
        XCTAssertEqual(list.records.first?.date, W4Dates.parseDate("13-Aug-2026"))
        XCTAssertNotNil(list.records.first?.date)
    }

    /// **[I]** An unparseable date does not lose the row: the raw text is still rendered.
    func testUnparseableDateKeepsTheRowWithoutADate() {
        let rows = Self.row(
            classes: "odd",
            cells: ["Sometime last term", "P1", "Maths HL", "Absence", "Unexcused", "", ""]
        )
        let list = W4AbsenceParser.parseList(Self.page(Self.gridView(rows: rows)), source: .academics)

        XCTAssertEqual(list.records.count, 1)
        XCTAssertNil(list.records.first?.date)
        XCTAssertEqual(list.records.first?.displayDate, "Sometime last term")
    }

    // MARK: - [I] The meter fallback is keyed on the link route

    /// **[I]** `homepage.css` also names `#advisor-absences`, `#mentor-absences`, `#admin-absences`
    /// and `#staff-absences` — meters a student never sees, but which a staff account would. When
    /// the two student ids are missing, the fallback keys on the "View attendance" **route**, so a
    /// staff meter can never be misread as the student's. The staff numbers below (7 / 5) must not
    /// appear anywhere in the result.
    func testMeterFallbackKeysOnTheRouteNotOnProsePosition() {
        let html = Self.page("""
        <div id="staff-absences">
          <h3>Staff Attendance Meter</h3>
          <p>You have 7 absences and 5 latenesses so far<br>
             <a href="https://w4.uwcrcn.no/index.php?r=people/staff/absences">View attendance</a></p>
        </div>
        <div class="meter">
          <h3>Academics Attendance Meter</h3>
          <p>You have 2 absences and 1 lateness so far<br>
             <a href="https://w4.uwcrcn.no/index.php?r=people/students/absences">View attendance</a></p>
        </div>
        <div class="meter">
          <h3>EA Attendance Meter</h3>
          <p>You have 4 absences and 3 latenesses so far<br>
             <a href="https://w4.uwcrcn.no/index.php?r=people/students/eaabsences">View attendance</a></p>
        </div>
        """)

        let meters = W4AbsenceParser.parseHomeMeters(html)

        XCTAssertEqual(meters.academic, AttendanceMeter(absences: 2, latenesses: 1))
        XCTAssertEqual(meters.extraAcademic, AttendanceMeter(absences: 4, latenesses: 3))
        XCTAssertNotEqual(meters.academic, AttendanceMeter(absences: 7, latenesses: 5))
        XCTAssertNotEqual(meters.extraAcademic, AttendanceMeter(absences: 7, latenesses: 5))
    }

    /// **[V]** The routes the fallback keys on, and the one route that must NOT resolve:
    /// `people/students/absences/register` is the "Register absence" form, a different page.
    func testSourceRoutesAreExactMatches() {
        XCTAssertEqual(AttendanceSource.academics.listRoute, "people/students/absences")
        XCTAssertEqual(AttendanceSource.extraAcademics.listRoute, "people/students/eaabsences")
        XCTAssertEqual(AttendanceSource.source(forRoute: "people/students/absences"), .academics)
        XCTAssertEqual(AttendanceSource.source(forRoute: "PEOPLE/STUDENTS/EAABSENCES"), .extraAcademics)
        XCTAssertNil(AttendanceSource.source(forRoute: "people/students/absences/register"))
    }

    /// **[I]** W4 writes both the singular and the plural, and the trailing "so far" is not part
    /// of the payload.
    func testMeterProseAcceptsSingularAndPluralForms() {
        let singular = W4AbsenceParser.parseMeter(
            Self.page("<p>You have 1 absence and 1 lateness so far</p>"), source: .academics
        )
        let plural = W4AbsenceParser.parseMeter(
            Self.page("<p>You have 12 absences and 30 latenesses</p>"), source: .academics
        )

        XCTAssertEqual(singular, AttendanceMeter(absences: 1, latenesses: 1))
        XCTAssertEqual(plural, AttendanceMeter(absences: 12, latenesses: 30))
        XCTAssertNil(W4AbsenceParser.parseMeter(Self.page("<p>Attendance is fine.</p>"), source: .academics))
    }

    // MARK: - Degrading

    /// The degrade contract: no throw, no crash, no invented rows — whatever arrives.
    func testEmptyAndGarbageInputDegradeToAnEmptyList() {
        for source in AttendanceSource.allCases {
            for html in ["", "<html><body><p>nope</p></body></html>", "<<<not html>>> & & &"] {
                let list = W4AbsenceParser.parseList(html, source: source)
                XCTAssertEqual(list.source, source)
                XCTAssertTrue(list.records.isEmpty)
                XCTAssertNil(list.meter)
                XCTAssertFalse(list.hasMorePages)
            }
            XCTAssertNil(W4AbsenceParser.parseMeter("", source: source))
        }
        XCTAssertTrue(W4AbsenceParser.parseHomeMeters("").isEmpty)
    }

    /// A row with nothing in it is not a registration.
    func testRowOfEmptyCellsIsNotARecord() {
        let list = W4AbsenceParser.parseList(
            Self.page(Self.gridView(rows: Self.row(classes: "odd", cells: ["", "", "", "", "", "", ""]))),
            source: .academics
        )
        XCTAssertTrue(list.records.isEmpty)
    }

    // MARK: - [I] Synthetic page builders
    //
    // Every byte these emit is hand-written from the Yii 1 CGridView convention. They exist to
    // exercise `W4AbsenceParser`; they are not a model of W4's absence list, which nobody has seen.

    private static func page(_ inner: String) -> String {
        """
        <html><body>
        <div id="main">
          <div id="content"><div id="content_frame"><div id="content_main">
            <div id="content_inner">
            \(inner)
            </div>
          </div></div></div>
        </div>
        </body></html>
        """
    }

    /// The inferred header set: `Date | Period | Class | Type | Status | Teacher | Comment`.
    private static func gridView(rows: String, summary: String? = nil) -> String {
        let summaryHTML = summary.map { "<div class=\"summary\">\($0)</div>" } ?? ""
        return """
        <div class="grid-view" id="yw0">
          \(summaryHTML)
          \(table(rows: rows))
        </div>
        """
    }

    private static func table(rows: String) -> String {
        """
        <table class="items">
          <thead>
            <tr>
              <th><a class="sort_desc" href="#">Date</a></th><th>Period</th><th>Class</th>
              <th>Type</th><th>Status</th><th>Teacher</th><th>Comment</th>
            </tr>
          </thead>
          <tbody>\(rows)</tbody>
        </table>
        """
    }

    private static func row(classes: String, cells: [String]) -> String {
        let tds = cells.map { "<td>\($0)</td>" }.joined()
        return "<tr class=\"\(classes)\">\(tds)</tr>"
    }
}
