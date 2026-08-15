//
//  LectioHTTPClient+Absence.swift
//  BetterLectio
//

import Foundation

extension LectioHTTPClient {

    private func absenceEditURL(schoolId: Int, studentId: String, registrationId: String) throws -> URL {
        var components = URLComponents(string: "https://www.lectio.dk/lectio/\(schoolId)/fravaer_aarsag.aspx")
        components?.queryItems = [
            URLQueryItem(name: "elevid", value: studentId),
            URLQueryItem(name: "id", value: registrationId),
            URLQueryItem(name: "atype", value: "aa")
        ]
        guard let url = components?.url else { throw LectioError.invalidURL }
        return url
    }

    /// Fetches the absence page (fravaerelev_fravaersaarsager.aspx) for a student.
    func fetchAbsence(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        targetStudentId: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> String {
        let effectiveStudentId = targetStudentId ?? studentId
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/subnav/fravaerelev_fravaersaarsager.aspx?elevid=\(effectiveStudentId)"

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

    /// Loads the currently valid choices from Lectio's edit page.
    func fetchAbsenceEditDetails(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        registrationId: String
    ) async throws -> AbsenceEditDetails {
        let url = try absenceEditURL(
            schoolId: schoolId,
            studentId: studentId,
            registrationId: registrationId
        )
        let (data, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "GET absence edit"
        )
        let form = try AbsenceEditFormParser.parse(decodeHTML(from: data))
        return AbsenceEditDetails(
            reasons: form.reasons,
            selectedReasonValue: form.selectedReasonValue,
            note: form.note
        )
    }

    /// Updates a reason and note through Lectio's ASP.NET postback form.
    func updateAbsenceReason(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        registrationId: String,
        reasonValue: String,
        note: String
    ) async throws {
        let url = try absenceEditURL(
            schoolId: schoolId,
            studentId: studentId,
            registrationId: registrationId
        )

        let (pageData, refreshedCredentials, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "GET absence edit"
        )
        let form = try AbsenceEditFormParser.parse(decodeHTML(from: pageData))
        guard form.reasons.contains(where: { $0.value == reasonValue }) else {
            throw LectioError.parsingError("Den valgte fraværsårsag er ikke længere tilgængelig")
        }

        let headers = [
            "Referer": url.absoluteString,
            "Origin": "https://www.lectio.dk",
            "Content-Type": "application/x-www-form-urlencoded"
        ]
        let (responseData, _, finalURL) = try await performRequest(
            url: url,
            method: "POST",
            body: AbsenceEditFormParser.postBody(form: form, reasonValue: reasonValue, note: note),
            headers: headers,
            credentials: refreshedCredentials ?? credentials,
            studentId: studentId,
            contextForLogging: "POST absence edit"
        )

        let responseHTML = decodeHTML(from: responseData)
        try AbsenceEditFormParser.validateUpdateResponse(html: responseHTML, finalURL: finalURL)
    }
}
