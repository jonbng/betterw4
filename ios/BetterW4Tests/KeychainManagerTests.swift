//
//  KeychainManagerTests.swift
//  BetterW4Tests
//
//  The Keychain is on the critical path of every login: the moment W4 accepts the password
//  (and the 2FA code) the session has to be persisted, or the user is bounced back to the
//  login screen with what looks like an authentication failure. These tests exercise the
//  real Keychain in the test host so a failure here is reported as a Keychain problem
//  rather than as "wrong code".
//

import XCTest
@testable import BetterW4

final class KeychainManagerTests: XCTestCase {

    private let studentId = "nc00test"

    override func setUp() {
        super.setUp()
        try? KeychainManager.shared.deleteCredentials(for: studentId)
        try? KeychainManager.shared.deleteStudent()
    }

    override func tearDown() {
        try? KeychainManager.shared.deleteCredentials(for: studentId)
        try? KeychainManager.shared.deleteStudent()
        super.tearDown()
    }

    /// Reports the raw OSStatus on failure — -34018 is errSecMissingEntitlement,
    /// -25299 errSecDuplicateItem, -25300 errSecItemNotFound.
    func testCredentialsRoundTrip() throws {
        let credentials = W4Credentials(sessionId: "abc123sessionid")

        XCTAssertNoThrow(
            try KeychainManager.shared.saveCredentials(credentials, for: studentId),
            "Saving credentials threw — the OSStatus in the message is the real error"
        )

        let loaded = KeychainManager.shared.loadCredentials(for: studentId)
        XCTAssertEqual(loaded?.sessionId, "abc123sessionid")
    }

    /// The second login must overwrite the first, not fail with errSecDuplicateItem.
    func testSavingTwiceOverwritesRatherThanFailing() throws {
        try KeychainManager.shared.saveCredentials(W4Credentials(sessionId: "first"), for: studentId)
        try KeychainManager.shared.saveCredentials(W4Credentials(sessionId: "second"), for: studentId)
        XCTAssertEqual(KeychainManager.shared.loadCredentials(for: studentId)?.sessionId, "second")
    }

    func testStudentRoundTrip() throws {
        let student = Student(
            studentId: studentId,
            name: "Test Student",
            pictureId: nil,
            classLabel: nil
        )
        XCTAssertNoThrow(try KeychainManager.shared.saveStudent(student))
        XCTAssertEqual(KeychainManager.shared.loadStudent()?.studentId, studentId)
    }

    /// The per-install device id must survive, and must be stable — a new id means W4 treats
    /// every launch as a new device and demands a fresh 2FA code every time.
    func testDeviceIDIsStableAcrossCalls() {
        let first = W4DeviceID.current()
        let second = W4DeviceID.current()
        XCTAssertFalse(first.isEmpty, "Device id is empty — LoginForm[deviceId] would be blank")
        XCTAssertEqual(first, second, "Device id changed between calls — 2FA on every launch")
    }

    /// Logging out wipes the session but must NOT take the device id with it.
    func testWipeAllKeepsTheDeviceID() throws {
        let before = W4DeviceID.current()
        try KeychainManager.shared.saveCredentials(W4Credentials(sessionId: "x"), for: studentId)

        KeychainManager.shared.wipeAll()

        XCTAssertNil(KeychainManager.shared.loadCredentials(for: studentId))
        XCTAssertEqual(W4DeviceID.current(), before, "wipeAll destroyed the device id")
    }
}
