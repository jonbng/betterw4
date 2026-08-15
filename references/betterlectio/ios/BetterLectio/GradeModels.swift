//
//  GradeModels.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Grades Models

struct GradesReport: Codable, Equatable {
    let blockedWrittenProtocolTerm: String?
    let blockedOralProtocolTerm: String?
    let columns: [GradeColumn]
    let grades: [GradeEntry]
    let notes: [GradeNoteEntry]
}

/// A grade column parsed from the live Lectio table header. Schools and terms
/// do not all expose the same columns, so identity cannot safely be positional.
struct GradeColumn: Codable, Equatable, Hashable, Identifiable {
    let key: String
    let label: String

    var id: String { key }

    var shortLabel: String {
        switch key {
        case "1.standpunkt": return "1.SP"
        case "2.standpunkt": return "2.SP"
        case "3.standpunkt": return "3.SP"
        case "afsluttende": return "Afsl."
        case "intern prøve": return "Int."
        case "årskarakter": return "Års"
        case "eksamenskarakter": return "Eks."
        default:
            let compact = label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            return compact.count <= 10 ? compact : String(compact.prefix(9)) + "…"
        }
    }
}

struct GradeEntry: Codable, Equatable, Identifiable {
    let id: String
    let hold: String
    let holdElementId: String?
    let subject: String
    let grades: [String: GradeCellValue]

    func cell(for columnKey: String) -> GradeCellValue? {
        grades[columnKey]
    }
}

struct GradeCellValue: Codable, Equatable {
    let value: String
    let xprsSubject: String?
    let source: String?
    let weight: Double?
}

struct GradeNoteEntry: Codable, Equatable, Identifiable {
    let id: String
    let hold: String
    let gradeType: String
    let grade: String
    let insertedAt: String
    let note: String?
}
