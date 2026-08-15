//
//  AssignmentsViewModel.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 23/02/2026.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Filter Enum

enum AssignmentFilter: String, CaseIterable {
    case kommende = "Kommende"
    case mangler = "Mangler"
    case fravaer = "Fravær"
    case afleverede = "Afleverede"
    case alt = "Alt"
}

@MainActor
class AssignmentsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var assignments: [Assignment] = [] { didSet { recomputeDerived() } }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: AssignmentFilter = .alt { didSet { recomputeDerived() } }

    /// Cached derived state, recomputed only when `assignments` or `selectedFilter`
    /// change — not on every unrelated `@Published` update (e.g. `isLoading`).
    @Published private(set) var filteredAssignments: [Assignment] = []
    @Published private(set) var assignmentsGroupedByWeek: [WeekGroup] = []

    private func recomputeDerived() {
        filteredAssignments = computeFilteredAssignments()
        assignmentsGroupedByWeek = computeAssignmentsGroupedByWeek()
    }

    // MARK: - Services

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared
    private var loadGeneration: UUID?
    private var activeStudentID: String?

    // MARK: - Filtered Assignments

    private func computeFilteredAssignments() -> [Assignment] {
        let now = Date()
        let calendar = Calendar.current
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        switch selectedFilter {
        case .kommende:
            return assignments.filter { a in
                guard let deadline = a.deadlineDate else { return false }
                // Future, or within last 3 days and not yet submitted
                return deadline > now || (deadline > threeDaysAgo && a.status != .submitted)
            }.sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }

        case .mangler:
            return assignments.filter { a in
                guard let deadline = a.deadlineDate else { return false }
                return a.status == .missing || (a.status == .notSubmitted && deadline < now)
            }.sorted { ($0.deadlineDate ?? .distantPast) > ($1.deadlineDate ?? .distantPast) }

        case .fravaer:
            return assignments.filter { a in
                absenceValue(from: a.absence) > 0
            }.sorted { ($0.deadlineDate ?? .distantPast) > ($1.deadlineDate ?? .distantPast) }

        case .afleverede:
            return assignments.filter { $0.status == .submitted }
                .sorted { ($0.deadlineDate ?? .distantPast) > ($1.deadlineDate ?? .distantPast) }

        case .alt:
            return assignments.sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
        }
    }

    // MARK: - Week Grouping

    struct WeekGroup: Identifiable {
        let id: String
        let title: String
        let assignments: [Assignment]

        /// Total elev timer hours for this week bucket (sums `studentTime`), matching lectio_plus_plus `OpgaveList`.
        var totalElevTimerHours: Double {
            assignments.reduce(0) { $0 + $1.elevTimerHours }
        }
    }

    /// Assignments grouped by week (deadline date), sorted chronologically.
    private func computeAssignmentsGroupedByWeek() -> [WeekGroup] {
        let calendar = Calendar.current
        let now = Date()
        guard calendar.dateInterval(of: .weekOfYear, for: now) != nil else {
            return [WeekGroup(id: "all", title: "Alle", assignments: filteredAssignments)]
        }

        var weekMap: [String: [Assignment]] = [:]
        var noDate: [Assignment] = []

        for a in filteredAssignments {
            guard let d = a.deadlineDate else {
                noDate.append(a)
                continue
            }
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: d) else {
                noDate.append(a)
                continue
            }
            let weekStart = weekInterval.start
            let year = calendar.component(.year, from: weekStart)
            let week = calendar.component(.weekOfYear, from: weekStart)
            let key = "\(year)-W\(week)"
            weekMap[key, default: []].append(a)
        }

        for key in weekMap.keys {
            weekMap[key]?.sort { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
        }

        let currentYear = calendar.component(.year, from: now)
        let currentWeek = calendar.component(.weekOfYear, from: now)
        let currentKey = "\(currentYear)-W\(currentWeek)"

        let sortedKeys = weekMap.keys.sorted { k1, k2 in
            let (y1, w1) = parseWeekKey(k1)
            let (y2, w2) = parseWeekKey(k2)
            if y1 != y2 { return y1 < y2 }
            return w1 < w2
        }

        var groups: [WeekGroup] = []
        for key in sortedKeys {
            guard let list = weekMap[key], !list.isEmpty else { continue }
            let firstDate = list.compactMap(\.deadlineDate).min() ?? now
            let title: String
            if key == currentKey {
                title = "Uge \(currentWeek) - Denne uge"
            } else {
                title = "Uge \(calendar.component(.weekOfYear, from: firstDate))"
            }
            groups.append(WeekGroup(id: key, title: title, assignments: list))
        }

        if !noDate.isEmpty {
            groups.append(WeekGroup(id: "ukendt", title: "Uden afleveringsdato", assignments: noDate))
        }

        return groups
    }

    /// Week identifier for the current week (for scroll-to).
    var currentWeekId: String {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let week = calendar.component(.weekOfYear, from: now)
        return "\(year)-W\(week)"
    }

    private func parseWeekKey(_ key: String) -> (Int, Int) {
        let parts = key.split(separator: "-")
        guard parts.count >= 2,
              let y = Int(parts[0]),
              let w = Int(parts[1].dropFirst()) else { return (0, 0) }
        return (y, w)
    }

    /// Parses absence string (e.g. "0 %", "15%", "0,5 %") and returns the numeric value.
    /// Returns 0 for nil, empty, "-", or unparseable strings.
    private func absenceValue(from absence: String?) -> Double {
        guard let s = absence, !s.isEmpty else { return 0 }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed == "-" || trimmed.isEmpty { return 0 }
        // Extract numeric part: "15 %", "15%", "0,5 %" -> 15 or 0.5
        let normalized = trimmed
            .replacingOccurrences(of: " %", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(normalized) ?? 0
    }

    /// Kommende assignments due this week (Mon–Sun)
    var thisWeekAssignments: [Assignment] {
        let calendar = Calendar.current
        let now = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return filteredAssignments.filter { a in
            guard let d = a.deadlineDate else { return false }
            return d >= weekInterval.start && d < weekInterval.end
        }
    }

    /// Kommende assignments after this week
    var laterAssignments: [Assignment] {
        let calendar = Calendar.current
        let now = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return filteredAssignments }
        return filteredAssignments.filter { a in
            guard let d = a.deadlineDate else { return false }
            return d >= weekInterval.end
        }
    }

    /// Kommende assignments with past deadlines (within 3 days, not submitted)
    var overdueAssignments: [Assignment] {
        let now = Date()
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return filteredAssignments.filter { a in
            guard let d = a.deadlineDate else { return false }
            return d < now && d < weekInterval.start
        }
    }

    // MARK: - Assignment Detail

    @Published var assignmentDetail: AssignmentDetail?
    @Published var isLoadingDetail = false
    @Published var detailError: String?

    func loadAssignmentDetail(for assignment: Assignment, student: Student) async {
        isLoadingDetail = true
        detailError = nil
        assignmentDetail = nil

        if student.isDemo {
            assignmentDetail = DemoDataProvider.assignmentDetail(for: assignment)
            isLoadingDetail = false
            return
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                detailError = "Ingen loginoplysninger fundet"
                isLoadingDetail = false
                return
            }

            let html = try await httpClient.fetchAssignmentDetail(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                exerciseId: assignment.id
            )

            let detail = try await Task.detached(priority: .userInitiated) {
                try AssignmentParser.parseAssignmentDetail(from: html)
            }.value
            try Task.checkCancellation()
            assignmentDetail = detail
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            detailError = error.errorDescription
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                detailError = error.localizedDescription
            }
        }

        isLoadingDetail = false
    }

    // MARK: - Load Assignments

    /// Loads all assignments by doing a GET then POSTing with both filters disabled.
    func loadAssignments(for student: Student) async {
        let generation = UUID()
        loadGeneration = generation
        if activeStudentID != student.studentId {
            assignments = []
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
            assignments = DemoDataProvider.assignments()
            return
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                if loadGeneration == generation {
                    errorMessage = "Ingen loginoplysninger fundet"
                }
                return
            }

            // 1. GET initial page (default: both filters checked)
            let initialHTML = try await httpClient.fetchAssignments(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId
            )

            let formFields = try await Task.detached(priority: .userInitiated) {
                try BaseParser.parseAllFormFields(from: initialHTML)
            }.value
            try Task.checkCancellation()

            // 2. POST with both filters disabled to get all assignments
            let html = try await httpClient.postAssignmentsPage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                eventTarget: "s$m$Content$Content$CurrentExerciseFilterCB",
                formFields: formFields,
                showCurrentOnly: false,
                showCurrentYearOnly: false
            )

            let parsedAssignments = try await Task.detached(priority: .userInitiated) {
                try AssignmentParser.parseAssignments(from: html)
            }.value
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            assignments = parsedAssignments
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
}
