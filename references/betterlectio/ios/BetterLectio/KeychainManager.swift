//
//  KeychainManager.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import Security

/// Manages secure storage of Lectio credentials in the iOS Keychain
class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    private let service = "dk.elliottf.betterlectio"

    // MARK: - Save Credentials

    /// Saves Lectio credentials securely in the Keychain
    func saveCredentials(_ credentials: LectioCredentials, for studentId: String) throws {
        let key = credentialsKey(for: studentId)

        // Encode credentials to Data
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)

        // Check if credentials already exist
        if loadCredentials(for: studentId) != nil {
            // Update existing credentials
            try updateCredentials(credentials, for: studentId)
        } else {
            // Add new credentials
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let status = SecItemAdd(query as CFDictionary, nil)

            guard status == errSecSuccess else {
                throw LectioError.keychainError("Kunne ikke gemme loginoplysninger: \(status)")
            }
        }
    }

    // MARK: - Load Credentials

    /// Loads Lectio credentials from the Keychain
    func loadCredentials(for studentId: String) -> LectioCredentials? {
        let key = credentialsKey(for: studentId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        // Decode credentials from Data
        let decoder = JSONDecoder()
        guard let creds = try? decoder.decode(LectioCredentials.self, from: data) else {
            return nil
        }

        // Pre-app-update keychain entries only had the two primaries. Dart always sends `isloggedin3`;
        // seed it once so native requests match browser/Dart without forcing a re-login.
        if creds.additionalCookies["isloggedin3"] == nil {
            var extras = creds.additionalCookies
            extras["isloggedin3"] = "Y"
            let migrated = LectioCredentials(
                autologinkey: creds.autologinkey,
                sessionId: creds.sessionId,
                autologinkeyExpiresAt: creds.autologinkeyExpiresAt,
                sessionIdExpiresAt: creds.sessionIdExpiresAt,
                additionalCookies: extras
            )
            try? updateCredentials(migrated, for: studentId)
            print("📌 Migrated keychain credentials: seeded isloggedin3=Y")
            return migrated
        }

        return creds
    }

    // MARK: - Update Credentials

    /// Updates existing Lectio credentials in the Keychain
    func updateCredentials(_ credentials: LectioCredentials, for studentId: String) throws {
        let key = credentialsKey(for: studentId)

        // Encode credentials to Data
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw LectioError.keychainError("Kunne ikke opdatere loginoplysninger: \(status)")
        }
    }

    // MARK: - Delete Credentials

    /// Deletes Lectio credentials from the Keychain
    func deleteCredentials(for studentId: String) throws {
        let key = credentialsKey(for: studentId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LectioError.keychainError("Kunne ikke slette loginoplysninger: \(status)")
        }
    }

    // MARK: - Save Student

    /// Saves student info to Keychain for persistence
    func saveStudent(_ student: Student) throws {
        let key = "lectio.student.current"

        // Encode student to Data
        let encoder = JSONEncoder()
        let data = try encoder.encode(student)

        // Check if student already exists
        if loadStudent() != nil {
            // Update existing student
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

            guard status == errSecSuccess else {
                throw LectioError.keychainError("Kunne ikke opdatere elev: \(status)")
            }
        } else {
            // Add new student
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let status = SecItemAdd(query as CFDictionary, nil)

            guard status == errSecSuccess else {
                throw LectioError.keychainError("Kunne ikke gemme elev: \(status)")
            }
        }
    }

    // MARK: - Load Student

    /// Loads current student from Keychain
    func loadStudent() -> Student? {
        let key = "lectio.student.current"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        // Decode student from Data
        let decoder = JSONDecoder()
        return try? decoder.decode(Student.self, from: data)
    }

    // MARK: - Delete Student

    /// Deletes current student from Keychain
    func deleteStudent() throws {
        let key = "lectio.student.current"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LectioError.keychainError("Kunne ikke slette elev: \(status)")
        }
    }

    // MARK: - Wipe

    /// Removes every Keychain item this app stores (all per-student credentials + the
    /// current-student record) in a single call. Called on logout so no residual auth
    /// state is left behind to confuse the next login.
    func wipeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("⚠️ [Keychain] wipeAll status: \(status)")
        }
    }

    // MARK: - Helper

    private func credentialsKey(for studentId: String) -> String {
        "lectio.credentials.\(studentId)"
    }
}
