//
//  StudentModels.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Student

struct Student: Codable, Equatable, Hashable {
    let studentId: String
    let gymId: Int
    let name: String?
    var pictureId: String?
    var classLabel: String?
    var schoolName: String?

    var id: String {
        "\(studentId)_\(gymId)"
    }
}

// MARK: - Demo Mode

extension Student {
    static let demoStudentId = "demo"
    static let demoGymId = -1

    var isDemo: Bool { studentId == Student.demoStudentId }

    static let demo = Student(
        studentId: Student.demoStudentId,
        gymId: Student.demoGymId,
        name: "Demo Student",
        pictureId: nil,
        classLabel: "3a",
        schoolName: "Demo School"
    )
}

extension School {
    static let demoId = -1
    static let demo = School(id: School.demoId, name: "Demo School")
    var isDemo: Bool { id == School.demoId }
}

// MARK: - School

struct School: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Local Credentials

/// Native requests mirror Dart's cookie jar: primaries plus every other `lectio.dk` cookie we snapshot from WKWebView and merge from `Set-Cookie`.
struct LectioCredentials: Codable, Equatable {
    let autologinkey: String
    let sessionId: String
    let autologinkeyExpiresAt: Date
    let sessionIdExpiresAt: Date
    /// All other auth-related cookies (e.g. `isloggedin3`). Keys must not duplicate the two primaries.
    let additionalCookies: [String: String]

    enum CodingKeys: String, CodingKey {
        case autologinkey
        case sessionId
        case autologinkeyExpiresAt
        case sessionIdExpiresAt
        case additionalCookies
    }

    init(
        autologinkey: String,
        sessionId: String,
        autologinkeyExpiresAt: Date,
        sessionIdExpiresAt: Date,
        additionalCookies: [String: String] = [:]
    ) {
        self.autologinkey = autologinkey
        self.sessionId = sessionId
        self.autologinkeyExpiresAt = autologinkeyExpiresAt
        self.sessionIdExpiresAt = sessionIdExpiresAt
        self.additionalCookies = additionalCookies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autologinkey = try c.decode(String.self, forKey: .autologinkey)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        autologinkeyExpiresAt = try c.decode(Date.self, forKey: .autologinkeyExpiresAt)
        sessionIdExpiresAt = try c.decode(Date.self, forKey: .sessionIdExpiresAt)
        additionalCookies = try c.decodeIfPresent([String: String].self, forKey: .additionalCookies) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autologinkey, forKey: .autologinkey)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(autologinkeyExpiresAt, forKey: .autologinkeyExpiresAt)
        try c.encode(sessionIdExpiresAt, forKey: .sessionIdExpiresAt)
        if !additionalCookies.isEmpty {
            try c.encode(additionalCookies, forKey: .additionalCookies)
        }
    }

    var isValid: Bool {
        autologinkeyExpiresAt > Date()
    }

    var isExpiringSoon: Bool {
        // Consider expired if less than 1 day remaining
        let oneDayFromNow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return autologinkeyExpiresAt < oneDayFromNow
    }
}

extension LectioCredentials {
    /// Clears the stored `ASP.NET_SessionId` (primary field and any duplicate in `additionalCookies`); `autologinkeyV2` is unchanged.
    func clearingASPNETSessionId() -> LectioCredentials {
        var extras = additionalCookies
        extras.removeValue(forKey: "ASP.NET_SessionId")
        return LectioCredentials(
            autologinkey: autologinkey,
            sessionId: "",
            autologinkeyExpiresAt: autologinkeyExpiresAt,
            sessionIdExpiresAt: .distantPast,
            additionalCookies: extras
        )
    }

    /// Replaces the stored `ASP.NET_SessionId` (and removes any duplicate in `additionalCookies`). Expiry is advisory, matching WK snapshot defaults.
    func withASPNETSessionId(_ newSessionId: String) -> LectioCredentials {
        var extras = additionalCookies
        extras.removeValue(forKey: "ASP.NET_SessionId")
        return LectioCredentials(
            autologinkey: autologinkey,
            sessionId: newSessionId,
            autologinkeyExpiresAt: autologinkeyExpiresAt,
            sessionIdExpiresAt: Date().addingTimeInterval(60 * 60 * 24 * 60),
            additionalCookies: extras
        )
    }

    /// Clears the stored `autologinkeyV2` (primary field and any duplicate in `additionalCookies`); `ASP.NET_SessionId` is unchanged.
    func clearingAutologinkeyV2() -> LectioCredentials {
        var extras = additionalCookies
        extras.removeValue(forKey: "autologinkeyV2")
        return LectioCredentials(
            autologinkey: "",
            sessionId: sessionId,
            autologinkeyExpiresAt: .distantPast,
            sessionIdExpiresAt: sessionIdExpiresAt,
            additionalCookies: extras
        )
    }

    /// Replaces the stored `autologinkeyV2` (and removes any duplicate in `additionalCookies`). Expiry is advisory, matching WK snapshot defaults.
    func withAutologinkeyV2(_ newKey: String) -> LectioCredentials {
        var extras = additionalCookies
        extras.removeValue(forKey: "autologinkeyV2")
        return LectioCredentials(
            autologinkey: newKey,
            sessionId: sessionId,
            autologinkeyExpiresAt: Date().addingTimeInterval(60 * 60 * 24 * 60),
            sessionIdExpiresAt: sessionIdExpiresAt,
            additionalCookies: extras
        )
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
    /// Posted when a HTTP request to Lectio surfaces `LectioError.invalidCredentials` after
    /// the client's internal retry loop has exhausted. `AuthenticationViewModel` listens for
    /// this and force-logs out the current student. Idempotent: multiple posts during the
    /// same dead-session moment collapse into a single logout.
    static let lectioSessionExpired = Notification.Name("dk.elliottf.betterlectio.sessionExpired")
}

enum LectioError: Error, LocalizedError {
    case invalidURL
    case noResponse
    case invalidCredentials
    case networkError(Error)
    case cookieExpired
    case missingCookies
    case parsingError(String)
    case robotDetection
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ugyldig webadresse (konfiguration)"
        case .noResponse:
            return "Intet svar fra serveren"
        case .invalidCredentials:
            return "Ugyldige oplysninger, eller log-in blev annulleret"
        case .networkError(let error):
            return "Netværksfejl: \(error.localizedDescription)"
        case .cookieExpired:
            return "Din session er udløbet. Log ind igen"
        case .missingCookies:
            return "Godkendelse mislykkedes. Manglende nødvendige cookies"
        case .parsingError(let detail):
            return "Kunne ikke læse data: \(detail)"
        case .robotDetection:
            return "Session ugyldig, eller robot-detektion udløst"
        case .keychainError(let detail):
            return "Nøglering-fejl: \(detail)"
        }
    }
}

extension LectioError {
    /// Posts `.lectioSessionExpired` if and only if this error is `.invalidCredentials`.
    /// Call this from every catch site that handles a Lectio fetch error, so auto-logout
    /// fires uniformly regardless of which screen surfaced the dead session first.
    func notifyIfSessionExpired() {
        if case .invalidCredentials = self {
            NotificationCenter.default.post(name: .lectioSessionExpired, object: nil)
        }
    }
}

// MARK: - Student Search Models

enum DropdownEntityType: String, Codable, CaseIterable {
    case student = "S"
    case teacher = "T"
    case team = "HE"
    case room = "RO"
    case group = "GE"
    case other = "O"
    
    var displayName: String {
        switch self {
        case .student: return "Elev"
        case .teacher: return "Lærer"
        case .team: return "Hold"
        case .room: return "Lokale"
        case .group: return "Gruppe"
        case .other: return "Andet"
        }
    }
}

struct StudentEntry: Codable, Identifiable, Equatable, Hashable {
    let studentId: String
    let name: String
    let classLabel: String
    let classNumber: String
    let gymId: Int
    let type: DropdownEntityType

    var isTeacher: Bool { type == .teacher }

    init(studentId: String, name: String, classLabel: String, classNumber: String, gymId: Int, type: DropdownEntityType = .student) {
        self.studentId = studentId
        self.name = name
        self.classLabel = classLabel
        self.classNumber = classNumber
        self.gymId = gymId
        self.type = type
    }

    var id: String { "\(studentId)_\(gymId)" }

    /// Returns initials from the student's name (first letter of first and last name)
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Consistent color derived from name hash
    var color: Int {
        abs(name.hashValue) % 12
    }

    /// Class to display (e.g. "3a"). Filters invalid values like "NSManagedObject".
    var displayClass: String {
        let invalid = classLabel.isEmpty
            || classLabel.localizedCaseInsensitiveContains("NSManagedObject")
        guard !invalid else { return "" }
        return classLabel
    }

    var asMessageRecipient: MessageRecipient {
        MessageRecipient(
            id: "\(type.rawValue)\(studentId)",
            name: name,
            type: isTeacher ? .teacher : .student,
            info: displayClass.isEmpty ? nil : displayClass,
            lectioRecipientID: "\(type.rawValue)\(studentId)"
        )
    }
}
