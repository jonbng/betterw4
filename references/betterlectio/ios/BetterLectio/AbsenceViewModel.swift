//
//  AbsenceViewModel.swift
//  BetterLectio
//
//  Created by Kilo Code on 04/03/2026.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class AbsenceViewModel: ObservableObject {
    @Published var report: AbsenceReport? {
        didSet { rebuildBreakdown() }
    }
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared
    private var cachedAllEntries: [AbsenceEntry] = []
    private var cachedSubjectBreakdown: [SubjectAbsence] = []
    private var demoReport: AbsenceReport?
    private var loadGeneration: UUID?
    private var activeStudentID: String?

    private static let demoReasons = [
        "Sygdom", "Private forhold", "Skolerelaterede aktiviteter", "Kom for sent", "Andet"
    ].map { AbsenceReasonOption(value: $0, label: $0) }

    func loadAbsence(for student: Student) async {
        let generation = UUID()
        loadGeneration = generation
        if activeStudentID != student.studentId {
            report = nil
            demoReport = nil
            noticeMessage = nil
        }
        activeStudentID = student.studentId
        isLoading = true
        errorMessage = nil

        defer {
            if loadGeneration == generation {
                isLoading = false
            }
        }

        if student.isDemo {
            if demoReport == nil {
                demoReport = sortedByDateDescending(DemoDataProvider.absenceReport())
            }
            report = demoReport
            return
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                errorMessage = "Ingen loginoplysninger fundet"
                return
            }

            let html = try await httpClient.fetchAbsence(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId
            )

            let parsedReport = try await Task.detached(priority: .userInitiated) {
                try StudentParser.parseAbsenceReport(from: html)
            }.value
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            report = sortedByDateDescending(parsedReport)
            noticeMessage = nil
        } catch let error as LectioError {
            if loadGeneration == generation {
                error.notifyIfSessionExpired()
                errorMessage = error.errorDescription
            }
        } catch {
            if loadGeneration == generation,
               !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    func editDetails(for entry: AbsenceEntry, student: Student) async throws -> AbsenceEditDetails {
        if student.isDemo {
            let selected = Self.demoReasons.first {
                $0.label.compare(entry.reason ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }?.value
            return AbsenceEditDetails(
                reasons: Self.demoReasons,
                selectedReasonValue: selected,
                note: entry.note ?? ""
            )
        }
        guard let registrationId = entry.registrationId else {
            throw LectioError.parsingError("Registreringen kan ikke redigeres")
        }
        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
            throw LectioError.invalidCredentials
        }
        do {
            return try await httpClient.fetchAbsenceEditDetails(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                registrationId: registrationId
            )
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            throw error
        }
    }

    /// Saves the edit, updates locally after the confirmed POST, then reconciles with a fresh report.
    func updateAbsence(
        entry: AbsenceEntry,
        reason: AbsenceReasonOption,
        note: String,
        student: Student
    ) async throws {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        if student.isDemo {
            applyLocalUpdate(entry, reason: reason.label, note: note)
            demoReport = report
            return
        }

        guard let registrationId = entry.registrationId else {
            throw LectioError.parsingError("Registreringen kan ikke redigeres")
        }

        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
            throw LectioError.invalidCredentials
        }
        do {
            try await httpClient.updateAbsenceReason(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                registrationId: registrationId,
                reasonValue: reason.value,
                note: note
            )
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            throw error
        }

        // The POST response has confirmed the mutation. Reflect that immediately; a
        // subsequent refresh failure must not be presented as a failed save.
        applyLocalUpdate(entry, reason: reason.label, note: note)
        Analytics.capture("absence_cause_updated")
        guard !Task.isCancelled else { return }

        do {
            // Reload with any credentials Lectio rotated during the postback.
            let refreshedCredentials = keychainManager.loadCredentials(for: student.studentId) ?? credentials
            let html = try await httpClient.fetchAbsence(
                credentials: refreshedCredentials,
                studentId: student.studentId,
                schoolId: student.gymId
            )
            let parsedReport = try await Task.detached(priority: .userInitiated) {
                try StudentParser.parseAbsenceReport(from: html)
            }.value
            let confirmedEntry = (parsedReport.missingReasons + parsedReport.registrations)
                .first { $0.registrationId == registrationId || $0.id == entry.id }
            let confirmedReason = confirmedEntry?.reason ?? ""
            let confirmedNote = confirmedEntry?.note ?? ""
            guard confirmedReason.compare(
                reason.label,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame,
            normalizedNote(confirmedNote) == normalizedNote(note) else {
                noticeMessage = "Ændringen blev gemt, men kunne ikke bekræftes ved genindlæsning. Træk ned for at opdatere."
                return
            }
            report = sortedByDateDescending(parsedReport)
            noticeMessage = nil
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            noticeMessage = "Ændringen blev gemt, men fraværet kunne ikke genindlæses. Træk ned for at opdatere."
        } catch where !(error is CancellationError) {
            noticeMessage = "Ændringen blev gemt, men fraværet kunne ikke genindlæses. Træk ned for at opdatere."
        }
    }

    private func applyLocalUpdate(_ entry: AbsenceEntry, reason: String, note: String) {
        guard let current = report else { return }
        let updated = AbsenceEntry(
            id: entry.id,
            registrationId: entry.registrationId,
            activityId: entry.activityId,
            date: entry.date,
            week: entry.week,
            activity: entry.activity,
            activityDetails: entry.activityDetails,
            absencePercent: entry.absencePercent,
            absenceType: entry.absenceType,
            registeredAt: entry.registeredAt,
            registeredBy: entry.registeredBy,
            reason: reason,
            note: note.nilIfEmpty,
            remark: entry.remark,
            isApproved: entry.isApproved
        )
        let missing = current.missingReasons.filter { $0.id != entry.id }
        var registrations = current.registrations.filter { $0.id != entry.id }
        registrations.append(updated)
        report = sortedByDateDescending(AbsenceReport(
            summary: current.summary,
            missingReasons: missing,
            registrations: registrations
        ))
    }

    private func normalizedNote(_ note: String) -> String {
        note.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sortedByDateDescending(_ report: AbsenceReport) -> AbsenceReport {
        AbsenceReport(
            summary: report.summary,
            missingReasons: report.missingReasons.sorted { $0.date > $1.date },
            registrations: report.registrations.sorted { $0.date > $1.date }
        )
    }

    var hasMissingReasons: Bool {
        !(report?.missingReasons.isEmpty ?? true)
    }

    var hasRegistrations: Bool {
        !(report?.registrations.isEmpty ?? true)
    }

    var regularAbsencePercent: Double {
        parsePercentage(report?.summary.regularAbsence)
    }

    var writtenAbsencePercent: Double {
        parsePercentage(report?.summary.writtenAbsence)
    }

    /// All entries combined (missing reasons + registrations)
    var allEntries: [AbsenceEntry] {
        cachedAllEntries
    }

    /// Per-subject breakdown computed from all entries
    var subjectBreakdown: [SubjectAbsence] {
        cachedSubjectBreakdown
    }

    private func rebuildBreakdown() {
        let entries = (report?.missingReasons ?? []) + (report?.registrations ?? [])
        cachedAllEntries = entries
        guard !entries.isEmpty else {
            cachedSubjectBreakdown = []
            return
        }

        // Group by hold (e.g. "1g4 da")
        var grouped: [String: [AbsenceEntry]] = [:]
        for entry in entries {
            let hold = entry.activityDetails?.hold ?? "Ukendt"
            grouped[hold, default: []].append(entry)
        }

        cachedSubjectBreakdown = grouped.map { hold, entries in
            let avgPercent = entries.compactMap { entry -> Double? in
                let clean = entry.absencePercent
                    .replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                return Double(clean)
            }.reduce(0, +) / max(Double(entries.count), 1)

            // Extract short subject name: "1g4 da" → "da", "1x Fy" → "Fy"
            let subject = hold.split(separator: " ").last.map(String.init) ?? hold

            return SubjectAbsence(
                subject: subject,
                fullHold: hold,
                totalEntries: entries.count,
                averagePercent: avgPercent
            )
        }
        .sorted { $0.totalEntries > $1.totalEntries }
    }

    /// Returns a color based on absence percentage (green -> yellow -> red)
    func absenceColor(for percentage: Double) -> Color {
        if percentage < 5 {
            return .green
        } else if percentage < 10 {
            return .yellow
        } else if percentage < 15 {
            return .orange
        } else {
            return .red
        }
    }

    /// Returns a warning message if absence is concerning
    var absenceWarning: String? {
        let regular = regularAbsencePercent
        let written = writtenAbsencePercent

        if written >= 15 {
            return "Dit skriftlige fravær er meget højt (\(written.formatted())%). Du risikerer at blive indkaldt til samtale."
        } else if regular >= 10 {
            return "Dit samlede fravær er højt (\(regular.formatted())%). Hold øje med at det ikke stiger."
        } else if written >= 10 {
            return "Dit skriftlige fravær er forhøjet (\(written.formatted())%)."
        }
        return nil
    }

    private func parsePercentage(_ string: String?) -> Double {
        guard let string = string else { return 0 }
        let cleanString = string
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleanString) ?? 0
    }
}
