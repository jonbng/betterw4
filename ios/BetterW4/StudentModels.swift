//
//  StudentModels.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Student

/// The signed-in person. W4 is one college on one host, so the UWC id is the whole identity:
/// there is no school id to scope by and no school to name (README §4.6).
///
/// A `Student` decoded from an older Keychain blob simply drops the keys that are gone —
/// `JSONDecoder` ignores what the type no longer declares — so no stored record can resurrect
/// a half-migrated row.
struct Student: Codable, Equatable, Hashable {
    let studentId: String
    let name: String?
    var pictureId: String?
    var classLabel: String?

    /// The UWC id alone. Used as a SwiftUI identity (`ContentView`'s `.task(id:)`); nothing
    /// persists it, so it is free to be exactly the id W4 knows the student by.
    var id: String { studentId }
}

// MARK: - Demo Mode

extension Student {
    static let demoStudentId = "demo"

    var isDemo: Bool { studentId == Student.demoStudentId }

    static let demo = Student(
        studentId: Student.demoStudentId,
        name: "Demo Student",
        pictureId: nil,
        classLabel: "3a"
    )
}

// MARK: - Local Credentials

/// W4's entire auth state: one cookie, `PHPSESSID` (README §4.1).
///
/// Host-only `w4.uwcrcn.no`, path `/`, `Secure`, not `HttpOnly`, no `Domain`, no `SameSite`,
/// and no expiry on the wire — it is a session cookie the server GCs on its own schedule.
/// There is no autologin key and no CSRF cookie, so there is nothing else to store and
/// nothing to reason about client-side regarding expiry.
struct W4Credentials: Codable, Equatable, Sendable {
    /// PHPSESSID — the session cookie every authenticated request needs.
    var sessionId: String

    /// Every other cookie W4 has set on this device, by name.
    ///
    /// The unauthenticated login page sets only `PHPSESSID`, which is where the "W4 has exactly
    /// one cookie" claim came from — but that capture could not see anything issued *after* a
    /// successful sign-in. A "remember this device" cookie is exactly that kind of cookie, and
    /// dropping it would silently defeat the feature: the box would be ticked, W4 would issue the
    /// cookie, and the app would throw it away before the next launch.
    ///
    /// So the jar keeps whatever W4 sends, and persists it with the session (this type is stored
    /// in the Keychain). Lectio-era names are refused outright — they can only arrive from a
    /// stale record, never from w4.uwcrcn.no.
    var additionalCookies: [String: String]

    init(sessionId: String = "", additionalCookies: [String: String] = [:]) {
        self.sessionId = sessionId
        self.additionalCookies = additionalCookies.filter { !Self.refusedNames.contains($0.key) }
    }

    /// Cookie names that must never be stored or sent. All Lectio; a W4 response cannot produce
    /// them, so their presence means a stale blob from an older install.
    static let refusedNames: Set<String> = [
        "ASP.NET_SessionId", "autologinkeyV2", "autologinkey", "isloggedin3" // legacy-name: a deny-list has to spell the names it refuses
    ]

    static let empty = W4Credentials()

    /// Emptiness is about the session, not the extras: a remember-me cookie without a PHPSESSID
    /// still means "you are signed out, go and get a session".
    var isEmpty: Bool { sessionId.isEmpty }

    // Hand-written so a record stored before `additionalCookies` existed still decodes rather
    // than throwing and logging the student out.
    private enum CodingKeys: String, CodingKey {
        case sessionId
        case additionalCookies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sessionId = try container.decode(String.self, forKey: .sessionId)
        let extras = try container.decodeIfPresent(
            [String: String].self,
            forKey: .additionalCookies
        ) ?? [:]
        self.init(sessionId: sessionId, additionalCookies: extras)
    }
}

// MARK: - Auth State

enum AuthState: Equatable {
    case loading
    case unauthenticated
    case authenticated(Student)

    var student: Student? {
        if case .authenticated(let student) = self {
            return student
        }
        return nil
    }

    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
}

// MARK: - Errors

extension Notification.Name {
    /// Posted when a HTTP request to W4 surfaces `W4Error.sessionExpired`.
    /// `AuthenticationViewModel` listens for this and force-logs out the current student.
    /// Idempotent: multiple posts during the same dead-session moment collapse into a
    /// single logout.
    static let w4SessionExpired = Notification.Name("dk.elliottf.betterw4.sessionExpired")
}

enum W4Error: Error, LocalizedError {
    case invalidURL
    case noResponse
    /// The username/password (or OTP) W4 was given is wrong. Not a dead session —
    /// this never triggers auto-logout.
    case invalidCredentials
    /// The PHPSESSID is dead (README §4.5 signals 1–3). The only error that logs the user out.
    case sessionExpired
    /// HTTP 403 without `Login Required`: signed in, wrong role. Must **not** log the user out —
    /// a student opening a staff-only page would otherwise be kicked to the login screen.
    case forbidden
    /// HTTP 409: W4's own error string is the body (`init_ajax.js` shows it verbatim).
    case serverConflict(String)
    /// Any other non-success status. Carries the route so a failure names the request that
    /// produced it — "HTTP 500" alone is unactionable when 20 surfaces are in flight.
    case httpError(status: Int, route: String)
    /// A feature still builds a Lectio URL. Blocked before it leaves the device: it would send
    /// a W4 session cookie to a third party and hit a server that cannot answer it.
    case notPortedToW4(host: String, context: String?)
    case networkError(Error)
    case cookieExpired
    case missingCookies
    case parsingError(String)
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid web address (configuration)"
        case .noResponse:
            return "No response from the server"
        case .invalidCredentials:
            return "Wrong username or password"
        case .sessionExpired:
            return "Your session has expired. Please log in again"
        case .forbidden:
            return "You do not have access to this page"
        case .serverConflict(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Error from remote server"
                : "Error from remote server: \(detail)"
        case .httpError(let status, let route):
            let where_ = route.isEmpty ? "" : " (r=\(route))"
            return status >= 500
                ? "W4 had a server error\(where_) — HTTP \(status)"
                : "W4 could not serve that page\(where_) — HTTP \(status)"
        case .notPortedToW4(let host, let context):
            let what = context.map { " (\($0))" } ?? ""
            return "This part of the app is not connected to W4 yet\(what) — it still points at \(host)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .cookieExpired:
            return "Your session has expired. Please log in again"
        case .missingCookies:
            return "Sign-in failed. W4 did not return a session cookie"
        case .parsingError(let detail):
            return "Could not read data: \(detail)"
        case .keychainError(let detail):
            return "Keychain error: \(detail)"
        }
    }
}

extension W4Error {
    /// Posts `.w4SessionExpired` if and only if this error is `.sessionExpired`.
    /// Call this from every catch site that handles a W4 fetch error, so auto-logout
    /// fires uniformly regardless of which screen surfaced the dead session first.
    /// `.forbidden` deliberately does nothing here — wrong role is not a dead session.
    func notifyIfSessionExpired() {
        if case .sessionExpired = self {
            NotificationCenter.default.post(name: .w4SessionExpired, object: nil)
        }
    }
}

// MARK: - Student Search Models
//
//  `DropdownEntityType` and `StudentEntry` lived here: the rows of Lectio's search dropdown,
//  keyed on a `S`/`T`/`HE`/`RO`/`GE` prefix plus a `gymId`, and the row type of the second
//  people table (`StudentStore`). W4 has one people table, two kinds of person and one id —
//  `DirectoryPerson` (`PeopleModels.swift`), served by `DirectoryRepository`. Both types are
//  deleted with `StudentStore` (plan Wave 6 item 6.5); nothing referenced them any more.
