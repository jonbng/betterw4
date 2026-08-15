//
//  LastSchoolStore.swift
//  BetterLectio
//
//  Non-secret last-school hint for one-tap MitID after logout / session expiry.
//  Never stores credentials, cookies, or student ids.
//

import Foundation

enum LastSchoolReason: String, Codable {
    case sessionExpired = "session_expired"
    case loggedOut = "logged_out"
}

struct LastSchoolHint: Equatable {
    let gymId: Int
    let schoolName: String
    let reason: LastSchoolReason

    var school: School {
        School(id: gymId, name: schoolName)
    }

    static func from(student: Student, reason: LastSchoolReason) -> LastSchoolHint? {
        guard !student.isDemo else { return nil }
        let name = (student.schoolName?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Gymnasium"
        return LastSchoolHint(gymId: student.gymId, schoolName: name, reason: reason)
    }

    static func from(school: School, reason: LastSchoolReason = .loggedOut) -> LastSchoolHint? {
        guard !school.isDemo else { return nil }
        let name = school.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return LastSchoolHint(gymId: school.id, schoolName: name, reason: reason)
    }
}

enum LastSchoolStore {
    private static let gymIdKey = "lastSchool.gymId"
    private static let schoolNameKey = "lastSchool.schoolName"
    private static let reasonKey = "lastSchool.reason"

    static func load() -> LastSchoolHint? {
        let defaults = UserDefaults.standard
        let gymId = defaults.integer(forKey: gymIdKey)
        // integer(forKey:) returns 0 when missing — reject unless a name was also stored.
        guard let name = defaults.string(forKey: schoolNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty,
            defaults.object(forKey: gymIdKey) != nil
        else {
            return nil
        }
        let reason = LastSchoolReason(rawValue: defaults.string(forKey: reasonKey) ?? "") ?? .loggedOut
        return LastSchoolHint(gymId: gymId, schoolName: name, reason: reason)
    }

    static func save(_ hint: LastSchoolHint) {
        let defaults = UserDefaults.standard
        defaults.set(hint.gymId, forKey: gymIdKey)
        defaults.set(hint.schoolName, forKey: schoolNameKey)
        defaults.set(hint.reason.rawValue, forKey: reasonKey)
    }

    static func remember(student: Student, reason: LastSchoolReason) {
        guard let hint = LastSchoolHint.from(student: student, reason: reason) else { return }
        save(hint)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: gymIdKey)
        defaults.removeObject(forKey: schoolNameKey)
        defaults.removeObject(forKey: reasonKey)
    }
}
