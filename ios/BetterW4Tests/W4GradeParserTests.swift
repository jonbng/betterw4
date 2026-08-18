//
//  W4GradeParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance — read this before adding an assertion.
//
//  **Nothing in this file is verified against W4.** The grades page has never
//  been captured: not one header row, not one data row (docs/spec/parsers.md
//  §10, features.md §1.6, reviewer-notes.md §7). `Fixtures/W4/grades.html` is
//  hand-written and carries that warning in its own header comment.
//
//  So every assertion below is marked **[I]**: it proves that `W4GradeParser`
//  behaves as designed against markup *we* invented. It proves nothing about
//  what w4.uwcrcn.no serves. The only [V] facts in play are the CSS class names
//  the server's own `css/main.css` defines — `table.grades`, `th.anticipated`,
//  `td.anticipated` and the three `.effort-grade-*` levels — and even those tell
//  us the classes exist, not how the table around them is laid out.
//
//  The test that matters most is `testMissingKnownColumnsDoNotShiftValues`:
//  columns are dynamic, so the one property that must hold whatever W4 does is
//  that a missing, renamed or re-ordered column can never slide a grade into a
//  neighbouring column.
//

import XCTest
@testable import BetterW4

final class W4GradeParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Minimal `#content_inner` page. **[I]** — the chrome is real (parsers.md
    /// §0.3), the table inside is whatever the test needs.
    private static func page(_ inner: String) -> String {
        """
        <html><body><div id="main"><div id="content"><div id="content_frame">
        <div id="content_main"><div id="content_inner">
        \(inner)
        </div></div></div></div></div></body></html>
        """
    }

    // MARK: - The synthesized grades fixture [I]

    func testFixtureRowsCarryIdentityColumns() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        XCTAssertEqual(report.title, "My Grades")
        XCTAssertEqual(report.rows.count, 3)

        let mathematics = try XCTUnwrap(report.rows.first)
        XCTAssertEqual(mathematics.subject, "Mathematics")
        XCTAssertEqual(mathematics.level, "HL")
        XCTAssertEqual(mathematics.teacher, "A. Newton")
        XCTAssertEqual(mathematics.displaySubject, "Mathematics HL")

        XCTAssertEqual(report.rows.map(\.subject), ["Mathematics", "Biology", "Visual Arts"])
        XCTAssertEqual(report.rows.map(\.level), ["HL", "SL", "SL"])
        XCTAssertEqual(report.rows.map(\.teacher), ["A. Newton", "B. Darwin", "C. Kahlo"])
    }

    /// Identity columns are consumed as identity; everything else becomes a
    /// dynamic column keyed by a slug of the server's own header, in the
    /// server's own order.
    func testFixtureColumnsComeFromTheHeaderInServerOrder() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        XCTAssertEqual(report.columns.map(\.id), ["predicted", "final", "effort"])
        XCTAssertEqual(report.columns.map(\.label), ["Predicted", "Final", "Effort"])
        XCTAssertEqual(report.defaultColumnID, "final")
    }

    /// `th.anticipated` is **[V]** in `css/main.css` — the marker is a class, so
    /// the flag must come from the class and never from the label text.
    func testFixtureFlagsTheAnticipatedColumn() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        XCTAssertEqual(report.column(withID: "predicted")?.isAnticipated, true)
        XCTAssertEqual(report.column(withID: "final")?.isAnticipated, false)
        XCTAssertEqual(report.column(withID: "effort")?.isAnticipated, false)
        XCTAssertEqual(report.anticipatedColumns.map(\.id), ["predicted"])
    }

    /// The three `.effort-grade-*` classes are **[V]**; that they sit in a
    /// column called "Effort" is **[I]**.
    func testFixtureParsesTheThreeEffortLevels() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        XCTAssertEqual(report.rows[0].cell(for: "effort")?.effort, .meets)
        XCTAssertEqual(report.rows[1].cell(for: "effort")?.effort, .almostMeets)
        XCTAssertEqual(report.rows[2].cell(for: "effort")?.effort, .doesNotMeet)
        XCTAssertEqual(report.rows[0].cell(for: "effort")?.value, "Meets expectations")

        // An effort grade is never mistaken for a grade.
        XCTAssertNil(report.rows[0].cell(for: "effort")?.ibGrade)
        XCTAssertNil(report.rows[0].cell(for: "predicted")?.effort)
    }

    /// An en dash and a hyphen both mean "no grade", and "no grade" is the
    /// absence of a cell — never a cell whose value is `""` or `"–"`.
    func testFixtureDashCellsAreMissingNotEmpty() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        // Biology has no final grade (en dash); Visual Arts has no predicted
        // grade (plain hyphen).
        XCTAssertNil(report.rows[1].cell(for: "final"))
        XCTAssertNil(report.rows[2].cell(for: "predicted"))

        XCTAssertEqual(report.rows[0].cell(for: "predicted")?.value, "6")
        XCTAssertEqual(report.rows[0].cell(for: "final")?.value, "7")
        XCTAssertEqual(report.rows[1].cell(for: "predicted")?.value, "5")
        XCTAssertEqual(report.rows[2].cell(for: "final")?.value, "4")

        let dashes = report.rows.flatMap { $0.cells.values }.filter { cell in
            cell.value == "-" || cell.value == "\u{2013}"
        }
        XCTAssertTrue(dashes.isEmpty, "a dash must never survive as a cell value")
    }

    func testFixtureSurfacesThePageNote() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        XCTAssertEqual(
            report.alerts,
            ["Predicted grades are provisional until the November session."]
        )
    }

    func testFixtureRowIDsAreStableAndUnique() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        XCTAssertEqual(report.rows.map(\.id), ["mathematics-hl", "biology-sl", "visual-arts-sl"])
        XCTAssertEqual(Set(report.rows.map(\.id)).count, report.rows.count)
    }

    // MARK: - The property that matters: values never shift [I]

    /// **The point of the whole parser.** Columns are dynamic, so a column that
    /// disappears, moves, or turns up unrecognised must drop out of the report —
    /// it must never slide somebody else's grade into its place.
    ///
    /// A positional parser passes the first assertion and fails every one after
    /// it.
    func testMissingKnownColumnsDoNotShiftValues() throws {
        let complete = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th class="anticipated">Predicted</th><th>Final</th></tr>
              <tr class="table_1_bg"><td>Mathematics</td><td>6</td><td>7</td></tr>
            </table>
            """))

        XCTAssertEqual(complete.columns.map(\.id), ["predicted", "final"])
        XCTAssertEqual(complete.rows[0].cell(for: "predicted")?.value, "6")
        XCTAssertEqual(complete.rows[0].cell(for: "final")?.value, "7")

        // 1. The anticipated column is gone. "7" is a final grade and must stay
        //    a final grade; nothing at all is predicted.
        let withoutPredicted = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Final</th></tr>
              <tr class="table_1_bg"><td>Mathematics</td><td>7</td></tr>
            </table>
            """))

        XCTAssertEqual(withoutPredicted.columns.map(\.id), ["final"])
        XCTAssertEqual(withoutPredicted.rows[0].cell(for: "final")?.value, "7")
        XCTAssertNil(
            withoutPredicted.rows[0].cell(for: "predicted"),
            "a positional parser would report the final grade as the predicted one"
        )

        // 2. The columns are re-ordered and an unknown one is inserted in front
        //    of them. Every value stays under its own header.
        let reordered = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Comments</th><th>Final</th><th class="anticipated">Predicted</th></tr>
              <tr class="table_1_bg"><td>Visual Arts</td><td>Good progress</td><td>7</td><td>6</td></tr>
            </table>
            """))

        XCTAssertEqual(reordered.columns.map(\.id), ["comments", "final", "predicted"])
        XCTAssertEqual(reordered.rows[0].cell(for: "final")?.value, "7")
        XCTAssertEqual(reordered.rows[0].cell(for: "predicted")?.value, "6")
        XCTAssertEqual(reordered.rows[0].cell(for: "comments")?.value, "Good progress")
        XCTAssertEqual(reordered.column(withID: "predicted")?.isAnticipated, true)
        XCTAssertEqual(reordered.column(withID: "final")?.isAnticipated, false)
    }

    /// A row that stops early keeps its values where they were: the missing
    /// columns are missing, not back-filled from the right.
    func testShortRowLeavesTrailingColumnsEmpty() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Predicted</th><th>Final</th><th>Effort</th></tr>
              <tr><td>Biology</td><td>5</td></tr>
            </table>
            """))

        XCTAssertEqual(report.columns.map(\.id), ["predicted", "final", "effort"])
        XCTAssertEqual(report.rows[0].cell(for: "predicted")?.value, "5")
        XCTAssertNil(report.rows[0].cell(for: "final"))
        XCTAssertNil(report.rows[0].cell(for: "effort"))
    }

    /// A `colspan` moves the *grid*, so the parser has to move with it.
    func testColspanDoesNotShiftValues() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Predicted</th><th>Final</th><th>Effort</th></tr>
              <tr><td colspan="2">Biology</td><td>7</td><td>Meets expectations</td></tr>
            </table>
            """))

        XCTAssertEqual(report.rows[0].subject, "Biology")
        XCTAssertNil(report.rows[0].cell(for: "predicted"), "the subject cell spans that position")
        XCTAssertEqual(report.rows[0].cell(for: "final")?.value, "7")
        XCTAssertEqual(report.rows[0].cell(for: "effort")?.value, "Meets expectations")
    }

    /// Duplicate header labels keep the `-2` / `-3` suffix behaviour, so three
    /// terms stay three columns instead of collapsing into one.
    func testDuplicateHeaderLabelsGetUniqueKeys() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Term</th><th>Term</th><th>Term</th></tr>
              <tr><td>Chemistry</td><td>4</td><td>5</td><td>6</td></tr>
            </table>
            """))

        XCTAssertEqual(report.columns.map(\.id), ["term", "term-2", "term-3"])
        XCTAssertEqual(report.columns.map(\.label), ["Term", "Term", "Term"])
        XCTAssertEqual(report.rows[0].cell(for: "term")?.value, "4")
        XCTAssertEqual(report.rows[0].cell(for: "term-2")?.value, "5")
        XCTAssertEqual(report.rows[0].cell(for: "term-3")?.value, "6")
    }

    /// An unlabelled column still gets a stable key, so its values are carried
    /// rather than dropped — and nothing shifts into the gap.
    func testUnlabelledColumnGetsAPositionalKey() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th></th><th>Final</th></tr>
              <tr><td>Chemistry</td><td>*</td><td>6</td></tr>
            </table>
            """))

        XCTAssertEqual(report.columns.map(\.id), ["column-2", "final"])
        XCTAssertEqual(report.rows[0].cell(for: "column-2")?.value, "*")
        XCTAssertEqual(report.rows[0].cell(for: "final")?.value, "6")
    }

    // MARK: - Cells [I]

    func testEveryDashSpellingMeansNoGrade() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Hyphen</th><th>En dash</th><th>Blank</th><th>Em dash</th></tr>
              <tr><td>Physics</td><td>-</td><td>&ndash;</td><td>&nbsp;</td><td> &mdash; </td></tr>
            </table>
            """))

        XCTAssertEqual(report.rows.count, 1, "a row of dashes is still a subject the student takes")
        XCTAssertEqual(report.rows[0].subject, "Physics")
        XCTAssertTrue(
            report.rows[0].cells.isEmpty,
            "no grade must be the absence of a cell, never an empty or dash-valued one"
        )
    }

    /// **[I]** The effort class may equally well sit on the grade cell itself —
    /// `css/main.css` only proves the class exists, not which element wears it.
    func testEffortClassOnTheGradeCellIsPickedUp() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Final</th></tr>
              <tr><td>Music</td><td class="effort-grade-does-not-meet-expectations">5</td></tr>
            </table>
            """))

        let cell = report.rows[0].cell(for: "final")
        XCTAssertEqual(cell?.value, "5")
        XCTAssertEqual(cell?.effort, .doesNotMeet)
        XCTAssertEqual(cell?.ibGrade, 5)
    }

    /// The one documented exception to "a dash means no cell": an effort marker
    /// with no text is still information, so the cell survives with an empty
    /// value and the effort grade attached.
    func testEffortWithoutTextStillProducesACell() throws {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Effort</th></tr>
              <tr><td>Music</td><td><span class="effort-grade-meets-expectations">&ndash;</span></td></tr>
            </table>
            """))

        let cell = try XCTUnwrap(report.rows.first?.cell(for: "effort"))
        XCTAssertEqual(cell.effort, .meets)
        XCTAssertEqual(cell.value, "")
        XCTAssertFalse(cell.hasValue)
    }

    /// `td.anticipated` is styled by `css/main.css` too, so a header that
    /// forgets the class is still recoverable from the cells below it.
    func testAnticipatedFallsBackToTheCellClass() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Predicted</th></tr>
              <tr class="table_1_bg"><td>Music</td><td class="anticipated">6</td></tr>
            </table>
            """))

        XCTAssertEqual(report.column(withID: "predicted")?.isAnticipated, true)
    }

    /// IB grades are 1–7, but a predicted or effort column is free text and must
    /// never be coerced into a number.
    func testFreeTextIsNeverCoercedToANumber() throws {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Final</th><th>Predicted</th></tr>
              <tr><td>Mathematics</td><td>7</td><td>7 (provisional)</td></tr>
              <tr><td>Theory of Knowledge</td><td>B</td><td>B/C</td></tr>
            </table>
            """))

        XCTAssertEqual(report.rows[0].cell(for: "final")?.ibGrade, 7)
        XCTAssertEqual(report.rows[0].cell(for: "final")?.ibProgress, 1.0)
        XCTAssertEqual(report.rows[0].cell(for: "predicted")?.value, "7 (provisional)")
        XCTAssertNil(report.rows[0].cell(for: "predicted")?.ibGrade)

        XCTAssertEqual(report.rows[1].cell(for: "final")?.value, "B")
        XCTAssertNil(report.rows[1].cell(for: "final")?.ibGrade)

        // Only the one bare IB grade counts towards the column average.
        XCTAssertEqual(try XCTUnwrap(report.average(forColumnID: "final")), 7.0, accuracy: 0.0001)
        XCTAssertNil(report.average(forColumnID: "predicted"))
    }

    func testColumnAverageUsesOnlyItsOwnColumn() throws {
        let report = W4GradeParser.parse(try fixture("grades"))

        // Final: 7 and 4 (Biology has no final grade) ⇒ 5.5.
        XCTAssertEqual(try XCTUnwrap(report.average(forColumnID: "final")), 5.5, accuracy: 0.0001)
        // Predicted: 6 and 5 (Visual Arts has none) ⇒ 5.5.
        XCTAssertEqual(try XCTUnwrap(report.average(forColumnID: "predicted")), 5.5, accuracy: 0.0001)
        // Effort is free text and has no average at all.
        XCTAssertNil(report.average(forColumnID: "effort"))
        XCTAssertNil(report.average(forColumnID: "no-such-column"))
    }

    // MARK: - Identity inference [I]

    /// Only when W4 gave us no level column. `"Theory of Knowledge"` has no
    /// level and must not acquire one.
    func testLevelIsInferredFromTheSubjectOnlyWhenThereIsNoLevelColumn() {
        let inferred = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Final</th></tr>
              <tr><td>Biology HL</td><td>7</td></tr>
              <tr><td>Visual Arts (SL)</td><td>5</td></tr>
              <tr><td>Theory of Knowledge</td><td>B</td></tr>
            </table>
            """))

        XCTAssertEqual(inferred.rows.map(\.subject), ["Biology", "Visual Arts", "Theory of Knowledge"])
        XCTAssertEqual(inferred.rows.map(\.level), ["HL", "SL", nil])

        // With a level column present the subject text is left exactly as W4
        // wrote it.
        let explicit = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Level</th><th>Final</th></tr>
              <tr><td>Biology HL</td><td>SL</td><td>7</td></tr>
            </table>
            """))

        XCTAssertEqual(explicit.rows[0].subject, "Biology HL")
        XCTAssertEqual(explicit.rows[0].level, "SL")
    }

    func testRowIDsStayUniqueWhenSubjectsRepeat() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><th>Subject</th><th>Final</th></tr>
              <tr><td>English A</td><td>6</td></tr>
              <tr><td>English A</td><td>5</td></tr>
            </table>
            """))

        XCTAssertEqual(report.rows.map(\.id), ["english-a", "english-a-2"])
        XCTAssertEqual(report.rows[0].cell(for: "final")?.value, "6")
        XCTAssertEqual(report.rows[1].cell(for: "final")?.value, "5")
    }

    // MARK: - Selector ladder (bug B13) [I]

    /// B13: the grades page is `table.grades`. A generic Yii grid sitting higher
    /// up the page must not win, even though `table.items` is what the Android
    /// parser looks for.
    func testTableGradesBeatsAGenericGridOnTheSamePage() {
        let report = W4GradeParser.parse(Self.page("""
            <div class="grid-view" id="yw0">
              <table class="items">
                <tr><th>Announcement</th><th>Posted</th></tr>
                <tr><td>Report cards are published</td><td>14-Aug-2026</td></tr>
              </table>
            </div>
            <table class="grades">
              <tr><th>Subject</th><th>Final</th></tr>
              <tr><td>Mathematics</td><td>7</td></tr>
            </table>
            """))

        XCTAssertEqual(report.rows.map(\.subject), ["Mathematics"])
        XCTAssertEqual(report.columns.map(\.id), ["final"])
    }

    func testLadderFallsBackToTheGenericGridAndThenToABareTable() {
        let grid = W4GradeParser.parse(Self.page("""
            <div class="grid-view" id="yw0">
              <table class="items">
                <thead><tr><th>Subject</th><th>Final</th></tr></thead>
                <tbody><tr class="odd"><td>Mathematics</td><td>7</td></tr></tbody>
              </table>
            </div>
            """))
        XCTAssertEqual(grid.rows.map(\.subject), ["Mathematics"])
        XCTAssertEqual(grid.rows[0].cell(for: "final")?.value, "7")

        let bare = W4GradeParser.parse(Self.page("""
            <table>
              <tr><th>Subject</th><th>Final</th></tr>
              <tr><td>Mathematics</td><td>7</td></tr>
            </table>
            """))
        XCTAssertEqual(bare.rows.map(\.subject), ["Mathematics"])
        XCTAssertEqual(bare.rows[0].cell(for: "final")?.value, "7")
    }

    // MARK: - Degrading, never crashing [I]

    /// Bug B9: `td.empty`, `span.empty` and the bare sentence are all Yii empty
    /// states. The columns survive an empty table; the rows do not exist.
    func testEmptyGridYieldsNoRowsAndKeepsTheColumns() {
        let report = W4GradeParser.parse(Self.page("""
            <div class="grid-view" id="yw0">
              <table class="grades">
                <thead><tr><th>Subject</th><th>Final</th></tr></thead>
                <tbody><tr><td colspan="2" class="empty"><span class="empty">No results found.</span></td></tr></tbody>
              </table>
            </div>
            """))

        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.columns.map(\.id), ["final"])
        XCTAssertEqual(report.emptyMessage, "No results found.")
    }

    func testAlertsAreSurfacedInDocumentOrder() {
        let report = W4GradeParser.parse(Self.page("""
            <div class="errorMessage">Your grades have not been published yet.</div>
            <div class="warning">Predicted grades are provisional.</div>
            <table class="grades">
              <tr><th>Subject</th><th>Final</th></tr>
              <tr><td>Mathematics</td><td>7</td></tr>
            </table>
            """))

        XCTAssertEqual(report.alerts, [
            "Your grades have not been published yet.",
            "Predicted grades are provisional."
        ])
        XCTAssertEqual(report.rows.count, 1, "an alert does not suppress the table")
    }

    /// The non-grid empty state: `#content_inner > div.note` (**[V]** pattern,
    /// from the captured applicants page).
    func testPageWithoutATableDegradesToAnEmptyReport() {
        let report = W4GradeParser.parse(Self.page("""
            <h2>My Grades</h2>
            <div class="note">No grades found</div>
            """))

        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertTrue(report.columns.isEmpty)
        XCTAssertEqual(report.alerts, ["No grades found"])
        XCTAssertEqual(report.emptyMessage, "No grades found")
        XCTAssertEqual(report.title, "My Grades")
    }

    /// Without a header there is no column identity, and guessing one is exactly
    /// the bug this parser exists to avoid — so it reports nothing rather than
    /// something wrong.
    func testTableWithoutAHeaderRowReportsNoRows() {
        let report = W4GradeParser.parse(Self.page("""
            <table class="grades">
              <tr><td>Mathematics</td><td>7</td></tr>
            </table>
            """))

        XCTAssertTrue(report.columns.isEmpty)
        XCTAssertTrue(report.rows.isEmpty)
    }

    func testEmptyAndGarbageInputDoNotThrow() {
        let empty = W4GradeParser.parse("")
        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertTrue(empty.columns.isEmpty)
        XCTAssertTrue(empty.alerts.isEmpty)

        let garbage = W4GradeParser.parse("<html><body><p>nope</p><table><tr><td>")
        XCTAssertTrue(garbage.rows.isEmpty)

        let notHTML = W4GradeParser.parse("{\"error\":\"session expired\"}")
        XCTAssertTrue(notHTML.rows.isEmpty)
    }

    // MARK: - Slugs

    func testSlugIsLowercaseASCIIAndHyphenated() {
        XCTAssertEqual(W4GradeParser.slug("Predicted"), "predicted")
        XCTAssertEqual(W4GradeParser.slug("Term 2 grade"), "term-2-grade")
        XCTAssertEqual(W4GradeParser.slug("  Final / awarded  "), "final-awarded")
        XCTAssertEqual(W4GradeParser.slug("Français"), "francais")
        XCTAssertEqual(W4GradeParser.slug("—"), "")
    }

    // MARK: - Model plumbing

    /// The parser is pure: it never stamps a report with the time it ran. Only
    /// whoever fetched the page may do that.
    func testParserNeverStampsAClockAndStampingIsCallersWork() throws {
        let report = W4GradeParser.parse(try fixture("grades"))
        XCTAssertNil(report.fetchedAt, "a parser that reads a clock is not a pure function")

        let stamped = report.withFetchedAt(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(stamped.fetchedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(stamped.rows, report.rows)
        XCTAssertEqual(stamped.columns, report.columns)

        XCTAssertNil(W4GradesReport.empty.defaultColumnID)
        XCTAssertTrue(W4GradesReport.empty.isEmpty)
    }

    // MARK: - Effort vocabulary

    func testEffortGradeClassMapping() {
        XCTAssertEqual(W4EffortGrade(className: "effort-grade-meets-expectations"), .meets)
        XCTAssertEqual(W4EffortGrade(className: "effort-grade-almost-meets-expectations"), .almostMeets)
        XCTAssertEqual(W4EffortGrade(className: "effort-grade-does-not-meet-expectations"), .doesNotMeet)
        XCTAssertNil(W4EffortGrade(className: "anticipated"))
        XCTAssertNil(W4EffortGrade(className: "table_1_bg"))
        XCTAssertNil(W4EffortGrade(className: ""))

        // Wording drift degrades to the nearest level rather than to nil.
        XCTAssertEqual(W4EffortGrade(className: "effort-grade-meets-expectation"), .meets)
        XCTAssertEqual(W4EffortGrade(className: "EFFORT-GRADE-ALMOST-MEETS"), .almostMeets)

        XCTAssertEqual(W4EffortGrade.meets.displayName, "Meets expectations")
        XCTAssertGreaterThan(W4EffortGrade.meets.rank, W4EffortGrade.almostMeets.rank)
        XCTAssertGreaterThan(W4EffortGrade.almostMeets.rank, W4EffortGrade.doesNotMeet.rank)
    }
}
