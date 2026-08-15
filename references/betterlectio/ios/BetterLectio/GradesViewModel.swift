//
//  GradesViewModel.swift
//  BetterLectio
//
//  Created by GitHub Copilot on 02/03/2026.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class GradesViewModel: ObservableObject {
    @Published var report: GradesReport? {
        didSet { cachedVisibleGrades = report?.grades.filter { !$0.grades.isEmpty } ?? [] }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared
    private var cachedVisibleGrades: [GradeEntry] = []
    private var loadGeneration: UUID?
    private var activeStudentID: String?

    func loadGrades(for student: Student) async {
        let generation = UUID()
        loadGeneration = generation
        if activeStudentID != student.studentId {
            report = nil
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
            report = DemoDataProvider.gradesReport()
            return
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                errorMessage = "Ingen loginoplysninger fundet"
                return
            }

            let html = try await httpClient.fetchGradesReport(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId
            )

            let parsedReport = try await Task.detached(priority: .userInitiated) {
                try GradeParser.parseGradesReport(from: html)
            }.value
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            report = parsedReport
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

    var visibleGrades: [GradeEntry] {
        cachedVisibleGrades
    }
}
