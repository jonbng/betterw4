//
//  AuthenticationViewModel.swift
//  BetterW4
//
//  Drives loading → unauthenticated → authenticated for W4's native login.
//

import Combine
import Foundation
import SwiftUI

/// The app's single source of truth for "who is signed in".
///
/// W4's login is two POSTs: username + password, then a one-time code when W4 challenges the
/// device. `otpChallenge` is what is held between them — non-nil means the UI should be
/// showing the code field.
@MainActor
final class AuthenticationViewModel: ObservableObject {
    enum AuthState: Equatable {
        case loading
        case unauthenticated
        case authenticated(Student)
    }

    // MARK: - Published surface

    @Published private(set) var authState: AuthState = .loading
    /// Non-nil ⇒ W4 asked for a one-time code; answer it with `submitOTP(code:)`.
    @Published private(set) var otpChallenge: W4OTPChallenge?
    /// A login / OTP / demo / logout call is in flight.
    @Published private(set) var isSubmitting = false
    /// W4's own rejection wording when it gave one, otherwise ours. Writable so a view can
    /// dismiss it.
    @Published var errorMessage: String?

    // MARK: - Services

    private let authService = AuthenticationService()

    // MARK: - Lifecycle

    init() {
        // Any HTTP path that classifies a dead `PHPSESSID` posts this (README §4.5 signals
        // 1–3). `.forbidden` deliberately does not, so a staff-only page never signs a
        // student out.
        NotificationCenter.default.addObserver(
            forName: .w4SessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleSessionExpired() }
        }

        Task { @MainActor [weak self] in await self?.restoreSession() }
    }

    // MARK: - Restore

    /// Cold start: load the stored student, then confirm the stored session is still alive.
    func restoreSession() async {
        guard let student = authService.loadStoredStudent() else {
            print("📱 [Auth] No stored student — wiping any residual auth state")
            await authService.wipeAuthState()
            authState = .unauthenticated
            return
        }

        if student.isDemo {
            print("🎭 [Auth] Restoring demo session")
            authState = .authenticated(student)
            return
        }

        guard authService.hasStoredCredentials(for: student) else {
            print("📱 [Auth] Stored student has no session cookie — treating as signed out")
            await authService.wipeAuthState()
            authState = .unauthenticated
            return
        }

        print("📱 [Auth] Restoring session for \(student.name ?? student.studentId)")

        do {
            // Finish this before the authenticated UI appears, so the tabs do not race the
            // probe with the same cookie.
            try await authService.validateStoredSession(for: student)
        } catch W4Error.sessionExpired {
            print("🚪 [Auth] Stored session is dead — back to the login screen")
            await authService.dropExpiredSession(for: student)
            authState = .unauthenticated
            errorMessage = sessionExpiredMessage
            return
        } catch {
            // Offline, a timeout, a parse hiccup: not proof the session died. Stay signed in
            // and let the next real fetch surface the problem.
            print("⚠️ [Auth] Session check deferred (\(error.localizedDescription))")
        }

        authState = .authenticated(student)
        startBackgroundSync(for: student)
    }

    // MARK: - Log in

    func logIn(username: String, password: String) async {
        guard !isSubmitting else { return }

        let trimmedUsername = W4Username.normalize(username)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your username and password."
            return
        }

        isSubmitting = true
        errorMessage = nil
        otpChallenge = nil
        defer { isSubmitting = false }

        do {
            let outcome = try await authService.logIn(username: trimmedUsername, password: password)
            apply(outcome)
        } catch {
            handle(error)
        }
    }

    func submitOTP(code: String) async {
        guard !isSubmitting, let challenge = otpChallenge else { return }

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Enter the code W4 sent you."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let outcome = try await authService.submitOTP(challenge, code: trimmedCode)
            apply(outcome)
        } catch {
            handle(error)
        }
    }

    /// Abandon the 2FA step and go back to username + password. The half-finished W4 session
    /// is simply dropped; the next attempt starts from a fresh `GET r=site/login`.
    func cancelOTP() {
        otpChallenge = nil
        errorMessage = nil
    }

    // MARK: - Demo mode

    /// Sign in with a synthetic student. No network traffic of any kind.
    func enterDemoMode() async {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil
        otpChallenge = nil
        defer { isSubmitting = false }

        do {
            let demo = try authService.enterDemoSession()
            authState = .authenticated(demo)
            startBackgroundSync(for: demo)
        } catch {
            handle(error)
        }
    }

    // MARK: - Log out

    func logout() async {
        guard case .authenticated(let student) = authState else { return }

        isSubmitting = true
        await authService.logout(student: student)
        isSubmitting = false

        // Pending reminders name this student's lessons and assessments. They have to go with the
        // session, for the same reason the caches do: the next person to hold the phone must not
        // get a notification about the last one's timetable.
        await NotificationScheduler.shared.clearAll()

        otpChallenge = nil
        errorMessage = nil
        authState = .unauthenticated
    }

    /// Force-logout when any HTTP path surfaces a definitively dead W4 session.
    ///
    /// Idempotent: concurrent posts from several view models collapse into one, because
    /// `authState` is no longer `.authenticated` after the first run. Offline caches are left
    /// intact — a dead cookie is not a reason to throw away the student's data.
    private func handleSessionExpired() async {
        guard case .authenticated(let student) = authState, !student.isDemo else { return }
        print("🚪 [Auth] Session expired — returning to the login screen")
        await authService.dropExpiredSession(for: student)
        otpChallenge = nil
        authState = .unauthenticated
        errorMessage = sessionExpiredMessage
    }

    // MARK: - Outcome / error handling

    private func apply(_ outcome: AuthenticationService.LoginOutcome) {
        switch outcome {
        case .authenticated(let student):
            otpChallenge = nil
            errorMessage = nil
            authState = .authenticated(student)
            startBackgroundSync(for: student)

        case .needsOTP(let challenge):
            // A second challenge while one is already showing means W4 re-rendered the 2FA
            // form — i.e. it did not accept the code.
            let isRetry = otpChallenge != nil
            otpChallenge = challenge
            errorMessage = isRetry ? "That code was not accepted. Try again." : nil

        case .failed(let message, let invalidOTP):
            if invalidOTP {
                // The password was fine; only the code was rejected. Stay on the code field.
                errorMessage = message ?? "That code was not accepted. Try again."
            } else {
                otpChallenge = nil
                errorMessage = message ?? "Wrong username or password."
            }
        }
    }

    /// Deliberately not an exhaustive `switch` over `W4Error`: every case already carries an
    /// English `errorDescription`, and new cases must not break this file.
    private func handle(_ error: Error) {
        print("❌ [Auth] \(error.localizedDescription)")

        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }

        if let w4Error = error as? W4Error {
            errorMessage = w4Error.errorDescription ?? "Could not sign in. Please try again."
            return
        }
        errorMessage = "Could not sign in: \(error.localizedDescription)"
    }

    private var sessionExpiredMessage: String {
        W4Error.sessionExpired.errorDescription ?? "Your session has expired. Please log in again"
    }

    /// Opportunistic; the authenticated screens may start their own requests immediately
    /// because all W4 traffic shares one priority-aware serial gate.
    private func startBackgroundSync(for student: Student) {
        Task {
            await DirectorySyncService.shared.syncDirectory(for: student)
        }
    }
}

// MARK: - AuthState conveniences

extension AuthenticationViewModel.AuthState {
    var student: Student? {
        if case .authenticated(let student) = self { return student }
        return nil
    }
}
