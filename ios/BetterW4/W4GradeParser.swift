//
//  W4GradeParser.swift
//  BetterW4
//
//  Parses the W4 grades table: `academics/grades/grades` and
//  `academics/grades/grades/sat` **[V routes]**.
//  Spec: docs/spec/parsers.md §10, docs/spec/features.md §1.6,
//  W4_PORT_PLAN.md D-14 and OQ-12, bug register B9 / B13.
//
//  EVIDENCE — read this before changing a selector.
//
//  VERIFIED [V] — from W4's own `css/main.css`, which the server serves and we
//  have on disk. A stylesheet rule is server-authored proof that the element it
//  styles exists:
//
//      table.grades th.anticipated                  { … }
//      table.grades tr.table_1_bg td.anticipated    { … }
//      table.grades tr.table_2_bg td.anticipated    { … }
//      .effort-grade-meets-expectations             { … }
//      .effort-grade-almost-meets-expectations      { … }
//      .effort-grade-does-not-meet-expectations     { … }
//
//  So three things are certain: the grades page is `table.grades` (**bug B13** —
//  the Android parser looks for the generic `table.items` and would find the
//  wrong table or none at all), an *anticipated* (predicted) column exists and
//  is marked by a class rather than by its label, and effort grades are a
//  separate three-level vocabulary carried by a CSS class (**D-14**).
//
//  UNKNOWN [U] — **the grades page itself has never been captured.** Not one
//  header row, not one data row. Which columns exist, what they are called, in
//  what order they appear and whether the level and teacher live in their own
//  columns are all guesses. `BetterW4Tests/Fixtures/W4/grades.html` is
//  hand-written: it verifies this parser, not W4.
//
//  THE PROPERTY THAT MATTERS MOST. Columns are derived from the server's own
//  header row and keyed by a slug of the header text; every value is then read
//  by its **grid index**, taken from that same header row. A column that is
//  missing, renamed, re-ordered or unknown therefore drops out of the report —
//  it can never shift a value into a neighbouring column. Nothing in this file
//  is positional beyond "the header says index 4 is Final, so index 4 of every
//  row is Final", and `colspan` is honoured so a spanned cell cannot slide its
//  neighbours either.
//
//  W4 HAS NO WEIGHTS. `Vægt` was Lectio's; D-14 replaces it with `effort`.
//  IB grades are 1–7, but predicted and effort columns are free text, so no cell
//  value is ever coerced to a number here.
//
//  The parser is pure and synchronous: `(String) -> W4GradesReport`. No network,
//  no storage, no clock, no singletons, no force-unwraps — and it never throws.
//  Every failure degrades to an empty report plus a logged warning.
//

import Foundation
import SwiftSoup

enum W4GradeParser {

    // MARK: - Public API

    /// Parses one grades page.
    ///
    /// Returns an empty report — never throws, never crashes — when the HTML
    /// does not parse, when no table can be found, or when the table carries no
    /// header row to key its columns by. Page alerts are surfaced even then, so
    /// the UI can show W4's own explanation instead of a blank screen.
    nonisolated static func parse(_ html: String) -> W4GradesReport {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("the HTML did not parse")
            return .empty
        }

        let scope = contentScope(of: document)
        let alerts = alertMessages(in: scope)
        let title = pageTitle(in: scope)

        guard let table = gradesTable(in: scope) else {
            let note = pageNote(in: scope)
            warn("no grades table found" + (note.map { " (the page says: \($0))" } ?? ""))
            return W4GradesReport(title: title, alerts: alerts, emptyMessage: note)
        }

        let allRows = tableRows(of: table)
        guard let header = headerRow(in: allRows) else {
            // No header means no column identity, and guessing one is exactly
            // the bug this parser exists to avoid (OQ-12: degrade instead).
            warn("the grades table has no header row — refusing to guess a column order")
            return W4GradesReport(
                title: title,
                alerts: alerts,
                emptyMessage: pageNote(in: scope)
            )
        }

        let bodyRows = allRows.filter { row in
            row !== header && hasDataCell(row)
        }

        let layout = columnLayout(header: header, bodyRows: bodyRows)
        if layout.valueColumns.isEmpty {
            warn("the grades table header produced no value columns")
        }

        var rows: [W4GradeRow] = []
        var usedRowIDs = Set<String>()
        var emptyMessage: String?

        for (offset, element) in bodyRows.enumerated() {
            let cells = indexedCells(of: element)
            if let message = emptyRowMessage(row: element, cells: cells) {
                // Bug B9: `td.empty`, `span.empty` and the bare sentence are all
                // Yii empty states, and only the first is checked by the Kotlin
                // parsers.
                if emptyMessage == nil { emptyMessage = message }
                continue
            }
            guard let row = gradeRow(
                cells: cells,
                layout: layout,
                position: offset,
                usedIDs: &usedRowIDs
            ) else { continue }
            rows.append(row)
        }

        if rows.isEmpty && emptyMessage == nil {
            emptyMessage = pageNote(in: scope)
        }

        return W4GradesReport(
            title: title,
            columns: layout.valueColumns.map { $0.column },
            rows: rows,
            alerts: alerts,
            emptyMessage: emptyMessage
        )
    }

    // MARK: - Locating the table (bug B13)

    /// Selector ladder from OQ-12, most specific first. `table.grades` is the
    /// real grades table **[V]**; `.grid-view table.items` is the generic Yii
    /// grid the Android port assumes; a bare `table` is the last resort.
    private static let tableSelectors = [
        "table.grades",
        "div.grid-view table.items",
        "table.items",
        "table"
    ]

    /// The first selector that matches anything at all wins — `table.grades` is
    /// never passed over in favour of a generic grid elsewhere on the page, even
    /// when the grades table happens to be empty this term (bug B13). Within one
    /// selector, a table that has data rows beats one that does not.
    private static func gradesTable(in scope: Element) -> Element? {
        for selector in tableSelectors {
            let tables = select(scope, selector)
            guard !tables.isEmpty else { continue }
            return tables.first(where: { hasDataRows($0) }) ?? tables.first
        }
        return nil
    }

    private static func hasDataRows(_ table: Element) -> Bool {
        tableRows(of: table).contains(where: { hasDataCell($0) })
    }

    private static func hasDataCell(_ row: Element) -> Bool {
        indexedCells(of: row).contains(where: { $0.element.tagName().lowercased() == "td" })
    }

    // MARK: - Column layout

    /// Where each field lives in the grid, resolved once from the header row.
    private struct Layout {
        var subjectIndex: Int?
        var levelIndex: Int?
        var teacherIndex: Int?
        /// Value columns paired with the grid index they were declared at, in
        /// the server's own order.
        var valueColumns: [(index: Int, column: W4GradeColumn)] = []
    }

    /// Header labels that identify a row rather than carry a grade. Checked
    /// teacher-first so that a "Teacher name" header is not eaten as the
    /// subject, and only the *first* match of each role is consumed — a second
    /// "Level"-ish header stays a normal value column.
    private static let teacherLabels = ["teacher", "staff", "instructor"]
    private static let levelLabels = ["level", "hl/sl", "hl / sl", "group"]
    private static let subjectLabels = ["subject", "course", "class", "name"]

    private static func columnLayout(header: Element, bodyRows: [Element]) -> Layout {
        var layout = Layout()
        var pending: [(index: Int, label: String, element: Element)] = []

        for (index, element) in indexedCells(of: header) {
            let label = collapsedText(of: element)
            let lowered = label.lowercased()

            if layout.teacherIndex == nil, contains(lowered, teacherLabels) {
                layout.teacherIndex = index
            } else if layout.levelIndex == nil, contains(lowered, levelLabels) {
                layout.levelIndex = index
            } else if layout.subjectIndex == nil, contains(lowered, subjectLabels) {
                layout.subjectIndex = index
            } else {
                pending.append((index, label, element))
            }
        }

        // **[I]** No grades capture exists, so a header that names no subject
        // column at all is possible. The first column is the pragmatic fallback
        // — it is where every Yii grid puts the row's name — but it is logged,
        // because it is a guess and the log line is how we find out we were
        // wrong.
        if layout.subjectIndex == nil, let first = pending.first {
            warn("no subject-like header (\"\(first.label)\" is first) — using the first column as the subject")
            layout.subjectIndex = first.index
            pending.removeFirst()
        }

        let bodyCells = bodyRows.map { cellMap(of: $0) }
        var usedIDs = Set<String>()

        for item in pending {
            let base = slug(item.label)
            // An unlabelled column still gets a stable key so its values are
            // carried rather than dropped, and so nothing shifts left into it.
            let candidate = base.isEmpty ? "column-\(item.index + 1)" : base
            let id = usedIDs.contains(candidate) ? unique(candidate, in: usedIDs) : candidate
            usedIDs.insert(id)

            // `th.anticipated` is the [V] marker; `td.anticipated` on this
            // column's own cells is the same class applied one row down, so it
            // is accepted as a fallback.
            let markedInBody = bodyCells.contains(where: { cells in
                guard let cell = cells[item.index] else { return false }
                return hasClass(cell, "anticipated")
            })
            let isAnticipated = hasClass(item.element, "anticipated") || markedInBody

            layout.valueColumns.append((
                index: item.index,
                column: W4GradeColumn(id: id, label: item.label, isAnticipated: isAnticipated)
            ))
        }

        return layout
    }

    // MARK: - Rows

    private static func gradeRow(
        cells: [(index: Int, element: Element)],
        layout: Layout,
        position: Int,
        usedIDs: inout Set<String>
    ) -> W4GradeRow? {
        let byIndex = Dictionary(cells.map { ($0.index, $0.element) }, uniquingKeysWith: { first, _ in first })

        func text(at index: Int?) -> String? {
            guard let index, let element = byIndex[index] else { return nil }
            let value = collapsedText(of: element)
            return value.isEmpty ? nil : value
        }

        var subject = text(at: layout.subjectIndex) ?? ""
        var level = text(at: layout.levelIndex)
        let teacher = text(at: layout.teacherIndex)

        // Values are read at the grid index the header declared, so a missing or
        // re-ordered column simply has no entry here.
        var values: [String: W4GradeCell] = [:]
        for (index, column) in layout.valueColumns {
            guard let element = byIndex[index], let cell = gradeCell(element) else { continue }
            values[column.id] = cell
        }

        // A row with neither a name nor a single grade is grid furniture.
        guard !subject.isEmpty || !values.isEmpty else { return nil }

        // **[I]** Only when W4 gave us no level column: IB subjects are commonly
        // written "Biology HL", and the trailing token is the level rather than
        // part of the subject name. Never applied when a level column exists.
        if level == nil {
            let split = splitLevel(from: subject)
            if let inferred = split.level {
                subject = split.subject
                level = inferred
            }
        }

        let base = rowIDBase(subject: subject, level: level, position: position)
        let id = usedIDs.contains(base) ? unique(base, in: usedIDs) : base
        usedIDs.insert(id)

        return W4GradeRow(
            id: id,
            subject: subject,
            level: level,
            teacher: teacher,
            cells: values
        )
    }

    /// One grade cell.
    ///
    /// Returns `nil` — never a cell whose value is `""` or `"–"` — when W4
    /// printed a dash or nothing at all, because "no grade" is the absence of a
    /// value, not an empty one. A cell that carries an effort class but no text
    /// survives: the effort grade is the payload there.
    private static func gradeCell(_ element: Element) -> W4GradeCell? {
        let effort = effortGrade(in: element)
        let value = collapsedText(of: element)

        if isNoGrade(value) {
            guard let effort else { return nil }
            return W4GradeCell(value: "", effort: effort)
        }
        return W4GradeCell(value: value, effort: effort)
    }

    /// Every dash W4 might use, plus the empty cell. An en dash (U+2013) and a
    /// plain hyphen are the two documented spellings; the rest are here so a
    /// copy-pasted em dash or minus sign cannot become a "grade".
    private static let dashScalars = CharacterSet(charactersIn:
        "-\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}\u{FE58}\u{FE63}\u{FF0D}"
    )

    private static func isNoGrade(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.unicodeScalars.allSatisfy { scalar in
            dashScalars.contains(scalar) || CharacterSet.whitespaces.contains(scalar)
        }
    }

    /// `.effort-grade-*` on the cell itself or on anything inside it **[V]**.
    private static func effortGrade(in element: Element) -> W4EffortGrade? {
        if let own = effortGrade(fromClassesOf: element) { return own }
        for descendant in select(element, "*") {
            if let found = effortGrade(fromClassesOf: descendant) { return found }
        }
        return nil
    }

    private static func effortGrade(fromClassesOf element: Element) -> W4EffortGrade? {
        for name in classNames(of: element) {
            if let effort = W4EffortGrade(className: name) { return effort }
        }
        return nil
    }

    // MARK: - Identity helpers

    /// `"Biology HL"` → `("Biology", "HL")`. Returns the input unchanged when
    /// there is no trailing IB level, or when the level *is* the whole string.
    private static func splitLevel(from subject: String) -> (subject: String, level: String?) {
        guard let range = subject.range(
            of: #"[\s,]*[\(\[]?\s*\b(?:HL|SL)\b\s*[\)\]]?\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return (subject, nil) }

        let level = String(subject[range]).uppercased().filter { $0.isLetter }
        let remainder = String(subject[subject.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",-–—:;"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !remainder.isEmpty, level == "HL" || level == "SL" else { return (subject, nil) }
        return (remainder, level)
    }

    private static func rowIDBase(subject: String, level: String?, position: Int) -> String {
        let joined = [subject, level ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let base = slug(joined)
        return base.isEmpty ? "row-\(position + 1)" : base
    }

    // MARK: - Slugs

    /// Lowercase, ASCII, hyphen-separated. `"Predicted grade"` → `"predicted-grade"`.
    ///
    /// Deliberately dumb: there is no dictionary of expected column names,
    /// because we have never seen the real ones. Whatever W4 calls a column
    /// becomes its key, so an unknown column is usable rather than dropped.
    static func slug(_ raw: String) -> String {
        let folded = raw
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        return folded
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Duplicate header labels keep the existing `-2`, `-3`… behaviour so that
    /// two columns both called "Term" do not collapse into one.
    private static func unique(_ base: String, in used: Set<String>) -> String {
        var suffix = 2
        var candidate = "\(base)-\(suffix)"
        while used.contains(candidate) {
            suffix += 1
            candidate = "\(base)-\(suffix)"
        }
        return candidate
    }

    // MARK: - Page furniture

    /// Every page parser starts at `#content_inner` (parsers.md §0.3).
    private static func contentScope(of document: Document) -> Element {
        for selector in ["#content_inner", "#content_main", "#content"] {
            if let element = select(document, selector).first { return element }
        }
        return document.body() ?? document
    }

    private static func pageTitle(in scope: Element) -> String? {
        for element in select(scope, "h1, h2, h3") {
            let text = collapsedText(of: element)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// W4's own alert containers **[V]** (`css/main.css`). Innermost wins, so a
    /// wrapper that merely contains an alert is not reported twice.
    private static let alertSelector = "div.errorMessage, div.error, div.warning, div.note"

    private static func alertMessages(in scope: Element) -> [String] {
        var seen = Set<String>()
        var messages: [String] = []
        for element in select(scope, alertSelector) {
            let nested = select(element, alertSelector).contains(where: { $0 !== element })
            guard !nested else { continue }
            let text = collapsedText(of: element)
            guard !text.isEmpty, !seen.contains(text) else { continue }
            seen.insert(text)
            messages.append(text)
        }
        return messages
    }

    /// The non-grid empty state: `#content_inner > div.note` ("No users found"
    /// is the **[V]** example, from `Current applicants at UWCRCN.html`).
    private static func pageNote(in scope: Element) -> String? {
        let direct = scope.children().array().first { element in
            element.tagName().lowercased() == "div" && hasClass(element, "note")
        }
        if let direct {
            let text = collapsedText(of: direct)
            return text.isEmpty ? nil : text
        }
        guard let anywhere = select(scope, "div.note").first else { return nil }
        let text = collapsedText(of: anywhere)
        return text.isEmpty ? nil : text
    }

    /// Bug B9: `td.empty`, `span.empty` **and** the bare "No results found."
    /// sentence are all Yii 1 empty states.
    private static func emptyRowMessage(
        row: Element,
        cells: [(index: Int, element: Element)]
    ) -> String? {
        if let marker = select(row, "td.empty, span.empty").first {
            let message = collapsedText(of: marker)
            return message.isEmpty ? "No results found." : message
        }
        guard cells.count <= 2 else { return nil }
        let joined = cells
            .map { collapsedText(of: $0.element) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = joined
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard normalized.hasPrefix("no "), normalized.hasSuffix("found") else { return nil }
        return joined
    }

    // MARK: - Grid structure

    /// The rows of *this* table only: a nested table inside a cell must not
    /// contribute rows, which a plain `select("tr")` would let it do.
    private static func tableRows(of table: Element) -> [Element] {
        var rows: [Element] = []
        for child in table.children().array() {
            switch child.tagName().lowercased() {
            case "thead", "tbody", "tfoot":
                rows += child.children().array().filter { $0.tagName().lowercased() == "tr" }
            case "tr":
                rows.append(child)
            default:
                continue
            }
        }
        return rows
    }

    private static func headerRow(in rows: [Element]) -> Element? {
        // A real `<thead>` wins, whatever it is made of.
        for row in rows where row.parent()?.tagName().lowercased() == "thead" {
            if !indexedCells(of: row).isEmpty { return row }
        }
        // Otherwise the first row made only of `<th>` is the header — Yii 1
        // happily emits a grid with no `<thead>` at all.
        for row in rows {
            let cells = indexedCells(of: row)
            guard !cells.isEmpty else { continue }
            let tags = cells.map { $0.element.tagName().lowercased() }
            if tags.contains("th") && !tags.contains("td") { return row }
        }
        return nil
    }

    /// A row's own cells paired with their **grid** position, so that a
    /// `colspan` cannot slide its neighbours out of alignment. A spanned cell is
    /// registered at its first position only; `rowspan` is not modelled, and no
    /// capture suggests the grades table uses it.
    private static func indexedCells(of row: Element) -> [(index: Int, element: Element)] {
        var cells: [(index: Int, element: Element)] = []
        var index = 0
        for child in row.children().array() {
            let tag = child.tagName().lowercased()
            guard tag == "td" || tag == "th" else { continue }
            cells.append((index: index, element: child))
            index += max(1, Int(attribute(child, "colspan")) ?? 1)
        }
        return cells
    }

    private static func cellMap(of row: Element) -> [Int: Element] {
        Dictionary(
            indexedCells(of: row).map { ($0.index, $0.element) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Small helpers

    private static func select(_ element: Element, _ query: String) -> [Element] {
        ((try? element.select(query)) ?? Elements()).array()
    }

    /// Extracted text with runs of whitespace (including the `&nbsp;` W4 puts in
    /// empty cells) collapsed to single spaces.
    private static func collapsedText(of element: Element) -> String {
        let raw = (try? element.text()) ?? ""
        return raw
            .split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ element: Element, _ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }

    private static func classNames(of element: Element) -> [String] {
        attribute(element, "class")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)
    }

    private static func hasClass(_ element: Element, _ name: String) -> Bool {
        classNames(of: element).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func contains(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func warn(_ message: String) {
        #if DEBUG
        print("⚠️ [W4GradeParser] \(message)")
        #endif
    }
}
