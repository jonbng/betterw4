//
//  SupabaseAuthService.swift
//  BetterLectio
//

import Foundation
import Supabase

@MainActor
final class SupabaseAuthService {
    static let shared = SupabaseAuthService()
    private let manager = SupabaseManager.shared
    private var authenticationTask: Task<Void, Never>?

    private init() {}

    /// Authenticates with Supabase via the universal `lectio-auth` edge function.
    /// Mints a Lectio login QR with the device's existing Lectio session (no cookie handoff).
    func authenticateWithLectio(credentials: LectioCredentials, studentId: String, gymId: Int) async {
        if let authenticationTask {
            print("⏳ [SupabaseAuth] Waiting for authentication already in progress...")
            await authenticationTask.value
            return
        }

        let task = Task { @MainActor in
            await performAuthentication(credentials: credentials, studentId: studentId, gymId: gymId)
        }
        authenticationTask = task
        await task.value
        authenticationTask = nil
    }

    func ensureSession(credentials: LectioCredentials, studentId: String, gymId: Int) async -> Bool {
        if manager.client?.auth.currentSession != nil { return true }
        await authenticateWithLectio(credentials: credentials, studentId: studentId, gymId: gymId)
        return manager.client?.auth.currentSession != nil
    }

    /// Back-compat wrapper for callers that only have gymId; resolves studentId from Keychain.
    func ensureSession(credentials: LectioCredentials, gymId: Int) async -> Bool {
        guard let studentId = KeychainManager.shared.loadStudent()?.studentId else { return false }
        return await ensureSession(credentials: credentials, studentId: studentId, gymId: gymId)
    }

    private func performAuthentication(credentials: LectioCredentials, studentId: String, gymId: Int) async {
        guard let client = manager.client else {
            print("⚠️ [SupabaseAuth] Client not configured. Skipping.")
            return
        }

        print("🔐 [SupabaseAuth] Starting QR mint + lectio-auth...")

        do {
            try await LectioHTTPClient.withSerialLectioRequest(priority: .important) {
                let qr = try await LectioQrMintService.mint(
                    credentials: credentials,
                    studentId: studentId,
                    gymId: gymId
                )
                print("✅ [SupabaseAuth] Lectio QR minted")

                let response: EdgeFunctionResponse = try await client.functions.invoke(
                    "lectio-auth",
                    options: FunctionInvokeOptions(
                        body: EdgeFunctionRequest(
                            qrId: qr.qrId,
                            userId: qr.userId,
                            schoolId: String(gymId),
                            client: ClientMetadata(
                                platform: "ios",
                                app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                                app_build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                            )
                        )
                    )
                )
                print("✅ [SupabaseAuth] Received magic-link token")

                if let responseStudentId = response.student_id, responseStudentId != studentId {
                    print("❌ [SupabaseAuth] Identity mismatch expected=\(studentId) actual=\(responseStudentId)")
                    return
                }

                try await client.auth.verifyOTP(
                    tokenHash: response.token_hash,
                    type: .magiclink
                )
                print("✅ [SupabaseAuth] Authentication successful. Session persisted by SDK.")

                if let requestID = response.request_id {
                    do {
                        let _: Bool = try await client.rpc(
                            "confirm_auth_attempt",
                            params: ConfirmAttemptParams(
                                p_request_id: requestID,
                                p_completion_kind: "session_ready"
                            )
                        ).execute().value
                    } catch {
                        print("⚠️ [SupabaseAuth] Auth-attempt confirmation failed: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            print("❌ [SupabaseAuth] Authentication failed: \(error.localizedDescription)")
        }
    }

    private struct EdgeFunctionRequest: Encodable {
        let qrId: String
        let userId: String
        let schoolId: String
        let client: ClientMetadata
    }

    private struct ClientMetadata: Encodable {
        let platform: String
        let app_version: String?
        let app_build: String?
    }

    private struct ConfirmAttemptParams: Encodable {
        let p_request_id: String
        let p_completion_kind: String
    }

    private struct EdgeFunctionResponse: Decodable {
        let token_hash: String
        let email: String
        let student_id: String?
        let school_id: String?
        let was_first_install: Bool?
        let request_id: String?
    }
}
