//
//  GradeParser.swift
//  BetterLectio
//

import Foundation
import SwiftSoup

/// Parser for grades and report cards from Lectio.
enum GradeParser {
    
    // MARK: - Parse Grades Report

    /// Parses the Lectio grades report page (`grades/grade_report.aspx`) into structured data.
    static func parseGradesReport(from html: String) throws -> GradesReport {
        let doc = try SwiftSoup.parse(html)

        let writtenAlertText = try doc
            .select("#s_m_Content_Content_karakterView_WrittenProtokolBlockLit")
            .first()?
            .text()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let oralAlertText = try doc
            .select("#s_m_Content_Content_karakterView_OralProtokolBlockLit")
            .first()?
            .text()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blockedWrittenProtocolTerm = extractBlockedTerm(fromAlert: writtenAlertText)
        let blockedOralProtocolTerm = extractBlockedTerm(fromAlert: oralAlertText)

        var grades: [GradeEntry] = []
        var columns: [GradeColumn] = []

        if let gradesTable = try doc.select("#s_m_Content_Content_karakterView_KarakterGV").first() {
            let rows = try gradesTable.select("tr")

            if let headerRow = rows.first(where: { row in
                guard let count = try? desktopHeaderCells(row).count else { return false }
                return count > 2
            }) {
                let headerCells = try desktopHeaderCells(headerRow)
                var usedKeys: Set<String> = []
                for header in headerCells.dropFirst(2) {
                    let label = try header.text().collapsingWhitespace
                    guard !label.isEmpty else { continue }
                    let baseKey = canonicalColumnKey(label)
                    var key = baseKey
                    var suffix = 2
                    while usedKeys.contains(key) {
                        key = "\(baseKey)-\(suffix)"
                        suffix += 1
                    }
                    usedKeys.insert(key)
                    columns.append(GradeColumn(key: key, label: label))
                }
            }

            for row in rows {
                // Parse desktop cells only to avoid duplicate mobile table markup.
                let cells = try desktopDataCells(row)
                guard !columns.isEmpty, cells.count >= 2 + columns.count else { continue }

                let holdSpan = try cells[0].select("span[data-lectiocontextcard]").first()
                let hold = try holdSpan?.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let holdElementId = try holdSpan?.attr("data-lectiocontextcard")

                let subject = try cells[1].text().trimmingCharacters(in: .whitespacesAndNewlines)

                var gradeCells: [String: GradeCellValue] = [:]
                for (offset, column) in columns.enumerated() {
                    if let value = try parseGradeCell(cells[offset + 2]) {
                        gradeCells[column.key] = value
                    }
                }

                let idBase = [hold, subject].joined(separator: "|")
                let id = idBase.isEmpty ? UUID().uuidString : idBase

                grades.append(GradeEntry(
                    id: id,
                    hold: hold,
                    holdElementId: holdElementId,
                    subject: subject,
                    grades: gradeCells
                ))
            }
        }

        var notes: [GradeNoteEntry] = []

        if let notesTable = try doc.select("#s_m_Content_Content_karakterView_KarakterNoterGrid").first() {
            let rows = try notesTable.select("tr")

            for row in rows {
                let cells = try row.select("td.OnlyDesktop")
                guard cells.count >= 5 else { continue }

                let hold = try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let gradeType = try cells[1].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let grade = try cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let insertedAt = try cells[3].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let note = try cells[4].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

                let idBase = [hold, gradeType, insertedAt].joined(separator: "|")
                let id = idBase.isEmpty ? UUID().uuidString : idBase

                notes.append(GradeNoteEntry(
                    id: id,
                    hold: hold,
                    gradeType: gradeType,
                    grade: grade,
                    insertedAt: insertedAt,
                    note: note
                ))
            }
        }

        print("📊 Parsed grades report: \(grades.count) grade rows, \(notes.count) note rows")

        return GradesReport(
            blockedWrittenProtocolTerm: blockedWrittenProtocolTerm,
            blockedOralProtocolTerm: blockedOralProtocolTerm,
            columns: columns,
            grades: grades,
            notes: notes
        )
    }

    /// Stable keys let selection survive refreshes while the original label is
    /// retained for display. Unknown future columns deliberately remain usable.
    static func canonicalColumnKey(_ raw: String) -> String {
        let value = raw.collapsingWhitespace.lowercased()
        if value.range(of: #"^1\.?\s*standpunkt"#, options: .regularExpression) != nil { return "1.standpunkt" }
        if value.range(of: #"^2\.?\s*standpunkt"#, options: .regularExpression) != nil { return "2.standpunkt" }
        if value.range(of: #"^3\.?\s*standpunkt"#, options: .regularExpression) != nil { return "3.standpunkt" }
        if value.contains("afsluttende") { return "afsluttende" }
        if value.contains("intern") { return "intern prøve" }
        if value.contains("eksamen") { return "eksamenskarakter" }
        if value.hasPrefix("årskarakter") || value.hasPrefix("aarskarakter") { return "årskarakter" }

        let slug = value
            .replacingOccurrences(
                of: "[^a-z0-9æøå]+",
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? raw : slug
    }

    private static func desktopHeaderCells(_ row: Element) throws -> Elements {
        let desktop = try row.select("th.OnlyDesktop, td.OnlyDesktop")
        if desktop.count > 0 { return desktop }
        return try row.select("th")
    }

    private static func desktopDataCells(_ row: Element) throws -> Elements {
        let desktop = try row.select("td.OnlyDesktop")
        if desktop.count > 0 { return desktop }
        return try row.select("td:not(.OnlyMobile)")
    }

    private static func parseGradeCell(_ cell: Element) throws -> GradeCellValue? {
        let valueText = try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valueText.isEmpty else { return nil }

        // Metadata usually lives on an inner div title attribute, e.g.:
        // XPRSFag: 4682C Musik\nKilde: Karakter\nVægt: 1
        let title = try cell.select("div[title]").first()?.attr("title")

        let xprsSubject = extractMetadataValue(prefix: "XPRSFag:", from: title)
        let source = extractMetadataValue(prefix: "Kilde:", from: title)
        let weightRaw = extractMetadataValue(prefix: "Vægt:", from: title)
        let weight = weightRaw
            .map { $0.replacingOccurrences(of: ",", with: ".") }
            .flatMap(Double.init)

        return GradeCellValue(
            value: valueText,
            xprsSubject: xprsSubject,
            source: source,
            weight: weight
        )
    }

    private static func extractMetadataValue(prefix: String, from title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        guard let line = title.components(separatedBy: .newlines)
            .lazy
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix(prefix) })
        else { return nil }
        let value = line.replacingOccurrences(of: prefix, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractBlockedTerm(fromAlert text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard let range = text.range(of: #"terminen\s+\"([^\"]+)\""#, options: .regularExpression) else {
            return nil
        }

        let matched = String(text[range])
        let stripped = matched
            .replacingOccurrences(of: "terminen", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}

private extension String {
    var collapsingWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
