//
//  AuthenticationService.swift
//  BetterW4
//
//  Native W4 authentication: username + password (+ OTP), PHPSESSID in the Keychain,
//  identity read out of the page chrome. No WebView, no MitID, no school picker.
//  README §4.4 / §4.5, reviewer-notes §5 / §6.
//

import Foundation

/// Everything the app does with a W4 session: sign in, restore, validate, sign out.
///
/// The two-step login (password, then a one-time code when W4 challenges) is driven by
/// `W4LoginClient`; this type turns its result into a persisted `Student` and keeps the
/// Keychain, the WebKit cookie stores and the local caches in sync with it.
class AuthenticationService {
    private let cookieManager = CookieManager.shared
    private let keychainManager = KeychainManager.shared
    private let httpClient = W4HTTPClient()

    /// W4 is a single college on a single host, so this is a constant, not a picked value.
    /// It is display copy for the sign-in screen only — it is never stored on `Student` and
    /// never reaches a URL or a cache key.
    static let collegeName = "UWC Red Cross Nordic"

    /// What one login attempt produced.
    enum LoginOutcome {
        /// Signed in; credentials and the student record are already persisted.
        case authenticated(Student)
        /// W4 wants a one-time code. Answer with `submitOTP(_:code:)` and this challenge.
        case needsOTP(W4OTPChallenge)
        /// Rejected. `message` is W4's own wording when it gave any; `invalidOTP` marks a
        /// rejected code (the password was fine) so the UI can stay on the code field.
        case failed(message: String?, invalidOTP: Bool)
    }

    // MARK: - Log in

    /// Step 1: `GET r=site/login` for a `PHPSESSID`, then POST the form W4 actually rendered.
    func logIn(username: String, password: String) async throws -> LoginOutcome {
        let step = try await W4LoginClient.submitPassword(username: username, password: password)
        return try await complete(step)
    }

    /// Step 2: answer the 2FA page with the challenge captured while we were standing on it.
    func submitOTP(_ challenge: W4OTPChallenge, code: String) async throws -> LoginOutcome {
        let step = try await W4LoginClient.submitOTP(challenge, code: code)
        return try await complete(step)
    }

    private func complete(_ step: W4LoginStep) async throws -> LoginOutcome {
        switch step {
        case .needsOTP(let challenge):
            return .needsOTP(challenge)

        case .failed(let message, let invalidOTP):
            return .failed(message: message, invalidOTP: invalidOTP)

        case .authenticated(let credentials, let html, let finalURL):
            let student = try await persistSession(
                credentials: credentials,
                html: html,
                finalURL: finalURL
            )
            return .authenticated(student)
        }
    }

    /// Identity comes from the authenticated page chrome — `Welcome, {name}` in `#user-panel`
    /// and the UWC id on the student's own public-profile link. There is no JSON profile
    /// endpoint and no numeric student id (reviewer-notes §6).
    private func persistSession(
        credentials: W4Credentials,
        html: String,
        finalURL: URL
    ) async throws -> Student {
        var sessionCredentials = credentials
        var pageHTML = html

        // The post-login landing page is usually Home, but a 302 can drop us somewhere with
        // thinner chrome. One cheap GET of `r=site/index` is worth it before giving up.
        if W4Html.uwcId(pageHTML) == nil || W4Html.displayName(pageHTML) == nil {
            print("ℹ️ [Auth] No chrome on \(W4Routes.route(of: finalURL) ?? "?") — reading identity from Home")
            if let home = try? await httpClient.get(
                route: W4Routes.R.home,
                credentials: sessionCredentials,
                studentId: nil,
                priority: .important
            ) {
                sessionCredentials = home.updatedCredentials ?? sessionCredentials
                pageHTML = httpClient.decodeHTML(from: home.data)
            }
        }

        guard let studentId = W4Html.uwcId(pageHTML) else {
            throw W4Error.parsingError("W4 did not show your UWC id after signing in")
        }
        guard !sessionCredentials.isEmpty else {
            throw W4Error.missingCookies
        }

        let student = Student(
            studentId: studentId,
            name: W4Html.displayName(pageHTML)
        )

        // A different account than last time: drop the old blobs rather than leaving an
        // orphaned per-student credential entry behind. The device id lives under its own
        // Keychain service and deliberately survives this.
        if let previous = keychainManager.loadStudent(), previous.studentId != studentId {
            print("🧹 [Auth] Different account than last sign-in — clearing the previous Keychain entries")
            keychainManager.wipeAll()
        }

        try keychainManager.saveCredentials(sessionCredentials, for: studentId)
        try keychainManager.saveStudent(student)
        await cookieManager.syncCredentialsToWebViews(sessionCredentials)

        print("✅ [Auth] Signed in as \(studentId)")
        return student
    }

    // MARK: - Demo mode

    /// A synthetic session for App Review: no network, no credentials, nothing sent to W4.
    /// The demo `Student` is persisted so a cold launch stays in demo mode.
    func enterDemoSession() throws -> Student {
        keychainManager.wipeAll()
        let demo = Student.demo
        try keychainManager.saveStudent(demo)
        print("🎭 [Auth] Entered demo session")
        return demo
    }

    // MARK: - Restore

    func loadStoredStudent() -> Student? {
        keychainManager.loadStudent()
    }

    /// A stored `PHPSESSID` exists. We never gate on an expiry date — W4's cookie carries no
    /// expiry at all, and only the server knows whether the session is still alive.
    func hasStoredCredentials(for student: Student) -> Bool {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
            return false
        }
        return !credentials.isEmpty
    }

    /// Cold-start probe: one cheap authenticated `GET r=site/index`.
    ///
    /// Throws `W4Error.sessionExpired` when the stored `PHPSESSID` is dead — the HTTP client
    /// classifies signals 1–3 from README §4.5 for us. Network and parsing errors propagate
    /// unchanged so the caller can keep the user signed in and recover on the next fetch.
    func validateStoredSession(for student: Student) async throws {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId),
              !credentials.isEmpty else {
            throw W4Error.sessionExpired
        }

        let result = try await httpClient.get(
            route: W4Routes.R.home,
            credentials: credentials,
            studentId: student.studentId,
            priority: .important
        )

        let fresh = result.updatedCredentials ?? credentials
        try? keychainManager.updateCredentials(fresh, for: student.studentId)
        await cookieManager.syncCredentialsToWebViews(fresh)

        // README §4.5 signal 6 is the least reliable one, so it warns rather than logs out:
        // a 200 that is not the login form already means the session answered for us.
        if !W4Html.isAuthenticatedHTML(httpClient.decodeHTML(from: result.data)) {
            print("⚠️ [Auth] Home answered 200 without the usual chrome — keeping the session")
        }
    }

    // MARK: - Log out

    /// Deliberate sign-out: tell W4, then remove every local trace of the session.
    func logout(student: Student) async {
        print("🚪 [Auth] Logging out \(student.studentId)")
        if !student.isDemo {
            await requestServerLogout(for: student)
        }
        await MessageCacheManager.clearCache(studentId: student.studentId)
        await wipeAuthState()
        print("✅ [Auth] Logout complete")
    }

    /// `GET index.php?r=site/logout`. It answers with a redirect to the login page, which is
    /// success here, so the request opts into seeing login pages. Failure is not fatal —
    /// the local wipe happens either way.
    private func requestServerLogout(for student: Student) async {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId),
              !credentials.isEmpty else { return }
        do {
            _ = try await httpClient.get(
                route: W4Routes.R.logout,
                credentials: credentials,
                // nil: this session is being torn down, so nothing should be written back
                // to the Keychain entry we are about to delete.
                studentId: nil,
                priority: .important,
                allowLoginPage: true
            )
        } catch {
            print("⚠️ [Auth] W4 logout request failed (\(error.localizedDescription)) — wiping locally anyway")
        }
    }

    /// Wipes every piece of auth state: the app's Keychain items (credentials + the current
    /// student record), the cached profile images and the whole WebKit jar. Idempotent, so it
    /// is also safe on cold start to scrub residue from a crash mid-logout or an old install.
    ///
    /// The per-install device id survives on purpose — it lives under its own Keychain service
    /// and regenerating it would make W4 demand a fresh 2FA code on every launch.
    func wipeAuthState() async {
        await PublicProfileImageLoader.shared.clearCache()
        keychainManager.wipeAll()
        await cookieManager.clearAllWebViewData()
    }

    /// The server killed the session under us. Drop the credentials so the app returns to the
    /// login screen, but leave the offline caches (schedule, messages, homework, directory)
    /// alone — the student should still see their data the moment they sign back in.
    func dropExpiredSession(for student: Student) async {
        try? keychainManager.deleteCredentials(for: student.studentId)
        try? keychainManager.deleteStudent()
        await cookieManager.removeSessionCookieFromWebViews()
    }
}
