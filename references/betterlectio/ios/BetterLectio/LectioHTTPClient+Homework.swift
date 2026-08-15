//
//  LectioHTTPClient+Homework.swift
//  BetterLectio
//

import Foundation

extension LectioHTTPClient {

    /// Fetches the homework overview page
    func fetchHomeworkOverview(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority = .important
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/material_lektieoversigt.aspx?elevid=\(studentId)"

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
