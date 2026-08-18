//
//  W4MailerParser.swift
//  BetterW4
//
//  Parses the two W4 mailer grids: `index.php?r=mailer/inbox` and `index.php?r=mailer/archive`.
//
//  EVIDENCE — read this before changing a selector.
//  No mailer page has ever been captured (`docs/spec/parsers.md` §7, plan OQ-4). What we know:
//    * the container is a Yii 1 `CGridView`; `.grid-view table.items`, `a.sort_asc`/`a.sort_desc`
//      are [V] because W4 itself styles them in `css/main.css`;
//    * `thead` / `tbody` / `div.summary` / `div.pager` / `ul.yiiPager` are [I] from the framework;
//    * the column *labels* are [I] from README §6 — inbox "Received | From | Subject",
//      archive "Send date | Subject | Attachment";
//    * everything else — the unread marker, the attachment marker, the id in the row link — is
//      [U]. Never seen.
//  Therefore this parser never throws out of its entry points, never force-unwraps, never
//  assumes a node exists, and reports *why* it produced no rows so the UI can tell "your inbox
//  is empty" apart from "W4's markup moved".
//
//  Rules that are not negotiable:
//    * Columns are matched on **header text**, never on position. A missing column yields nil,
//      it never shifts the ones after it.
//    * The message id is the `id=` in the row's link. Never `tr[id]` (Yii does not emit one) and
//      never a hash of the subject (bug B18: hashes collide, which silently merges two emails).
//    * Empty states are `td.empty`, `span.empty`, the literal "No results found." and `div.note`
//      (bug B9 — the Kotlin port only checks the first).
//    * Pagination is detected and surfaced, never silently ignored (bug B10).
//
//  Pure and synchronous by design (plan D-30): no I/O, no actor hops, no singletons.
//

import Foundation
import OSLog
import SwiftSoup

private let w4MailerLog = Logger(subsystem: "dk.jonathanb.w4", category: "W4MailerParser")

// MARK: - Mailer list parser

nonisolated enum W4MailerParser {

    // MARK: Entry points

    /// Parses one page of a mailer grid.
    ///
    /// Always returns a page. A parse failure becomes `.unrecognised` with zero messages and a
    /// logged warning — the caller decides how to present that.
    static func parseList(_ html: String, folder: MailFolder) -> MailListPage {
        do {
            let doc = try SwiftSoup.parse(html)
            let root = try W4MailHTML.contentRoot(doc)
            let pagination = try paginationState(in: root)
            let hasNote = try hasEmptyNote(in: root)

            guard let table = try grid(in: root) else {
                if hasNote {
                    w4MailerLog.info("mailer/\(folder.id, privacy: .public): no grid, div.note empty state")
                    return .empty(folder: folder, outcome: .emptyState, pagination: pagination)
                }
                w4MailerLog.warning("mailer/\(folder.id, privacy: .public): no grid-view table found")
                return .empty(folder: folder, outcome: .unrecognised, pagination: pagination)
            }

            let columns = try columnLayout(of: table)
            if folder.expectsSenderColumn && !columns.hasSenderColumn {
                w4MailerLog.info("mailer/\(folder.id, privacy: .public): no sender column in header; from will be nil")
            }

            var messages: [MailMessage] = []
            var dataRowCount = 0
            var sawEmptyMarker = false

            for row in try dataRows(of: table) {
                if try isEmptyMarkerRow(row) {
                    sawEmptyMarker = true
                    continue
                }
                dataRowCount += 1
                if let message = try message(from: row, folder: folder, columns: columns) {
                    messages.append(message)
                }
            }

            if !messages.isEmpty {
                return MailListPage(
                    folder: folder,
                    messages: messages,
                    pagination: pagination,
                    outcome: .parsed,
                    columns: columns
                )
            }

            // No rows. Distinguish "W4 says it is empty" from "we could not read the rows".
            if sawEmptyMarker || hasNote || dataRowCount == 0 {
                return .empty(
                    folder: folder,
                    outcome: .emptyState,
                    pagination: pagination,
                    columns: columns
                )
            }

            w4MailerLog.warning(
                "mailer/\(folder.id, privacy: .public): \(dataRowCount) row(s) present but none parseable"
            )
            return .empty(
                folder: folder,
                outcome: .unrecognised,
                pagination: pagination,
                columns: columns
            )
        } catch {
            w4MailerLog.warning(
                "mailer/\(folder.id, privacy: .public): parse failed: \(String(describing: error), privacy: .public)"
            )
            return .empty(folder: folder, outcome: .unrecognised)
        }
    }

    /// Pagination state of a mailer grid, or `nil` when the page shows no pager and no summary.
    static func parsePagination(_ html: String) -> MailPagination? {
        do {
            let doc = try SwiftSoup.parse(html)
            return try paginationState(in: try W4MailHTML.contentRoot(doc))
        } catch {
            w4MailerLog.warning("mailer pager parse failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Grid discovery

    /// Selector ladder, most specific first. The bare `table` rung only ever runs inside
    /// `#content_inner`, so it cannot pick up the page-chrome layout tables.
    private static let gridLadder = [
        "div.grid-view table.items",
        "table.items",
        "div.grid-view table",
        "table"
    ]

    private static func grid(in root: Element) throws -> Element? {
        for query in gridLadder {
            for candidate in try root.select(query).array() {
                if try isPlausibleGrid(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func isPlausibleGrid(_ table: Element) throws -> Bool {
        guard try !table.select("tr").isEmpty() else { return false }
        return try !table.select("th").isEmpty() || !table.select("td").isEmpty()
    }

    // MARK: Header-driven columns

    /// Exact header labels per role, tried before any substring match.
    private static let exactLabels: [(role: MailColumnRole, labels: [String])] = [
        (.subject, ["subject", "title"]),
        (.from, ["from", "sender"]),
        (.attachment, ["attachment", "attachments", "file", "files"]),
        (.received, ["received", "send date", "sent date", "sent", "date", "received date"])
    ]

    /// Substring fallbacks, only applied to roles and columns still unclaimed.
    private static let looseLabels: [(role: MailColumnRole, needles: [String])] = [
        (.subject, ["subject", "title"]),
        (.from, ["from", "sender"]),
        (.attachment, ["attachment", "file"]),
        (.received, ["received", "send date", "sent date", "date", "sent"])
    ]

    private enum MailColumnRole: CaseIterable {
        case received, from, subject, attachment
    }

    static func columnLayout(of table: Element) throws -> MailColumnLayout {
        var headers: [String] = []
        for cell in try headerCells(of: table) {
            headers.append(W4MailHTML.normalizedHeader(try cell.text()))
        }
        guard !headers.isEmpty else { return .none }

        var claimedRoles: Set<MailColumnRole> = []
        var claimedColumns: Set<Int> = []
        var resolved: [MailColumnRole: Int] = [:]

        for (role, labels) in exactLabels {
            guard !claimedRoles.contains(role) else { continue }
            for (index, header) in headers.enumerated()
            where !claimedColumns.contains(index) && labels.contains(header) {
                resolved[role] = index
                claimedRoles.insert(role)
                claimedColumns.insert(index)
                break
            }
        }

        for (role, needles) in looseLabels {
            guard !claimedRoles.contains(role) else { continue }
            for (index, header) in headers.enumerated() where !claimedColumns.contains(index) {
                guard needles.contains(where: { header.contains($0) }) else { continue }
                resolved[role] = index
                claimedRoles.insert(role)
                claimedColumns.insert(index)
                break
            }
        }

        return MailColumnLayout(
            headers: headers,
            received: resolved[.received],
            from: resolved[.from],
            subject: resolved[.subject],
            attachment: resolved[.attachment]
        )
    }

    private static func headerCells(of table: Element) throws -> [Element] {
        let inThead = try table.select("thead th").array()
        if !inThead.isEmpty { return inThead }
        // No `thead`: the first row that carries `th` cells is the header row.
        for row in try table.select("tr").array() {
            let cells = row.children().array().filter { $0.tagName().lowercased() == "th" }
            if !cells.isEmpty { return cells }
        }
        return []
    }

    // MARK: Rows

    private static func dataRows(of table: Element) throws -> [Element] {
        let body = try table.select("tbody tr").array()
        let candidates = body.isEmpty ? try table.select("tr").array() : body
        return candidates.filter { row in
            let children = row.children().array()
            let hasHeaderCells = children.contains { $0.tagName().lowercased() == "th" }
            let hasDataCells = children.contains { $0.tagName().lowercased() == "td" }
            return hasDataCells || !hasHeaderCells
        }
    }

    /// Bug B9: Yii 1 emits `td.empty`, and from 1.1.14 an inner `span.empty` carrying
    /// "No results found." Check all three, not just the first.
    private static func isEmptyMarkerRow(_ row: Element) throws -> Bool {
        if try !row.select("td.empty").isEmpty() { return true }
        if try !row.select("span.empty").isEmpty() { return true }
        let text = W4MailHTML.normalizedText(try row.text()).lowercased()
        return text.hasPrefix("no results found")
    }

    /// Bug B9's non-grid half: `#content_inner > div.note` ("No users found" is the captured
    /// example, in `references/pages/Current applicants at UWCRCN.html`).
    private static func hasEmptyNote(in root: Element) throws -> Bool {
        try !root.select("div.note").isEmpty()
    }

    private static func message(
        from row: Element,
        folder: MailFolder,
        columns: MailColumnLayout
    ) throws -> MailMessage? {
        let cells = row.children().array().filter { $0.tagName().lowercased() == "td" }
        guard !cells.isEmpty else { return nil }

        let anchors = try row.select("a[href]").array()
        let idAnchor = try firstAnchorCarryingMessageID(anchors)

        guard let subjectCell = try subjectCell(cells: cells, columns: columns, idAnchor: idAnchor) else {
            return nil
        }

        var subjectAnchor = try subjectCell.select("a[href]").first()
        if subjectAnchor == nil { subjectAnchor = idAnchor }

        var subject = ""
        if let subjectAnchor {
            subject = W4MailHTML.normalizedText(try subjectAnchor.text())
        }
        if subject.isEmpty {
            subject = W4MailHTML.normalizedText(try subjectCell.text())
        }
        guard !subject.isEmpty else { return nil }

        var href: String?
        if let anchor = subjectAnchor ?? idAnchor {
            href = try anchor.attr("href").nilIfEmpty
        }
        let dateText = try text(of: cells, at: columns.received)

        // Bug B18: never `tr[id]`, never a hash of the subject alone.
        var id = W4MailHTML.messageID(inHref: href ?? "")
        if id == nil, let idAnchor {
            id = W4MailHTML.messageID(inHref: try idAnchor.attr("href"))
        }
        if id == nil {
            id = W4MailHTML.fallbackID(
                folderID: folder.id,
                subject: subject,
                date: dateText ?? ""
            )
            w4MailerLog.info("mailer/\(folder.id, privacy: .public): row has no id= link; using a content hash")
        }
        guard let resolvedID = id else { return nil }

        let from = try text(of: cells, at: columns.from)
        let receivedAt = dateText.flatMap(parseTimestamp)
        if dateText != nil, receivedAt == nil {
            w4MailerLog.debug("mailer/\(folder.id, privacy: .public): unparseable date column value")
        }

        return MailMessage(
            id: resolvedID,
            folderID: folder.id,
            subject: subject,
            from: from,
            receivedAt: receivedAt,
            isUnread: try isUnread(row),
            hasAttachment: try hasAttachment(row: row, cells: cells, columns: columns),
            href: href
        )
    }

    /// The subject cell, in order of confidence: the header-matched column, then the cell that
    /// actually holds the `mailer/view` link, then the last cell with text. Never "index 2".
    private static func subjectCell(
        cells: [Element],
        columns: MailColumnLayout,
        idAnchor: Element?
    ) throws -> Element? {
        if let index = columns.subject, cells.indices.contains(index) {
            return cells[index]
        }
        if let idAnchor {
            for cell in cells {
                let descendants = try cell.select("a[href]").array()
                if descendants.contains(where: { $0 === idAnchor }) { return cell }
            }
        }
        for cell in cells.reversed() {
            if !W4MailHTML.normalizedText(try cell.text()).isEmpty { return cell }
        }
        return nil
    }

    private static func firstAnchorCarryingMessageID(_ anchors: [Element]) throws -> Element? {
        for anchor in anchors {
            let href = try anchor.attr("href")
            if W4MailHTML.messageID(inHref: href) != nil { return anchor }
        }
        for anchor in anchors {
            if try anchor.attr("href").contains("mailer/view") { return anchor }
        }
        return anchors.first
    }

    private static func text(of cells: [Element], at index: Int?) throws -> String? {
        guard let index, cells.indices.contains(index) else { return nil }
        return W4MailHTML.normalizedText(try cells[index].text()).nilIfEmpty
    }

    /// UNVERIFIED [U]: no unread marker has been captured. Accept the two shapes a Yii grid
    /// could plausibly use and default to read.
    private static func isUnread(_ row: Element) throws -> Bool {
        if row.hasClass("unread") { return true }
        return try !row.select(".unread").isEmpty()
    }

    /// UNVERIFIED [U]: no attachment marker has been captured. Prefer the header-matched
    /// column; only sniff the row when the grid has no attachment column at all.
    private static func hasAttachment(
        row: Element,
        cells: [Element],
        columns: MailColumnLayout
    ) throws -> Bool {
        if let index = columns.attachment, cells.indices.contains(index) {
            let cell = cells[index]
            if try !cell.select("a[href]").isEmpty() { return true }
            if try !cell.select("img").isEmpty() { return true }
            return !W4MailHTML.normalizedText(try cell.text()).isEmpty
        }
        for anchor in try row.select("a[href]").array() {
            let href = try anchor.attr("href").lowercased()
            if href.contains("attachment") || href.contains("download") { return true }
        }
        for image in try row.select("img").array() {
            let alt = try image.attr("alt").lowercased()
            let src = try image.attr("src").lowercased()
            if alt.contains("attach") || src.contains("attach") { return true }
        }
        return false
    }

    /// Single call site for the shared date helper (plan D-11: Oslo, en_GB_POSIX, fixed
    /// Gregorian calendar). `W4Dates` is owned by the timetable item; this parser only uses it.
    private static func parseTimestamp(_ raw: String) -> Date? {
        W4Dates.parseDateTime(raw)
    }

    // MARK: Pagination (bug B10)

    private static func paginationState(in root: Element) throws -> MailPagination? {
        let pager = try root.select("div.pager").first() ?? root.select("ul.yiiPager").first()
        let summary = W4MailHTML.normalizedText(
            try root.select("div.summary").first()?.text() ?? ""
        ).nilIfEmpty
        let summaryImpliesMore = summary.map(summarySaysMorePages) ?? false

        guard let pager else {
            guard let summary else { return nil }
            return MailPagination(hasMorePages: summaryImpliesMore, summary: summary)
        }

        var pageNumbers: [Int] = []
        var currentPage: Int?
        var nextPageHref: String?
        var hasUsableLink = false

        for anchor in try pager.select("a[href]").array() {
            let container = anchor.parent()
            let isHidden = container?.hasClass("hidden") ?? false
            let isDisabled = container?.hasClass("disabled") ?? false
            let isSelected = container?.hasClass("selected") ?? false
            if !isHidden && !isDisabled && !isSelected {
                hasUsableLink = true
            }
            if container?.hasClass("next") == true, !isHidden, !isDisabled, nextPageHref == nil {
                nextPageHref = try anchor.attr("href").nilIfEmpty
            }
            if let number = Int(W4MailHTML.normalizedText(try anchor.text())) {
                pageNumbers.append(number)
                if isSelected { currentPage = number }
            }
        }

        for item in try pager.select("li.selected").array() where currentPage == nil {
            currentPage = Int(W4MailHTML.normalizedText(try item.text()))
        }

        return MailPagination(
            hasMorePages: hasUsableLink || summaryImpliesMore,
            currentPage: currentPage,
            pageCount: pageNumbers.max(),
            summary: summary,
            nextPageHref: nextPageHref
        )
    }

    /// "Displaying 1-20 of 37 results." ⇒ there is more mail than this page. Regex over the
    /// *text* of an already-extracted node, which is allowed; markup is never regexed.
    private static func summarySaysMorePages(_ summary: String) -> Bool {
        let lowered = summary.lowercased()
        let pattern = "displaying\\s+(\\d+)\\s*[-–—]\\s*(\\d+)\\s+of\\s+(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
        guard let match = regex.firstMatch(in: lowered, options: [], range: range),
              match.numberOfRanges > 3,
              let lastRange = Range(match.range(at: 2), in: lowered),
              let totalRange = Range(match.range(at: 3), in: lowered),
              let last = Int(lowered[lastRange]),
              let total = Int(lowered[totalRange]) else { return false }
        return last < total
    }
}

// MARK: - Shared mailer HTML helpers

/// Small pieces shared by `W4MailerParser` and `W4MailDetailParser`.
nonisolated enum W4MailHTML {

    /// Every W4 page body lives in `#content_inner` (verified chrome, `parsers.md` §0.3).
    /// Falling back to `#content_main` and then the document keeps a fragment response — the
    /// kind an AJAX route returns — parseable.
    static func contentRoot(_ doc: Document) throws -> Element {
        if let inner = try doc.select("#content_inner").first() { return inner }
        if let main = try doc.select("#content_main").first() { return main }
        if let body = doc.body() { return body }
        return doc
    }

    /// Lowercased, `&nbsp;`-flattened, whitespace-collapsed, trailing-colon-stripped.
    static func normalizedHeader(_ raw: String) -> String {
        var value = normalizedText(raw).lowercased()
        while value.hasSuffix(":") {
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    /// Collapses every run of whitespace (including the `&nbsp;` W4 sprinkles through its
    /// grids) to a single space and trims.
    static func normalizedText(_ raw: String) -> String {
        let flattened = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        let parts = flattened.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return parts.joined(separator: " ")
    }

    /// The `id=` query value out of a row or attachment link.
    ///
    /// Deliberately anchored on `?`, `&` or the entity-escaped `&amp;` so that `folder_id=27`,
    /// `uwc_id=nc26abcd` and `page_id=3` cannot masquerade as a message id.
    static func messageID(inHref href: String) -> String? {
        numericQueryValue(in: href, key: "id")
    }

    /// `?key=123` / `&key=123` / `&amp;key=123`, first match wins.
    static func numericQueryValue(in href: String, key: String) -> String? {
        guard !href.isEmpty else { return nil }
        let needle = "\(key)="
        var searchStart = href.startIndex
        while let found = href.range(of: needle, range: searchStart..<href.endIndex) {
            searchStart = found.upperBound
            guard isQueryKeyBoundary(href, before: found.lowerBound) else { continue }
            var digits = ""
            var index = found.upperBound
            while index < href.endIndex, href[index].isNumber {
                digits.append(href[index])
                index = href.index(after: index)
            }
            if !digits.isEmpty { return digits }
        }
        return nil
    }

    /// True when the character run before `index` ends a query separator — `?`, `&`, or the
    /// escaped `&amp;`. Anything else (a `_` as in `folder_id`, a letter) is not a boundary.
    private static func isQueryKeyBoundary(_ href: String, before index: String.Index) -> Bool {
        guard index > href.startIndex else { return false }
        let previous = href[href.index(before: index)]
        if previous == "?" || previous == "&" { return true }
        // `&amp;id=` — five characters back must be `&amp;`.
        guard let start = href.index(index, offsetBy: -5, limitedBy: href.startIndex) else { return false }
        return href[start..<index] == "&amp;"
    }

    /// Stable, collision-resistant substitute id for a row whose link carries no `id=`.
    ///
    /// FNV-1a over folder + subject + date. Bug B18: `subject.hashCode()` is neither stable
    /// across launches nor collision-resistant, and two colliding rows become one message.
    /// The `w4mail-` prefix keeps a substituted id visibly distinct from a real W4 id.
    static func fallbackID(folderID: String, subject: String, date: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(folderID)\u{1}\(subject)\u{1}\(date)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return "w4mail-" + String(hash, radix: 16)
    }
}
