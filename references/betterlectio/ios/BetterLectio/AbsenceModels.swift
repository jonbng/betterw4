//
//  AbsenceModels.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Absence Models

/// Total absence summary showing overall percentages
struct AbsenceSummary: Codable, Equatable {
    let regularAbsence: String      // "Almindeligt fravær" percentage
    let writtenAbsence: String      // "Skriftligt fravær" percentage
}

/// Represents a single absence entry (missing reason or registered)
struct AbsenceEntry: Codable, Identifiable, Equatable {
    let id: String                  // Stable list identity (registration id when available)
    let registrationId: String?     // id used by fravaer_aarsag.aspx
    let activityId: String?         // absid/aftaleid for the related schedule activity
    let date: Date                  // The date of the absence activity
    let week: String
    let activity: String            // e.g. "fr 10/10 1. modul - 1g4 da • Ka • 24"
    let activityDetails: ActivityDetails?
    let absencePercent: String      // e.g. "100%", "75%"
    let absenceType: String         // e.g. "Fravær", "Godskrevet"
    let registeredAt: String        // e.g. "10/10-2025 08:12"
    let registeredBy: String        // e.g. "Ka", "MH"
    let reason: String?             // e.g. "Sygdom"
    let note: String?               // Additional note for the reason
    let remark: String?             // Bemærkning column
    let isApproved: Bool            // Has checkmark (Godskrevet)
}

/// A reason Lectio currently allows for an absence registration.
struct AbsenceReasonOption: Codable, Identifiable, Equatable, Hashable {
    let value: String
    let label: String

    var id: String { value }
}

/// Authoritative values loaded from Lectio's absence edit page.
struct AbsenceEditDetails: Equatable {
    let reasons: [AbsenceReasonOption]
    let selectedReasonValue: String?
    let note: String
}

struct ActivityDetails: Codable, Equatable {
    let title: String?              // e.g. "Ideologier"
    let hold: String                // e.g. "1g4 da"
    let teacher: String             // e.g. "Ka"
    let room: String                // e.g. "24"
    let dateTime: String            // e.g. "10/10-2025 08:10 til 09:50"
    let hasNote: Bool
    let hasHomework: Bool
    let isChanged: Bool
}

/// Complete absence report containing all sections
struct AbsenceReport: Codable, Equatable {
    let summary: AbsenceSummary
    let missingReasons: [AbsenceEntry]
    let registrations: [AbsenceEntry]
}

/// Per-subject absence breakdown for charts
struct SubjectAbsence: Identifiable {
    let id = UUID()
    let subject: String
    let fullHold: String
    let totalEntries: Int
    let averagePercent: Double
}
