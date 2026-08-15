//
//  AuthenticationService.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import WebKit
import Supabase

/// Service for handling Lectio authentication with MitID
class AuthenticationService {
    private let cookieManager = CookieManager.shared
    private let keychainManager = KeychainManager.shared
    private let httpClient = LectioHTTPClient()

    // MARK: - Authentication URL

    /// Generates the Lectio login URL for a specific school
    func getAuthenticationURL(for school: School) -> URL {
        URL(string: "https://www.lectio.dk/lectio/\(school.id)/login.aspx")!
    }

    // MARK: - Callback Detection

    /// Checks if a URL is the MitID callback or forside.aspx (already logged in)
    func isCallbackURL(_ url: URL) -> Bool {
        let urlString = url.absoluteString

        // MitID callback: Contains integration/unilogin.aspx but NOT broker.unilogin.dk
        let isMitIDCallback = urlString.contains("lectio.dk/lectio/integration/unilogin.aspx")
            && !urlString.contains("broker.unilogin.dk")

        // Already logged in: Contains forside.aspx
        let isForsideURL = urlString.contains("/forside.aspx")

        return isMitIDCallback || isForsideURL
    }

    // MARK: - Complete Authentication

    /// Extracts cookies from WebView and completes authentication flow
    func completeAuthentication(
        from webView: WKWebView,
        school: School
    ) async throws -> Student {
        print("🔐 Starting authentication completion...")

        // Step 1: Extract credentials from WebView cookies
        let credentials = try await cookieManager.extractLectioCredentials(from: webView)

        print("✅ Credentials extracted successfully")

        // Step 2: Validate credentials by fetching student info from Lectio.
        // Lectio frequently rotates ASP.NET_SessionId / autologinkeyV2 during this round-trip;
        // `finalCredentials` is the post-rotation set, which is what we must persist.
        print("🌐 Validating credentials with Lectio...")
        let (studentId, name, finalCredentials) = try await validateCredentialsAndGetStudentInfo(
            credentials: credentials,
            schoolId: school.id
        )

        print("✅ Student ID: \(studentId)")
        print("✅ Student name: \(name)")

        // Step 3: Create student object
        let student = Student(
            studentId: studentId,
            gymId: school.id,
            name: name,
            schoolName: school.name
        )

        // Step 4: Save credentials to Keychain (post-validation rotated set).
        try keychainManager.saveCredentials(finalCredentials, for: studentId)
        print("✅ Credentials saved to Keychain")

        // Step 5: Save student info to Keychain
        try keychainManager.saveStudent(student)
        print("✅ Student info saved to Keychain")

        // Step 6: Mint Supabase session via lectio-auth (QR only; Lectio cookies stay on device).
        await SupabaseAuthService.shared.authenticateWithLectio(
            credentials: finalCredentials,
            studentId: studentId,
            gymId: school.id
        )

        return student
    }

    // MARK: - Demo Mode

    /// Creates an unauthenticated demo session for App Review. No network, no
    /// credentials, no Supabase. The demo Student is persisted so cold launch
    /// restores the same session without showing the login screen.
    func enterDemoSession() throws -> Student {
        let demo = Student.demo
        try keychainManager.saveStudent(demo)
        print("🎭 Entered demo session")
        return demo
    }

    // MARK: - Logout

    /// Wipes every piece of auth state so the next login starts from a clean slate:
    /// the entire app keychain (credentials + student record), the WKWebView cookie/
    /// storage jar used by the MitID/UniLogin login flow, and the Supabase session.
    /// Idempotent — safe to call when nothing is signed in (e.g. on cold-start to
    /// scrub residual state from a crash mid-logout or a stale prior install).
    func wipeAuthState() async {
        await MainActor.run {
            SupabaseStudentProfileService.shared.clearCache()
        }
        await PublicProfileImageLoader.shared.clearCache()
        keychainManager.wipeAll()
        await cookieManager.clearAllWebViewData()
        try? await SupabaseManager.shared.client?.auth.signOut(scope: .local)
    }

    func logout(student: Student) async {
        print("🚪 Logging out student: \(student.studentId)")
        await MessageCacheManager.clearCache(studentId: student.studentId)
        await wipeAuthState()
        print("✅ Logout complete")
    }

    // MARK: - Load Stored Credentials

    /// Attempts to load stored student from Keychain
    func loadStoredStudent() -> Student? {
        keychainManager.loadStudent()
    }

    /// Checks if stored credentials exist in Keychain. We do not gate on expiry dates —
    /// Lectio happily rotates sessions when a stale-looking autologin is presented, so a
    /// past expiry date is not a reason to refuse to try.
    func hasStoredCredentials(for student: Student) -> Bool {
        keychainManager.loadCredentials(for: student.studentId) != nil
    }

    // MARK: - Validate Credentials

    /// Validates credentials by fetching student info from Lectio.
    /// Returns the rotated credentials too — Lectio commonly issues fresh `ASP.NET_SessionId`
    /// and `autologinkeyV2` during this probe; the caller must persist these instead of the
    /// pre-validation snapshot.
    private func validateCredentialsAndGetStudentInfo(
        credentials: LectioCredentials,
        schoolId: Int,
        priority: FetchPriority = .important
    ) async throws -> (studentId: String, name: String, finalCredentials: LectioCredentials) {
        let (studentId, name, _, finalCredentials) = try await httpClient.validateCredentialsAndGetStudentInfo(
            credentials: credentials,
            schoolId: schoolId,
            priority: priority
        )

        return (studentId, name, finalCredentials)
    }

    // MARK: - Cold-Start Validation

    /// Lightweight probe used on app launch to detect a server-revoked session before any
    /// user-facing fetch fails. Throws `.invalidCredentials` if the autologin is dead;
    /// network errors / robot detection / parsing errors are propagated unchanged so the
    /// caller can decide whether to keep the user signed in.
    ///
    /// On success, persists any `Set-Cookie` rotation from the probe (same as login validation).
    /// Previously this return value was discarded, so Keychain could stay one refresh behind
    /// the server until a later request with a non-nil `studentId` saved updates.
    func coldStartValidate(credentials: LectioCredentials, schoolId: Int, studentId: String) async throws {
        let (_, _, _, finalCredentials) = try await httpClient.validateCredentialsAndGetStudentInfo(
            credentials: credentials,
            schoolId: schoolId,
            studentId: studentId,
            priority: .opportunistic
        )
        do {
            try keychainManager.updateCredentials(finalCredentials, for: studentId)
        } catch {
            print("⚠️ [Auth] Cold-start: validated OK but could not persist rotated credentials — \(error.localizedDescription)")
        }
    }
}
