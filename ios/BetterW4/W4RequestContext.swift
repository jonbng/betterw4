//
//  W4RequestContext.swift
//  BetterW4
//
//  The three things every repository needs before it can talk to W4: who is signed in, their
//  PHPSESSID, and whether this is a demo session that must never touch the network.
//
//  Without this, each of a dozen repositories would repeat the same "load the student, load the
//  credentials, bail out if either is missing, branch on demo" preamble — and the demo branch is
//  exactly the one an author forgets, which is how a demo build ends up making live requests.
//

import Foundation

struct W4RequestContext: Sendable {
    let student: Student
    let credentials: W4Credentials

    /// The signed-in student's UWC id (`nc26abcd`). Cache scope key and Keychain account key.
    var uwcId: String { student.studentId }

    /// Roster id for "You" — demo sessions use the invented person on demo class pages.
    var rosterUwcId: String {
        student.isDemo ? DemoDataProvider.uwcId : student.studentId
    }

    /// True when the app is in the offline demo session used for App Review.
    var isDemo: Bool { student.isDemo }

    // MARK: - Resolution

    /// The current session, or `nil` when nobody is signed in.
    ///
    /// Demo returns a context with empty credentials on purpose: repositories branch on `isDemo`
    /// *before* fetching, so a demo session never has a session id to leak in the first place.
    static func current(keychain: KeychainManager = .shared) -> W4RequestContext? {
        guard let student = keychain.loadStudent() else { return nil }

        if student.isDemo {
            return W4RequestContext(student: student, credentials: .empty)
        }

        guard let credentials = keychain.loadCredentials(for: student.studentId),
              !credentials.isEmpty else {
            return nil
        }
        return W4RequestContext(student: student, credentials: credentials)
    }

    /// The current session, or a thrown error when there is none.
    ///
    /// Throws `.sessionExpired` rather than `.missingCookies` when a student record exists but its
    /// credentials are gone: that combination means the session died, and the app should route the
    /// user back to the login screen rather than show a generic failure.
    static func require(keychain: KeychainManager = .shared) throws -> W4RequestContext {
        if let context = current(keychain: keychain) { return context }
        if keychain.loadStudent() != nil { throw W4Error.sessionExpired }
        throw W4Error.missingCookies
    }
}
