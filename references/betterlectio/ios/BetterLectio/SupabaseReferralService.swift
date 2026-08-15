import Foundation
import Supabase

final class SupabaseReferralService {
    static let shared = SupabaseReferralService()

    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func stats(studentID: String) async throws -> ReferralStats {
        guard let client = manager.client else { throw ReferralServiceError.notConfigured }
        let rows: [ReferralStats] = try await client.rpc(
            "get_referral_stats",
            params: ReferralStatsParameters(p_student_id: studentID)
        ).execute().value
        return rows.first ?? .empty
    }

    func registerClick(referrerStudentID: String) async throws -> UUID {
        guard let configuration = manager.configuration else { throw ReferralServiceError.notConfigured }
        var components = URLComponents(
            url: configuration.projectURL.appending(path: "functions/v1/referral-click"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "ref", value: referrerStudentID),
            URLQueryItem(name: "delivery", value: "json"),
        ]
        guard let url = components?.url else { throw ReferralServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ReferralServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(ClickResponse.self, from: data)
        guard let token = UUID(uuidString: payload.cookieId) else { throw ReferralServiceError.invalidResponse }
        return token
    }

    func validate(token: UUID, referrerStudentID: String) async throws -> Bool {
        guard let configuration = manager.configuration else { throw ReferralServiceError.notConfigured }
        var components = URLComponents(
            url: configuration.projectURL.appending(path: "functions/v1/referral-click"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "ref", value: referrerStudentID),
            URLQueryItem(name: "delivery", value: "validate"),
            URLQueryItem(name: "token", value: token.uuidString.lowercased()),
        ]
        guard let url = components?.url else { throw ReferralServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ReferralServiceError.invalidResponse
        }
        return try JSONDecoder().decode(TokenValidationResponse.self, from: data).valid
    }

    func finalize(student: Student, token: UUID) async throws -> ReferralFinalizeResult {
        guard let client = manager.client else { throw ReferralServiceError.notConfigured }
        return try await client.functions.invoke(
            "referral-finalize",
            options: FunctionInvokeOptions(
                body: FinalizeRequest(
                    studentId: student.studentId,
                    schoolId: student.gymId,
                    cookieId: token.uuidString.lowercased(),
                    platform: "ios"
                )
            )
        )
    }
}

enum ReferralServiceError: Error {
    case notConfigured
    case invalidResponse
}

private nonisolated struct ReferralStatsParameters: Encodable, Sendable {
    let p_student_id: String
}

private nonisolated struct ClickResponse: Decodable, Sendable {
    let cookieId: String
}

private nonisolated struct TokenValidationResponse: Decodable, Sendable {
    let valid: Bool
}

private nonisolated struct FinalizeRequest: Encodable, Sendable {
    let studentId: String
    let schoolId: Int
    let cookieId: String
    let platform: String
}
