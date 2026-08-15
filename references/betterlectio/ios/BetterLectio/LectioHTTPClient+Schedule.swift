//
//  LectioHTTPClient+Schedule.swift
//  BetterLectio
//

import Foundation

extension LectioHTTPClient {
    
    /// Result struct containing schedule HTML and optional enriched student info
    struct ScheduleFetchResult {
        let html: String
        let studentInfo: EnrichedStudentInfo?
    }

    /// Enriched student info extracted from SkemaNy.aspx header
    struct EnrichedStudentInfo {
        let pictureId: String?
        let name: String?
        let classLabel: String?
    }

    /// Fetches the student schedule page for a given date range.
    func fetchSchedule(
        credentials: LectioCredentials,
        studentId: String,
        target: SchedulableTarget,
        week: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> ScheduleFetchResult {
        var urlString: String
        switch target.kind {
        case .student:
            urlString = "https://www.lectio.dk/lectio/\(target.gymId)/SkemaNy.aspx?elevid=\(target.id)"
        case .teacher:
            urlString = "https://www.lectio.dk/lectio/\(target.gymId)/SkemaNy.aspx?laererid=\(target.id)"
        case .room, .resource:
            urlString = "https://www.lectio.dk/lectio/\(target.gymId)/SkemaNy.aspx?type=lokale&nosubnav=1&id=\(target.id)"
        }
        if let week = week {
            urlString += "&week=\(week)"
        }

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )

        let html = decodeHTML(from: data)
        guard !html.isEmpty else {
            throw LectioError.parsingError("Could not decode schedule HTML")
        }

        // Extract student info only when fetching the logged-in student's own schedule
        let studentInfo: EnrichedStudentInfo?
        if target.kind == .student && target.id == studentId {
            studentInfo = EnrichedStudentInfo(
                pictureId: StudentParser.parseStudentPictureId(from: html),
                name: StudentParser.parseStudentNameFromTitle(from: html),
                classLabel: StudentParser.parseStudentClassFromTitle(from: html)
            )
            if studentInfo?.pictureId != nil || studentInfo?.name != nil {
                print("📋 Extracted student info - Picture: \(studentInfo?.pictureId ?? "nil"), Name: \(studentInfo?.name ?? "nil"), Class: \(studentInfo?.classLabel ?? "nil")")
            }
        } else {
            studentInfo = nil
        }

        return ScheduleFetchResult(html: html, studentInfo: studentInfo)
    }

    /// Extracts the absid from an event ID string
    static func absId(from eventId: String) -> String? {
        if eventId.hasPrefix("ABS") {
            return String(eventId.dropFirst(3))
        }
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: eventId, range: NSRange(eventId.startIndex..., in: eventId)) else {
            return nil
        }
        return String(eventId[Range(match.range, in: eventId)!])
    }

    /// Fetches lesson content (notes, homework, etc.) for a specific lesson.
    func fetchLessonContent(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        absId: String,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/aktivitet/aktivitetforside2.aspx?absid=\(absId)&prevurl=skemany.aspx&elevid=\(studentId)"

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

    /// Fetches the advanced schedule search page (FindSkemaAdv.aspx) to extract the dropdown URL.
    func fetchAdvancedSchedulePage(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/FindSkemaAdv.aspx"

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

    /// Fetches the autocomplete dropdown JSON data from a relative URL path.
    func fetchDropdownData(
        credentials: LectioCredentials,
        studentId: String,
        relativePath: String,
        priority: FetchPriority = .opportunistic
    ) async throws -> Data {
        let urlString = "https://www.lectio.dk\(relativePath)"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )

        return data
    }
}
