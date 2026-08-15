//
//  LectioHTTPClient+Student.swift
//  BetterLectio
//

import Foundation

extension LectioHTTPClient {

    /// Validates credentials by fetching student schedule page.
    /// Returns the discovered student info AND the latest credentials, including any
    /// cookies Lectio rotated during the validation round-trip — the caller must persist
    /// these (not the input `credentials`) since rotated cookies during validation are
    /// otherwise lost (we don't yet know the studentId to write them under).
    ///
    /// Pass `studentId` when it's already known (e.g. cold-start probe) so the request can
    /// reload the freshest credentials from the keychain inside the serial gate. Another
    /// concurrent request may have rotated `autologinkeyV2` since this call was queued, and
    /// replaying the pre-rotation token trips Lectio's reuse detection and kills the session.
    /// Pass `nil` only for initial-login validation where the studentId isn't known yet.
    func validateCredentialsAndGetStudentInfo(
        credentials: LectioCredentials,
        schoolId: Int,
        studentId: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> (id: String, name: String, gymId: Int, finalCredentials: LectioCredentials) {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/SkemaNy.aspx"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        var rotatedCredentials = credentials
        let (data, updatedFromRequest, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority,
            onCredentialsUpdated: { rotatedCredentials = $0 }
        )

        let html = decodeHTML(from: data)
        let (id, name) = try StudentParser.parseStudentInfo(from: html)

        let finalCredentials = updatedFromRequest ?? rotatedCredentials
        return (id, name, schoolId, finalCredentials)
    }

    /// Fetches the Lectio homepage (forside.aspx) which contains the hold/team list.
    func fetchHomepage(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/forside.aspx"

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

    /// Fetches the team members page to get student picture IDs in bulk.
    func fetchTeamMembers(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        holdElementId: String,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/subnav/members.aspx?holdelementid=\(holdElementId)&showteachers=1&showstudents=1"

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

    /// Fetches the logged-in student's digital study card page and returns the parsed
    /// birthday string (e.g. "26/2-2008 (18 år)"). Returns `nil` if the field is absent.
    func fetchDigitalStudentCardBirthday(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority = .opportunistic
    ) async throws -> String? {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/digitaltStudiekort.aspx"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )

        return StudentParser.parseBirthday(from: decodeHTML(from: data))
    }

    /// Fetches a student's or teacher's schedule page to extract their picture ID.
    func fetchStudentPage(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        targetStudentId: String,
        isTeacher: Bool = false,
        personName: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> String {
        let idParam = isTeacher ? "laererid" : "elevid"
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/SkemaNy.aspx?\(idParam)=\(targetStudentId)"

        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: personName ?? targetStudentId,
            priority: priority
        )

        return decodeHTML(from: data)
    }
}
