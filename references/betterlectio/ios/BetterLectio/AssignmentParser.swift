//
//  AssignmentParser.swift
//  BetterLectio
//

import Foundation
import SwiftSoup

/// Parser for assignments and exercises from Lectio.
enum AssignmentParser {
    
    // MARK: - Parse Assignments

    /// Parses assignments table from OpgaverElev.aspx HTML
    static func parseAssignments(from html: String) throws -> [Assignment] {
        let doc = try SwiftSoup.parse(html)

        guard let table = try doc.select("table#s_m_Content_Content_ExerciseGV").first() else {
            print("⚠️ Assignments table not found")
            return []
        }

        let rows = try table.select("tbody tr")
        var assignments: [Assignment] = []

        // Danish date formatter for deadline parsing: "3/12-2025 14:00"
        let deadlineFormatter = DateFormatter()
        deadlineFormatter.dateFormat = "d/M-yyyy HH:mm"
        deadlineFormatter.locale = Locale(identifier: "da_DK")

        for row in rows {
            // Skip header row (has th elements)
            let headers = try row.select("th")
            if !headers.isEmpty() { continue }

            // Get desktop-only cells
            let cells = try row.select("td.OnlyDesktop")
            guard cells.count >= 11 else { continue }

            // Week
            let week = try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)

            // Hold (class) + element ID
            let holdSpan = try cells[1].select("span[data-lectiocontextcard]").first()
            let hold = try holdSpan?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? cells[1].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let holdElementId = try holdSpan?.attr("data-lectiocontextcard") ?? ""

            // Title + detail URL + exercise ID
            let titleLink = try cells[2].select("a").first()
            let title = try titleLink?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let detailURL = try titleLink?.attr("href") ?? ""

            // Extract exerciseid from URL
            var exerciseId = ""
            if let range = detailURL.range(of: "exerciseid=(\\d+)", options: .regularExpression) {
                exerciseId = String(detailURL[range]).replacingOccurrences(of: "exerciseid=", with: "")
            }

            guard !exerciseId.isEmpty else { continue }

            // Deadline
            let deadline = try cells[3].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let deadlineDate = deadlineFormatter.date(from: deadline)

            // Student time
            let studentTime = try cells[4].text().trimmingCharacters(in: .whitespacesAndNewlines)

            // Status
            let statusText = try cells[5].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let hasWaitingSpan = try !cells[5].select("span.exercisewait").isEmpty()
            let status: AssignmentStatus
            if hasWaitingSpan || statusText == "Venter" {
                status = .waiting
            } else if statusText == "Afleveret" {
                status = .submitted
            } else if statusText.contains("Ikke afleveret") {
                status = .notSubmitted
            } else if statusText == "Mangler" {
                status = .missing
            } else {
                status = .waiting
            }

            // Absence
            let absence = try cells[6].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

            // Awaiting
            let awaiting = try cells[7].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

            // Assignment note
            let assignmentNote = try cells[8].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

            // Grade (may contain grade + grade note separated by <br>)
            let gradeCell = cells[9]
            let gradeHTML = try gradeCell.html()
            let gradeParts = gradeHTML.components(separatedBy: "<br>")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let grade = gradeParts.first
            let gradeNote = gradeParts.dropFirst().first

            // Student note
            let studentNote = try cells[10].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

            assignments.append(Assignment(
                id: exerciseId,
                week: week,
                hold: hold,
                holdElementId: holdElementId,
                title: title,
                deadline: deadline,
                deadlineDate: deadlineDate,
                studentTime: studentTime,
                status: status,
                absence: absence,
                awaiting: awaiting,
                assignmentNote: assignmentNote,
                grade: grade,
                gradeNote: gradeNote,
                studentNote: studentNote,
                detailURL: detailURL
            ))
        }

        print("📝 Parsed \(assignments.count) assignments")
        return assignments
    }

    // MARK: - Parse Assignment Detail

    /// Parses the assignment detail page (ElevAflevering.aspx) into structured content.
    static func parseAssignmentDetail(from html: String) throws -> AssignmentDetail {
        let doc = try SwiftSoup.parse(html)

        // --- Section 1: Opgaveoplysninger ---
        guard let infoSection = try doc.select("#m_Content_registerAfl_pa").first() else {
            throw LectioError.parsingError("Assignment info section not found")
        }

        // Title
        let title = try doc.select("#m_Content_NameLbl").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Description files (Opgavebeskrivelse)
        var descriptionFiles: [AssignmentFile] = []
        let descLinks = try infoSection.select("a[id*=showdocumentHyperlnk]")
        for link in descLinks {
            let href = try link.attr("href")
            let text = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            descriptionFiles.append(AssignmentFile(id: href, name: text, url: href))
        }

        // Parse key-value rows from the info table
        let infoRows = try infoSection.select("table.ls-std-table-inputlist tr")
        var hold = ""
        var gradeScale: String?
        var teacher = ""
        var studentTime = ""
        var deadline = ""
        var assignmentNote: String?
        var inDescription = false

        for row in infoRows {
            let th = try row.select("th").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let td = try row.select("td").first()

            if th.hasPrefix("Hold") {
                hold = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if th.hasPrefix("Karakterskala") {
                gradeScale = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            } else if th.hasPrefix("Ansvarlig") {
                teacher = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if th.hasPrefix("Elevtid") {
                studentTime = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if th.hasPrefix("Afleveringsfrist") {
                deadline = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } else if th.hasPrefix("Opgavenote") {
                let noteText = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                assignmentNote = noteText.isEmpty ? nil : noteText
            } else if th.contains("undervisningsbeskrivelse") {
                let val = try td?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                inDescription = val == "Ja"
            }
        }

        // --- Section 2: Afleveres af (student status) ---
        var awaiting: String?
        var status: String?
        var completed = false
        var grade: String?
        var gradeNote: String?
        var studentNote: String?

        if let studentTable = try doc.select("#m_Content_StudentGV").first() {
            let studentRows = try studentTable.select("tr")
            // Skip header row (first tr with th elements)
            for row in studentRows {
                let cells = try row.select("td")
                guard cells.count >= 7 else { continue }

                // cells: [0]=photo, [1]=name, [2]=awaiting, [3]=status, [4]=completed, [5]=grade, [6]=gradeNote, [7]=studentNote
                awaiting = try cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)
                if awaiting?.isEmpty == true { awaiting = nil }

                status = try cells[3].text().trimmingCharacters(in: .whitespacesAndNewlines)
                if status?.isEmpty == true { status = nil }

                // Completed checkbox
                let checkbox = try cells[4].select("input[type=checkbox]").first()
                if let cb = checkbox {
                    completed = try cb.hasAttr("checked")
                }

                let gradeText = try cells[5].text().trimmingCharacters(in: .whitespacesAndNewlines)
                grade = gradeText.isEmpty ? nil : gradeText

                let gradeNoteText = try cells[6].text().trimmingCharacters(in: .whitespacesAndNewlines)
                gradeNote = gradeNoteText.isEmpty ? nil : gradeNoteText

                if cells.count > 7 {
                    let studentNoteText = try cells[7].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    studentNote = studentNoteText.isEmpty ? nil : studentNoteText
                }

                break // Only need the first data row (the student)
            }
        }

        // --- Section 3: Opgaveindlæg (submissions) ---
        var submissions: [AssignmentSubmission] = []

        if let submissionTable = try doc.select("#m_Content_RecipientGV").first() {
            // Check for empty state
            let noRecord = try submissionTable.select("span.norecord")
            if noRecord.isEmpty() {
                let subRows = try submissionTable.select("tr")
                var index = 0
                for row in subRows {
                    let cells = try row.select("td")
                    guard cells.count >= 4 else { continue }

                    let timestamp = try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    let user = try cells[1].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    let commentText = try cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    let comment = commentText.isEmpty ? nil : commentText

                    // Document link
                    var document: AssignmentFile?
                    if let docLink = try cells[3].select("a").first() {
                        let href = try docLink.attr("href")
                        let docName = try docLink.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !href.isEmpty {
                            document = AssignmentFile(id: href, name: docName, url: href)
                        }
                    }

                    submissions.append(AssignmentSubmission(
                        id: "\(index)",
                        timestamp: timestamp,
                        user: user,
                        comment: comment,
                        document: document
                    ))
                    index += 1
                }
            }
        }

        print("📋 Parsed assignment detail: \(title), \(submissions.count) submissions, \(descriptionFiles.count) description files")

        return AssignmentDetail(
            title: title,
            hold: hold,
            gradeScale: gradeScale,
            teacher: teacher,
            studentTime: studentTime,
            deadline: deadline,
            assignmentNote: assignmentNote,
            inDescription: inDescription,
            descriptionFiles: descriptionFiles,
            submissions: submissions,
            awaiting: awaiting,
            status: status,
            completed: completed,
            grade: grade,
            gradeNote: gradeNote,
            studentNote: studentNote
        )
    }
}
