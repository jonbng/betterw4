//
//  AuthenticationViewModel.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import SwiftUI
import WebKit
import Combine
import Supabase

/// View model for managing authentication state and flow
@MainActor
class AuthenticationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var authState: AuthState = .loading
    @Published var schools: [School] = []
    @Published var selectedSchool: School?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showWebView = false
    @Published var authenticationURL: URL?
    @Published var isLoadingSchools = false
    @Published var schoolLoadError: String?
    @Published private(set) var hasLoadedSchoolsFromSupabase = false
    /// Persisted last school for one-tap MitID after logout / session expiry.
    @Published private(set) var lastSchoolHint: LastSchoolHint?
    /// When a hint exists, resume mode is the default; true after “Vælg anden skole”.
    @Published var choosingOtherSchool = false

    var showResumeLogin: Bool {
        lastSchoolHint != nil && !choosingOtherSchool
    }

    // MARK: - Services

    let authService = AuthenticationService()

    // MARK: - Initialization

    init() {
        lastSchoolHint = LastSchoolStore.load()
        if let hint = lastSchoolHint {
            selectedSchool = hint.school
        }
        loadSchools()
        Task { @MainActor [weak self] in await self?.checkStoredCredentials() }

        NotificationCenter.default.addObserver(
            forName: .lectioSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleSessionExpired() }
        }
    }

    /// Force-logout when any HTTP path surfaces a definitively dead Lectio session.
    /// Idempotent — concurrent posts from multiple view models collapse to a single logout
    /// because `authState` is no longer `.authenticated` after the first run.
    private func handleSessionExpired() async {
        guard case .authenticated(let student) = authState, !student.isDemo else { return }
        print("🚪 [Auth] Session expired — auto-logging out")
        LastSchoolStore.remember(student: student, reason: .sessionExpired)
        lastSchoolHint = LastSchoolStore.load()
        selectingResumeSchool()
        // Match extension event name: unexpected Lectio session death.
        Analytics.capture("lectio session lost", properties: [
            "school_id": String(student.gymId),
            "school_name": student.schoolName ?? "",
            "detection_source": "http_session_expired",
        ])
        await authService.logout(student: student)
        Analytics.reset()
        authState = .unauthenticated
        choosingOtherSchool = false
        errorMessage = nil
    }

    private func selectingResumeSchool() {
        if let hint = lastSchoolHint {
            selectedSchool = hint.school
        } else {
            selectedSchool = nil
        }
    }

    // MARK: - Load Schools

    /// Seeds the picker with a small hardcoded list so the UI has something to show
    /// before the Supabase fetch completes (or if it fails). The full list is fetched
    /// by `loadSchoolsFromSupabase()` when the picker opens.
    func loadSchools() {
        schools = [
            School.demo,
            School(id: 9, name: "Gammel Hellerup Gymnasium"),
            School(id: 94, name: "Sorø Akademis Skole"),
            School(id: 242, name: "Aarhus Gymnasium"),
            School(id: 34, name: "Øregård Gymnasium"),
            School(id: 264, name: "Viborg Gymnasium"),
            School(id: 73, name: "Roskilde Gymnasium"),
            School(id: 289, name: "Aalborg Katedralskole")
        ]
    }

    /// Fetches the full list of schools from Supabase. Replaces the current `schools`
    /// array with `[Demo] + fetched` on success. On failure, keeps whatever is already
    /// loaded (the hardcoded seed or a prior successful fetch).
    func loadSchoolsFromSupabase(force: Bool = false) async {
        if hasLoadedSchoolsFromSupabase && !force { return }
        if isLoadingSchools { return }

        isLoadingSchools = true
        schoolLoadError = nil
        defer { isLoadingSchools = false }

        do {
            let fetched = try await SupabaseSchoolService.shared.fetchAllSchools()
            guard !fetched.isEmpty else {
                schoolLoadError = "Kunne ikke hente skoler"
                return
            }
            schools = [School.demo] + fetched
            hasLoadedSchoolsFromSupabase = true
        } catch {
            print("⚠️ [Auth] Failed to fetch schools from Supabase: \(error.localizedDescription)")
            schoolLoadError = "Kunne ikke hente skoler: \(error.localizedDescription)"
        }
    }

    // MARK: - Check Stored Credentials

    /// Restores authenticated state if credentials exist in Keychain. We deliberately do not
    /// check expiry dates — they're advisory, not gating. Lectio rotates stale-looking autologin
    /// cookies on the next request, so a "looks expired" state is not a reason to refuse to try.
    /// Only a missing student record or missing credentials means the user was never logged in;
    /// in those cases we wipe any residual auth state (WK cookies, orphan keychain entries,
    /// Supabase session) before showing LoginView so the next login starts from a clean slate.
    private func checkStoredCredentials() async {
        guard let student = authService.loadStoredStudent() else {
            print("📱 No stored student found — wiping any residual auth state")
            await authService.wipeAuthState()
            lastSchoolHint = LastSchoolStore.load()
            selectingResumeSchool()
            choosingOtherSchool = false
            authState = .unauthenticated
            return
        }

        if student.isDemo {
            print("🎭 Restoring demo session")
            Analytics.capture("demo_session_restored")
            authState = .authenticated(student)
            return
        }

        guard authService.hasStoredCredentials(for: student) else {
            print("📱 Stored student has no credentials — wiping and treating as signed out")
            LastSchoolStore.remember(student: student, reason: .sessionExpired)
            lastSchoolHint = LastSchoolStore.load()
            selectingResumeSchool()
            Analytics.capture("lectio session lost", properties: [
                "school_id": String(student.gymId),
                "school_name": student.schoolName ?? "",
                "detection_source": "missing_credentials_on_restore",
            ])
            await authService.wipeAuthState()
            Analytics.reset()
            choosingOtherSchool = false
            authState = .unauthenticated
            return
        }

        print("📱 Restoring session for: \(student.name ?? student.studentId)")

        // Cold-launch authentication work finishes before the authenticated UI appears.
        // Otherwise ScheduleView can race the Edge Function with the same Lectio token.
        guard await coldStartValidate(student: student) else { return }
        await ensureSupabaseSession(for: student)
        Analytics.identify(student)
        authState = .authenticated(student)

        // Directory sync is opportunistic; authenticated screens may now begin their own
        // requests, but all Lectio traffic shares the same priority-aware serial gate.
        Task {
            await DirectorySyncService.shared.syncDirectory(for: student)
        }
    }

    /// Background probe to detect a server-revoked session before any user-facing fetch fails
    /// (e.g. password change or admin action while the app was killed). Network/robot-detection
    /// errors do NOT trigger logout — we only want a definitive `.invalidCredentials` to mean
    /// the session is permanently dead.
    private func coldStartValidate(student: Student) async -> Bool {
        guard let credentials = KeychainManager.shared.loadCredentials(for: student.studentId) else {
            LastSchoolStore.remember(student: student, reason: .sessionExpired)
            lastSchoolHint = LastSchoolStore.load()
            selectingResumeSchool()
            Analytics.capture("lectio session lost", properties: [
                "school_id": String(student.gymId),
                "school_name": student.schoolName ?? "",
                "detection_source": "missing_credentials_on_restore",
            ])
            await authService.wipeAuthState()
            Analytics.reset()
            choosingOtherSchool = false
            authState = .unauthenticated
            return false
        }
        do {
            try await authService.coldStartValidate(credentials: credentials, schoolId: student.gymId, studentId: student.studentId)
            print("✅ [Auth] Cold-start validation OK")
            return true
        } catch LectioError.invalidCredentials {
            print("🚪 [Auth] Cold-start validation: session is dead — auto-logging out")
            LastSchoolStore.remember(student: student, reason: .sessionExpired)
            lastSchoolHint = LastSchoolStore.load()
            selectingResumeSchool()
            Analytics.capture("lectio session lost", properties: [
                "school_id": String(student.gymId),
                "school_name": student.schoolName ?? "",
                "detection_source": "cold_start_validation",
            ])
            await authService.logout(student: student)
            Analytics.reset()
            choosingOtherSchool = false
            authState = .unauthenticated
            return false
        } catch {
            print("⚠️ [Auth] Cold-start validation deferred (\(error.localizedDescription)) — will recover on next user fetch")
            return true
        }
    }

    /// If the SDK has no cached Supabase session on cold launch (e.g. first launch after
    /// install, long-idle period where the refresh token expired, or initial migration from
    /// the pre-SDK auth layer), silently re-mint a session via the existing magic-link flow
    /// using the Lectio credentials already in Keychain. No UI prompt; best-effort.
    private func ensureSupabaseSession(for student: Student) async {
        guard let client = SupabaseManager.shared.client else { return }
        if client.auth.currentSession != nil { return }

        guard let credentials = KeychainManager.shared.loadCredentials(for: student.studentId) else {
            return
        }

        print("🔄 [SupabaseAuth] No cached session — re-authenticating via Edge Function…")
        await SupabaseAuthService.shared.authenticateWithLectio(
            credentials: credentials,
            studentId: student.studentId,
            gymId: student.gymId
        )
    }

    // MARK: - Login with MitID

    /// One-tap MitID for the persisted last school.
    func resumeLastSchoolLogin() {
        guard let hint = lastSchoolHint else { return }
        selectedSchool = hint.school
        choosingOtherSchool = false
        loginWithMitID(source: "last_school_resume")
    }

    func chooseOtherSchool() {
        choosingOtherSchool = true
        // Keep hint; clear selection so picker is the path forward.
        selectedSchool = nil
        errorMessage = nil
    }

    func backToResumeLogin() {
        guard lastSchoolHint != nil else { return }
        choosingOtherSchool = false
        selectingResumeSchool()
        errorMessage = nil
    }

    /// Initiates MitID login flow
    func loginWithMitID(source: String = "school_picker") {
        guard let school = selectedSchool else {
            errorMessage = "Vælg en skole først"
            return
        }

        if school.isDemo {
            enterDemoMode()
            return
        }

        print("🔐 Starting MitID login for school: \(school.name)")
        Analytics.capture("login_started", properties: [
            "source": source,
            "login_method": "mitid",
        ])

        authenticationURL = authService.getAuthenticationURL(for: school)
        showWebView = true
        errorMessage = nil
    }

    // MARK: - Demo Mode

    /// Skips MitID entirely and authenticates with a synthetic demo Student.
    /// Used by Apple App Review to evaluate the app without real credentials.
    private func enterDemoMode() {
        do {
            let demo = try authService.enterDemoSession()
            Analytics.capture("demo_entered")
            authState = .authenticated(demo)
            errorMessage = nil
            showWebView = false
            isLoading = false
        } catch {
            handleError(error)
        }
    }

    // MARK: - Handle WebView Auth Complete

    /// Handles the result from the WebView authentication
    func handleWebViewAuthComplete(result: Result<WKWebView, Error>) {
        guard let school = selectedSchool else {
            errorMessage = "Ingen skole valgt"
            showWebView = false
            return
        }

        isLoading = true

        Task {
            do {
                switch result {
                case .success(let webView):
                    print("✅ WebView authentication successful")

                    // Complete authentication (extract cookies, validate, save)
                    let student = try await authService.completeAuthentication(
                        from: webView,
                        school: school
                    )

                    Analytics.identify(student)
                    Analytics.capture("login_completed", properties: ["login_method": "mitid"])
                    if let refreshed = LastSchoolHint.from(school: school) {
                        LastSchoolStore.save(refreshed)
                    }

                    // Update UI on main thread
                    await MainActor.run {
                        lastSchoolHint = LastSchoolStore.load()
                        choosingOtherSchool = false
                        authState = .authenticated(student)
                        showWebView = false
                        isLoading = false
                        errorMessage = nil
                        print("✅ Authentication complete for: \(student.name ?? student.studentId)")
                        
                        // Start background directory sync
                        Task {
                            await DirectorySyncService.shared.syncDirectory(for: student)
                        }
                    }

                case .failure(let error):
                    await MainActor.run {
                        Analytics.capture("login_failed", properties: ["error_type": String(describing: type(of: error))])
                        Analytics.capture(error, source: "webview_authentication")
                        handleError(error)
                        showWebView = false
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    Analytics.capture("login_failed", properties: ["error_type": String(describing: type(of: error))])
                    Analytics.capture(error, source: "authentication_completion")
                    handleError(error)
                    showWebView = false
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Logout

    /// Logs out the current user
    func logout() async {
        guard case .authenticated(let student) = authState else {
            return
        }
        if !student.isDemo {
            LastSchoolStore.remember(student: student, reason: .loggedOut)
            lastSchoolHint = LastSchoolStore.load()
            selectingResumeSchool()
        }
        Analytics.capture("logged_out")
        await authService.logout(student: student)
        Analytics.reset()
        authState = .unauthenticated
        choosingOtherSchool = false
        errorMessage = nil
        print("✅ Logout successful")
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        print("❌ Error: \(error.localizedDescription)")

        if let lectioError = error as? LectioError {
            switch lectioError {
            case .invalidURL:
                errorMessage = "Ugyldig webadresse (konfiguration)"
            case .noResponse:
                errorMessage = "Intet svar fra serveren"
            case .invalidCredentials:
                errorMessage = "Ugyldige oplysninger, eller log-in blev annulleret"
            case .networkError(let underlyingError):
                errorMessage = "Netværksfejl: \(underlyingError.localizedDescription)"
            case .cookieExpired:
                errorMessage = "Din session er udløbet. Log ind igen"
            case .missingCookies:
                errorMessage = "Godkendelse mislykkedes. Manglende nødvendige cookies"
            case .parsingError(let detail):
                errorMessage = "Kunne ikke behandle svaret: \(detail)"
            case .robotDetection:
                errorMessage = "Session ugyldig. Prøv igen"
            case .keychainError(let detail):
                errorMessage = "Sikkerhedsfejl: \(detail)"
            }
        } else {
            errorMessage = "Der opstod en fejl: \(error.localizedDescription)"
        }
    }

}
