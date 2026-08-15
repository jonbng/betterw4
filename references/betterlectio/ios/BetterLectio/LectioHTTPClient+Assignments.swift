//
//  LectioHTTPClient+Assignments.swift
//  BetterLectio
//

import Foundation

extension LectioHTTPClient {

    /// Fetches the grades report page HTML for a student.
    func fetchGradesReport(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        targetStudentId: String? = nil,
        culture: String = "da-DK",
        priority: FetchPriority = .important
    ) async throws -> String {
        let effectiveStudentId = targetStudentId ?? studentId
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/grades/grade_report.aspx?elevid=\(effectiveStudentId)&culture=\(culture)"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )

        return decodeHTML(from: data)
    }

    /// Fetches assignments page HTML (GET request, returns default filter state)
    func fetchAssignments(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/OpgaverElev.aspx"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )

        return decodeHTML(from: data)
    }

    /// Posts to assignments page with all form fields to toggle filters.
    func postAssignmentsPage(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        eventTarget: String,
        formFields: [(name: String, value: String)],
        showCurrentOnly: Bool,
        showCurrentYearOnly: Bool,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/OpgaverElev.aspx"
        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        // Build form body from ALL extracted form fields
        var formParts: [String] = []

        // Override __EVENTTARGET with the control that triggered the postback
        let skipFields: Set<String> = ["__EVENTTARGET"]

        for field in formFields {
            if skipFields.contains(field.name) { continue }
            formParts.append("\(formURLEncode(field.name))=\(formURLEncode(field.value))")
        }

        // Set the event target to the toggled control
        formParts.insert("__EVENTTARGET=\(formURLEncode(eventTarget))", at: 0)

        // Add checkbox states
        if showCurrentOnly {
            formParts.append("\(formURLEncode("s$m$Content$Content$CurrentExerciseFilterCB"))=on")
        }
        if showCurrentYearOnly {
            formParts.append("\(formURLEncode("s$m$Content$Content$ShowThisTermOnlyCB"))=on")
        }

        let bodyString = formParts.joined(separator: "&")
        let bodyData = bodyString.data(using: .utf8)

        let headers = [
            "Referer": "https://www.lectio.dk/lectio/\(schoolId)/OpgaverElev.aspx",
            "Origin": "https://www.lectio.dk",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        let (data, _, _) = try await performRequest(
            url: url,
            method: "POST",
            body: bodyData,
            headers: headers,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "POST assignments page",
            priority: priority
        )

        return decodeHTML(from: data)
    }

    /// Fetches the assignment detail page (ElevAflevering.aspx) for a specific exercise
    func fetchAssignmentDetail(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        exerciseId: String,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/ElevAflevering.aspx?elevid=\(studentId)&exerciseid=\(exerciseId)&prevurl=OpgaverElev.aspx"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )

        return decodeHTML(from: data)
    }
}
