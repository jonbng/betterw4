import Foundation
import Supabase

@MainActor
protocol ProfilePictureServing: AnyObject {
    func state(studentID: String) async throws -> ProfilePictureState
    func submit(student: Student, picture: PreparedProfilePicture) async throws -> ProfilePictureSubmitResult
}

@MainActor
final class SupabaseProfilePictureService: ProfilePictureServing {
    static let shared = SupabaseProfilePictureService()
    static let maximumBytes = ProfilePictureValidator.maximumBytes

    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func state(studentID: String) async throws -> ProfilePictureState {
        guard let client = manager.client else { throw ProfilePictureServiceError.notConfigured }
        return try await client.rpc(
            "get_my_profile_picture_state",
            params: ProfilePictureStateParameters(p_student_id: studentID)
        ).execute().value
    }

    func submit(student: Student, picture: PreparedProfilePicture) async throws -> ProfilePictureSubmitResult {
        do {
            try ProfilePictureValidator.validate(picture)
        } catch {
            throw ProfilePictureServiceError.invalidFile
        }
        guard let configuration = manager.configuration, let client = manager.client else {
            throw ProfilePictureServiceError.notConfigured
        }
        let accessToken: String
        do {
            accessToken = try await client.auth.session.accessToken
        } catch {
            throw ProfilePictureServiceError.notAuthenticated
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: configuration.projectURL.appending(path: "functions/v1/profile-picture-submit"))
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            student: student,
            picture: picture,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProfilePictureServiceError.invalidResponse }
        let result = try JSONDecoder().decode(ProfilePictureSubmitResult.self, from: data)
        if !(200..<300).contains(http.statusCode), result.code == nil {
            throw ProfilePictureServiceError.invalidResponse
        }
        return result
    }

    private static func multipartBody(
        student: Student,
        picture: PreparedProfilePicture,
        boundary: String
    ) -> Data {
        var data = Data()
        func append(_ string: String) { data.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        field("studentId", student.studentId)
        field("schoolId", String(student.gymId))
        field("platform", "ios")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"profile.\(picture.fileExtension)\"\r\n")
        append("Content-Type: \(picture.mimeType)\r\n\r\n")
        data.append(picture.data)
        append("\r\n--\(boundary)--\r\n")
        return data
    }
}

enum ProfilePictureServiceError: Error, Equatable {
    case notConfigured
    case notAuthenticated
    case invalidFile
    case invalidResponse
}

private nonisolated struct ProfilePictureStateParameters: Encodable, Sendable {
    let p_student_id: String
}
