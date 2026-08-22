//
//  W4AbsenceParser.swift
//  BetterW4
//
//  W4 attendance: the two Home meters and the AC / EA registration lists.
//  Spec: docs/spec/parsers.md §8, docs/spec/features.md §1.5, W4_PORT_PLAN.md D-13.
//
//  EVIDENCE — read this before changing a selector.
//
//  VERIFIED [V] (references/pages/UWCRCN W4.html:239-249, sanitized into
//  BetterW4Tests/Fixtures/W4/home.html):
//      <div id="absences">
//        <div id="academic-absences"><h3>Academics Attendance Meter</h3>
//          <p>You have 0 absences and 0 latenesses so far<br>
//             <a href="…r=people/students/absences">View attendance</a></p></div>
//        <div id="ea-absences">… r=people/students/eaabsences …</div>
//      </div>
//  `homepage.css` also names `#advisor-absences`, `#mentor-absences`,
//  `#admin-absences` and `#staff-absences` — meters a student never sees. They
//  must not crash us and must never be mistaken for the two student meters,
//  which is why the fallback below is keyed on the *link route*, not on prose
//  position.
//
//  VERIFIED [V] (W4's own css/tables.css): `tr.prearranged_1`,
//  `tr.prearranged_2`, `tr.medical_1`, `tr.medical_2` — so the category of a row
//  is carried by the row class, not only by a "Type" column (bug B14).
//
//  VERIFIED [V]: live empty list and term-time week/register pages are stored in
//  BetterW4Tests/Fixtures/W4. Filled rows remain defensive and header-driven.
//
//  D-13: meter counts come from the meter prose ONLY. Nothing here ever counts
//  rows to produce a meter, and the raw `status` string is carried through
//  verbatim next to the `AttendanceKind` enum.
//
//  The parser is pure and synchronous: `(String) -> Model`, no I/O, no actors,
//  no singletons.
//

import Foundation
import SwiftSoup

enum W4AbsenceParser {

    // MARK: - Home meters [V]

    /// Both Home meters. Either side is `nil` when W4 did not render it — which
    /// is a different fact from a meter that reads zero.
    ///
    /// The real capture reads `0 absences and 0 latenesses` on both meters, so
    /// the zero case is the only one that has ever been observed.
    nonisolated static func parseHomeMeters(_ html: String) -> AttendanceMeters {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("home meters: the HTML did not parse")
            return .empty
        }
        let parsed = meters(in: document)
        if parsed.isEmpty {
            warn("home meters: neither #academic-absences nor #ea-absences produced a count")
        }
        return parsed
    }

    /// One meter, from either the Home page or a list page that repeats it.
    nonisolated static func parseMeter(_ html: String, source: AttendanceSource) -> AttendanceMeter? {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("meter (\(source.rawValue)): the HTML did not parse")
            return nil
        }
        if let meter = meters(in: document).meter(for: source) {
            return meter
        }
        // Only trust a bare sentence when the page is *not* the Home page: Home
        // carries two of them and an unscoped match would report the academic
        // numbers for Extra Academics.
        guard !hasHomeMeterMarkup(document) else { return nil }
        return meterProse(in: text(of: contentInner(of: document) ?? document))
    }

    // MARK: - List page

    /// One page of `people/students/absences` or `people/students/eaabsences`.
    ///
    /// Degrades to an empty list plus a warning for every failure: unparseable
    /// HTML, no grid, no header, an empty-state row. It never throws.
    nonisolated static func parseList(_ html: String, source: AttendanceSource) -> AttendanceList {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("list (\(source.rawValue)): the HTML did not parse")
            return .empty(source: source)
        }

        let scope = contentInner(of: document) ?? document
        let meter = listMeter(document: document, scope: scope, source: source)

        guard let table = gridTable(in: scope) else {
            let note = pageNote(in: scope)
            let suffix = note == nil ? "" : " (the page says: " + (note ?? "") + ")"
            warn("list (\(source.rawValue)): no grid table found" + suffix)
            return .empty(source: source, meter: meter, message: note)
        }

        let header = headerRow(of: table)
        var columns = header.map { columnMap(fromHeader: cellElements(of: $0)) } ?? Columns()
        if columns.isEmpty {
            warn("list (\(source.rawValue)): no usable header row; falling back to the inferred column order")
            columns = .inferred
        }

        var records: [AttendanceRecord] = []
        var occurrences: [String: Int] = [:]
        var emptyMessage: String?

        for row in bodyRows(of: table, header: header) {
            let cells = cellElements(of: row)
            if let message = emptyRowMessage(row: row, cells: cells) {
                if emptyMessage == nil { emptyMessage = message }
                continue
            }
            guard let record = record(
                row: row,
                cells: cells,
                columns: columns,
                source: source,
                occurrences: &occurrences
            ) else { continue }
            records.append(record)
        }

        if records.isEmpty && emptyMessage == nil {
            emptyMessage = pageNote(in: scope)
        }

        return AttendanceList(
            source: source,
            meter: meter,
            records: records,
            hasMorePages: hasMorePages(in: scope),
            emptyMessage: emptyMessage
        )
    }

    nonisolated static func parseRegistrationForm(_ html: String) -> AbsenceRegistrationForm {
        guard let document = try? SwiftSoup.parse(html),
              let form = try? document.select("form#student-absence-form, form.main").first() else {
            return AbsenceRegistrationForm()
        }
        let parsed = YiiForm.parse(form: form)
        let inputs = (try? form.select("input"))?.array() ?? []
        func input(named name: String) -> Element? {
            inputs.first { ((try? $0.attr("name")) ?? "") == name }
        }
        let date = input(named: "StudentAbsenceForm[absence_date]")
            .flatMap { try? $0.attr("value") } ?? ""
        let reason = input(named: "StudentAbsenceForm[reason]")
            .flatMap { try? $0.attr("value") } ?? ""
        let slots = inputs.compactMap { input -> AbsenceRegistrationSlot? in
            guard ((try? input.attr("name")) ?? "") == "StudentAbsenceForm[absences][]" else {
                return nil
            }
            let id = (try? input.attr("id")) ?? UUID().uuidString
            let label = (try? form.select("label[for=\(id)]").first()?.text()) ?? ""
            return AbsenceRegistrationSlot(
                id: id,
                value: (try? input.attr("value")) ?? "",
                label: label,
                disabled: input.hasAttr("disabled"),
                checked: input.hasAttr("checked")
            )
        }
        let emptyDayMessage = (try? form.select("p").array())?
            .first { ((try? $0.text()) ?? "").localizedCaseInsensitiveContains("don't have any class") }
            .flatMap { try? $0.text() }
        return AbsenceRegistrationForm(
            action: parsed.action,
            fields: parsed.fields.map { AbsenceRegistrationField(name: $0.name, value: $0.value) },
            submitButtons: parsed.submitButtons.map { AbsenceRegistrationField(name: $0.name, value: $0.value) },
            date: date,
            slots: slots,
            reason: reason,
            emptyDayMessage: emptyDayMessage
        )
    }

    nonisolated static func parseSubmissionError(_ html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html) else { return "W4 returned unreadable HTML." }
        let candidates = (try? document.select(
            ".errorMessage, div.error, .errorSummary li, .flash-error, .alert-error"
        ).array()) ?? []
        for element in candidates {
            let style = ((try? element.attr("style")) ?? "").lowercased()
            let message = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty, !style.contains("display:none") { return message }
        }
        return nil
    }

    // MARK: - Meters

    private static func meters(in document: Document) -> AttendanceMeters {
        AttendanceMeters(
            academic: meter(in: document, elementID: "academic-absences", source: .academics),
            extraAcademic: meter(in: document, elementID: "ea-absences", source: .extraAcademics)
        )
    }

    private static func meter(
        in document: Document,
        elementID: String,
        source: AttendanceSource
    ) -> AttendanceMeter? {
        // 1. The verified id.
        if let element = select(document, "#\(elementID)").first,
           let meter = meterProse(in: text(of: element)) {
            return meter
        }

        // 2. Fallback: find this source's "View attendance" link and walk up to
        //    the tightest ancestor whose text carries the sentence. Keyed on the
        //    route so a staff/advisor meter can never be misread as a student's.
        for link in select(document, "a[href]") {
            let href = attribute(link, "href")
            guard let route = W4Routes.route(ofURLString: href),
                  source.owns(route: route) else { continue }
            for ancestor in link.parents().array().prefix(4) {
                if let meter = meterProse(in: text(of: ancestor)) { return meter }
            }
        }
        return nil
    }

    private static func listMeter(
        document: Document,
        scope: Element,
        source: AttendanceSource
    ) -> AttendanceMeter? {
        if hasHomeMeterMarkup(document) {
            return meters(in: document).meter(for: source)
        }
        return meterProse(in: text(of: scope))
    }

    private static func hasHomeMeterMarkup(_ document: Document) -> Bool {
        !select(document, "#absences, #academic-absences, #ea-absences").isEmpty
    }

    /// `You have 3 absences and 1 lateness so far` → `(3, 1)`.
    ///
    /// The trailing "so far" is not required: the two counts are the payload,
    /// and W4 writes both the singular ("1 lateness") and the plural
    /// ("0 latenesses") forms.
    private static func meterProse(in text: String) -> AttendanceMeter? {
        let pattern = #"You\s+have\s+(\d+)\s+absences?\s+and\s+(\d+)\s+latenesse?s?"#
        guard let groups = matchGroups(pattern, in: text), groups.count >= 2,
              let absences = Int(groups[0]),
              let latenesses = Int(groups[1]) else { return nil }
        return AttendanceMeter(absences: absences, latenesses: latenesses)
    }

    // MARK: - Rows

    private static func record(
        row: Element,
        cells: [Element],
        columns: Columns,
        source: AttendanceSource,
        occurrences: inout [String: Int]
    ) -> AttendanceRecord? {
        let values = cells.map { text(of: $0) }
        func value(_ index: Int?) -> String? {
            guard let index, index >= 0, index < values.count else { return nil }
            return blankToNil(values[index])
        }

        let displayDate = value(columns.date) ?? ""
        let period = value(columns.period)
        let subject = value(columns.subject)
        let typeLabel = value(columns.type)
        let statusLabel = value(columns.status)
        let teacher = value(columns.teacher)
        let note = value(columns.note)
        let addedBy = value(columns.addedBy)
        let studentWas = value(columns.studentWas)

        // A row that carries nothing we can show is not a registration.
        if displayDate.isEmpty, period == nil, subject == nil,
           typeLabel == nil, statusLabel == nil, note == nil {
            return nil
        }

        // Bug B14: the row class wins over the "Type" column, because
        // `tr.prearranged_*` / `tr.medical_*` are the [V] evidence and a row
        // typed "Absence" can still be styled `prearranged_1`.
        var kind = AttendanceKind.kind(forRowClasses: classNames(of: row))
            ?? AttendanceKind.kind(forLabel: typeLabel)
            ?? AttendanceKind.kind(forLabel: studentWas)
        if kind == nil && columns.type == nil {
            kind = AttendanceKind.kind(forLabel: statusLabel)
        }

        let resolved = kind ?? .unknown
        // D-13: the raw string is rendered verbatim; the enum is only for
        // grouping. Prefer the status column, fall back to the type column.
        let status = statusLabel ?? typeLabel ?? ""

        // Bug B19: identity is a content hash, never the row index.
        let base = AttendanceRecord.identity(
            source: source,
            dateRaw: displayDate,
            period: period,
            subject: subject,
            kind: resolved
        )
        let seen = occurrences[base] ?? 0
        occurrences[base] = seen + 1
        let id = seen == 0 ? base : AttendanceRecord.identity(
            source: source,
            dateRaw: displayDate,
            period: period,
            subject: subject,
            kind: resolved,
            occurrence: seen
        )

        return AttendanceRecord(
            id: id,
            source: source,
            date: parseDate(displayDate),
            displayDate: displayDate,
            period: period,
            subject: subject,
            kind: resolved,
            status: status,
            teacher: teacher ?? addedBy,
            note: note,
            addedBy: addedBy,
            studentWas: studentWas
        )
    }

    // MARK: - Grid structure

    /// Column indexes, matched on header *text* so an unknown or re-ordered
    /// column can never shift a value into the wrong field.
    private struct Columns {
        var date: Int?
        var period: Int?
        var subject: Int?
        var type: Int?
        var status: Int?
        var teacher: Int?
        var note: Int?
        var addedBy: Int?
        var studentWas: Int?
        var isHeaderDriven: Bool = true

        var isEmpty: Bool {
            date == nil && period == nil && subject == nil
                && type == nil && status == nil && teacher == nil && note == nil
                && addedBy == nil && studentWas == nil
        }

        /// The **[I]** column order parsers.md §8 documents for this page:
        /// `Date | Period | Class/Activity | Type | Status | Comment`. Used only
        /// when the grid has no header at all.
        static let inferred = Columns(
            date: 0,
            period: 1,
            subject: 2,
            type: 3,
            status: 4,
            note: 5,
            isHeaderDriven: false
        )
    }

    private static func columnMap(fromHeader cells: [Element]) -> Columns {
        var columns = Columns()
        for (index, cell) in cells.enumerated() {
            let label = text(of: cell).lowercased()
            guard !label.isEmpty else { continue }

            if columns.date == nil, contains(label, ["date", "when"]) {
                columns.date = index
            } else if columns.addedBy == nil, contains(label, ["added"]) {
                columns.addedBy = index
            } else if columns.studentWas == nil, label.contains("student was") {
                columns.studentWas = index
            } else if columns.type == nil, contains(label, ["type", "kind"]) {
                columns.type = index
            } else if columns.status == nil, contains(label, ["status"]) {
                columns.status = index
            } else if columns.teacher == nil, contains(label, ["teacher", "staff"]) {
                columns.teacher = index
            } else if columns.period == nil, contains(label, ["period", "slot", "lesson"]) {
                columns.period = index
            } else if columns.subject == nil,
                      contains(label, ["class", "subject", "course", "activity", "group"]) {
                columns.subject = index
            } else if columns.note == nil,
                      contains(label, ["comment", "note", "remark", "reason", "explanation"]) {
                columns.note = index
            }
        }
        return columns
    }

    /// Selector ladder for the grid (parsers.md §0.4). The first table that has
    /// at least one data row wins; failing that, the first table of the first
    /// selector that matched anything at all.
    private static let tableSelectors = [
        "div.grid-view table.items",
        "table.items",
        "table.grid-view",
        "table"
    ]

    private static func gridTable(in scope: Element) -> Element? {
        var firstMatch: Element?
        for selector in tableSelectors {
            let tables = select(scope, selector)
            if firstMatch == nil { firstMatch = tables.first }
            if let withRows = tables.first(where: { hasDataRows($0) }) { return withRows }
        }
        return firstMatch
    }

    private static func hasDataRows(_ table: Element) -> Bool {
        select(table, "tr").contains { !select($0, "td").isEmpty }
    }

    private static func headerRow(of table: Element) -> Element? {
        if let row = select(table, "thead tr").first, !cellElements(of: row).isEmpty {
            return row
        }
        // No <thead>: the first row made only of <th> cells is the header.
        for row in select(table, "tr") where !select(row, "th").isEmpty && select(row, "td").isEmpty {
            return row
        }
        return nil
    }

    private static func bodyRows(of table: Element, header: Element?) -> [Element] {
        var rows = select(table, "tbody > tr")
        if rows.isEmpty { rows = select(table, "tr") }
        return rows.filter { row in
            if let header, row === header { return false }
            return !select(row, "td").isEmpty
        }
    }

    private static func cellElements(of row: Element) -> [Element] {
        row.children().array().filter { element in
            let tag = element.tagName().lowercased()
            return tag == "td" || tag == "th"
        }
    }

    /// Bug B9: Yii 1 empty states are `td.empty`, `span.empty` **and** the bare
    /// sentence "No results found."; only checking `td.empty` misses two of them.
    private static func emptyRowMessage(row: Element, cells: [Element]) -> String? {
        if let marker = select(row, "td.empty, span.empty").first {
            let message = text(of: marker)
            return message.isEmpty ? "No results found." : message
        }
        guard cells.count <= 2 else { return nil }
        let joined = cells.map { text(of: $0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = joined.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard normalized.hasPrefix("no "), normalized.hasSuffix("found") else { return nil }
        return joined
    }

    /// The non-grid empty state: `#content_inner > div.note` ("No users found"
    /// is the **[V]** example, from `Current applicants at UWCRCN.html`).
    private static func pageNote(in scope: Element) -> String? {
        let direct = scope.children().array().first { element in
            element.tagName().lowercased() == "div" && element.hasClass("note")
        }
        if let direct { return blankToNil(text(of: direct)) }
        guard let anywhere = select(scope, "div.note").first else { return nil }
        return blankToNil(text(of: anywhere))
    }

    /// Bug B10: nobody paginates. Detect the pager (or a summary that says there
    /// is more) so the UI can say "more on W4" instead of silently truncating.
    private static func hasMorePages(in scope: Element) -> Bool {
        let links = select(scope, "div.pager a[href], ul.yiiPager a[href]").filter { link in
            let href = attribute(link, "href").trimmingCharacters(in: .whitespacesAndNewlines)
            return !href.isEmpty && href != "#"
        }
        if !links.isEmpty { return true }

        if let summary = select(scope, "div.summary").first,
           let groups = matchGroups(#"(\d+)\s*-\s*(\d+)\s+of\s+(\d+)"#, in: text(of: summary)),
           groups.count >= 3,
           let shownEnd = Int(groups[1]),
           let total = Int(groups[2]) {
            return shownEnd < total
        }
        return false
    }

    // MARK: - Dates

    /// Every date is Oslo wall clock (D-11 / parsers.md §0.1). `W4Dates` is the
    /// single shared parser — this file must never build a `DateFormatter`.
    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = W4Dates.parseDate(trimmed) { return date }
        // A cell may carry more than the date ("13-Aug-2026 (P5)"); pull the
        // date token out of the extracted text and try again. Regex over text,
        // never over markup.
        if let token = firstDateToken(in: trimmed), token != trimmed,
           let date = W4Dates.parseDate(token) {
            return date
        }
        return nil
    }

    private static func firstDateToken(in text: String) -> String? {
        let patterns = [
            #"\d{1,2}-[A-Za-z]{3,}-\d{2,4}"#,
            #"\d{4}-\d{1,2}-\d{1,2}"#,
            #"\d{1,2}/\d{1,2}/\d{2,4}"#
        ]
        for pattern in patterns {
            if let match = matchGroups("(\(pattern))", in: text)?.first { return match }
        }
        return nil
    }

    // MARK: - Small helpers

    private static func contentInner(of document: Document) -> Element? {
        select(document, "#content_inner").first
    }

    private static func select(_ element: Element, _ query: String) -> [Element] {
        ((try? element.select(query)) ?? Elements()).array()
    }

    private static func text(of element: Element) -> String {
        ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ element: Element, _ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }

    private static func classNames(of element: Element) -> [String] {
        attribute(element, "class")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map(String.init)
    }

    private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func contains(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func matchGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[groupRange]))
        }
        return groups
    }

    private static func warn(_ message: String) {
        print("⚠️ [W4AbsenceParser] \(message)")
    }
}
