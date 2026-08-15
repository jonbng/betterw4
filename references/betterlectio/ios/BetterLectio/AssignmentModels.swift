//
//  AssignmentModels.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Assignment Models

struct Assignment: Codable, Identifiable, Equatable {
    let id: String          // exerciseid from URL
    let week: String
    let hold: String        // class name e.g. "1x DA"
    let holdElementId: String // e.g. "HE73009188994"
    let title: String
    let deadline: String    // raw string "3/12-2025 14:00"
    let deadlineDate: Date?
    let studentTime: String // e.g. "1,00"
    let status: AssignmentStatus
    let absence: String?    // e.g. "0 %" or nil
    let awaiting: String?   // "Lærer" or "Elev" or nil
    let assignmentNote: String?
    let grade: String?
    let gradeNote: String?  // e.g. "8,5p"
    let studentNote: String?
    let detailURL: String   // relative URL to ElevAflevering.aspx

    /// Elev timer (hours) from the list column — same semantics as lectioDartWrapper `AssignmentRef.studentTime`.
    var elevTimerHours: Double {
        let normalized = studentTime
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }
}

enum AssignmentStatus: String, Codable {
    case submitted      // "Afleveret"
    case waiting        // "Venter"
    case notSubmitted   // "Ikke afleveret"
    case missing        // "Mangler"

    var displayName: String {
        switch self {
        case .submitted: return "Afleveret"
        case .waiting: return "Venter"
        case .notSubmitted: return "Ikke afleveret"
        case .missing: return "Mangler"
        }
    }
}

// MARK: - Assignment Detail Models

struct AssignmentDetail: Codable, Equatable {
    let title: String
    let hold: String
    let gradeScale: String?
    let teacher: String
    let studentTime: String
    let deadline: String
    let assignmentNote: String?
    let inDescription: Bool
    let descriptionFiles: [AssignmentFile]
    let submissions: [AssignmentSubmission]
    let awaiting: String?
    let status: String?
    let completed: Bool
    let grade: String?
    let gradeNote: String?
    let studentNote: String?
}

struct AssignmentFile: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let url: String
}

struct AssignmentSubmission: Codable, Equatable, Identifiable {
    let id: String
    let timestamp: String
    let user: String
    let comment: String?
    let document: AssignmentFile?
}

// MARK: - Homework Overview Models

/// A single homework entry from the homework overview page (lektier overblik)
struct HomeworkEntry: Codable, Identifiable, Equatable {
    let id: String              // absId from activity link
    let date: Date
    let displayDate: String     // e.g. "fr 13/3"
    let hold: String            // e.g. "1x MA"
    let title: String?          // activity title from tooltip e.g. "Stemmeretten"
    let teacher: String?
    let room: String?
    let status: EventStatus
    let note: String?           // teacher note (if any)
    let items: [HomeworkItem]
}

/// Individual homework task within a HomeworkEntry
struct HomeworkItem: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let url: String?            // link to activity page anchor, or file URL
}
