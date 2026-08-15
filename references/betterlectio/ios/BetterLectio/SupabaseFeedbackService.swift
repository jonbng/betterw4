import Foundation
import Supabase

@MainActor
protocol FeedbackSubmitting {
    func submit(
        student: Student,
        category: FeedbackCategory,
        message: String,
        context: FeedbackContext,
        screenshot: EncodedFeedbackScreenshot?
    ) async throws -> FeedbackSubmitResult
}

@MainActor
final class SupabaseFeedbackService: FeedbackSubmitting {
    static let shared = SupabaseFeedbackService()

    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func submit(
        student: Student,
        category: FeedbackCategory,
        message: String,
        context: FeedbackContext,
        screenshot: EncodedFeedbackScreenshot?
    ) async throws -> FeedbackSubmitResult {
        guard !student.isDemo else { throw FeedbackSubmissionError.demoMode }
        guard let client = manager.client else { throw FeedbackSubmissionError.notConfigured }
        guard !message.isEmpty else { throw FeedbackSubmissionError.emptyMessage }
        guard message.count <= FeedbackLimits.maximumMessageCharacters else {
            throw FeedbackSubmissionError.messageTooLong
        }

        if client.auth.currentSession == nil {
            guard
                let credentials = KeychainManager.shared.loadCredentials(for: student.studentId),
                await SupabaseAuthService.shared.ensureSession(
                    credentials: credentials,
                    studentId: student.studentId,
                    gymId: student.gymId
                )
            else {
                throw FeedbackSubmissionError.notAuthenticated
            }
        }

        let feedbackID: String = try await client.rpc(
            "submit_feedback",
            params: SubmitFeedbackParameters(
                p_student_id: student.studentId,
                p_school_id: student.gymId,
                p_category: category.rawValue,
                p_message: message,
                p_platform: "ios",
                p_context: context
            )
        )
        .execute()
        .value

        let attachmentStatus: FeedbackAttachmentStatus
        if let screenshot {
            attachmentStatus = await uploadScreenshot(
                screenshot,
                feedbackID: feedbackID,
                student: student,
                client: client
            )
        } else {
            attachmentStatus = .notRequested
        }

        return FeedbackSubmitResult(
            feedbackID: feedbackID,
            attachmentStatus: attachmentStatus,
            isDemo: false
        )
    }

    private func uploadScreenshot(
        _ screenshot: EncodedFeedbackScreenshot,
        feedbackID: String,
        student: Student,
        client: SupabaseClient
    ) async -> FeedbackAttachmentStatus {
        let path = "\(student.gymId)/\(student.studentId)/\(feedbackID)/\(UUID().uuidString.lowercased()).jpg"
        var didUpload = false
        do {
            try await client.storage
                .from("feedback-attachments")
                .upload(
                    path,
                    data: screenshot.data,
                    options: FileOptions(contentType: "image/jpeg", upsert: false)
                )
            didUpload = true

            let _: String = try await client.rpc(
                "register_feedback_attachment",
                params: RegisterFeedbackAttachmentParameters(
                    p_feedback_id: feedbackID,
                    p_kind: "screenshot",
                    p_storage_path: path,
                    p_mime_type: "image/jpeg",
                    p_byte_size: screenshot.data.count,
                    p_width: screenshot.width,
                    p_height: screenshot.height
                )
            )
            .execute()
            .value
            return .uploaded
        } catch {
            FeedbackLogBuffer.shared.record("Feedback screenshot upload failed: \(type(of: error))", level: "W")
            if didUpload {
                do {
                    try await client.storage.from("feedback-attachments").remove(paths: [path])
                } catch {
                    FeedbackLogBuffer.shared.record("Feedback screenshot cleanup failed: \(type(of: error))", level: "W")
                }
            }
            // The text feedback already exists. Report partial success so retrying
            // cannot accidentally create a duplicate feedback row.
            return .failed
        }
    }
}

struct EncodedFeedbackScreenshot: Sendable {
    let data: Data
    let width: Int
    let height: Int
}

struct FeedbackContext: Encodable, Sendable {
    let app_version: String
    let app_build: String
    let os_version: String
    let device_model: String
    let locale: String
    let captured_at: String
    let include_logs: Bool
    let logs: String?
}

private nonisolated struct SubmitFeedbackParameters: Encodable, Sendable {
    let p_student_id: String
    let p_school_id: Int
    let p_category: String
    let p_message: String
    let p_platform: String
    let p_context: FeedbackContext
}

private nonisolated struct RegisterFeedbackAttachmentParameters: Encodable, Sendable {
    let p_feedback_id: String
    let p_kind: String
    let p_storage_path: String
    let p_mime_type: String
    let p_byte_size: Int
    let p_width: Int
    let p_height: Int
}
