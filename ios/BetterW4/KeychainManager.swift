//
//  KeychainManager.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import Security

/// Secure storage for W4 auth state: the `PHPSESSID` credentials per student, the signed-in
/// `Student`, and the stable per-install device id used for `LoginForm[deviceId]`.
class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    private let service = "dk.elliottf.betterw4"

    /// The device id lives under its own service so `wipeAll()` — which deletes everything
    /// under `service` on logout — cannot take it with it. Regenerating the device id would
    /// make W4 treat every launch as a new device and prompt for 2FA each time.
    private let deviceService = "dk.elliottf.betterw4.device"
    private let deviceIdKey = "w4.deviceId"

    private let studentKey = "w4.student.current"

    // MARK: - Save Credentials

    /// Saves W4 credentials securely in the Keychain
    func saveCredentials(_ credentials: W4Credentials, for studentId: String) throws {
        let key = credentialsKey(for: studentId)
        let data = try JSONEncoder().encode(credentials)

        if loadCredentials(for: studentId) != nil {
            try updateCredentials(credentials, for: studentId)
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let status = SecItemAdd(query as CFDictionary, nil)

            guard status == errSecSuccess else {
                throw W4Error.keychainError("Could not save credentials: \(status)")
            }
        }
    }

    // MARK: - Load Credentials

    /// Loads W4 credentials from the Keychain
    func loadCredentials(for studentId: String) -> W4Credentials? {
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

        return try? JSONDecoder().decode(W4Credentials.self, from: data)
    }

    // MARK: - Update Credentials

    /// Updates existing W4 credentials in the Keychain
    func updateCredentials(_ credentials: W4Credentials, for studentId: String) throws {
        let key = credentialsKey(for: studentId)
        let data = try JSONEncoder().encode(credentials)

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
            throw W4Error.keychainError("Could not update credentials: \(status)")
        }
    }

    // MARK: - Delete Credentials

    /// Deletes W4 credentials from the Keychain
    func deleteCredentials(for studentId: String) throws {
        let key = credentialsKey(for: studentId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw W4Error.keychainError("Could not delete credentials: \(status)")
        }
    }

    // MARK: - Save Student

    /// Saves student info to Keychain for persistence
    func saveStudent(_ student: Student) throws {
        let data = try JSONEncoder().encode(student)

        if loadStudent() != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: studentKey
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

            guard status == errSecSuccess else {
                throw W4Error.keychainError("Could not update student: \(status)")
            }
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: studentKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let status = SecItemAdd(query as CFDictionary, nil)

            guard status == errSecSuccess else {
                throw W4Error.keychainError("Could not save student: \(status)")
            }
        }
    }

    // MARK: - Load Student

    /// Loads current student from Keychain
    func loadStudent() -> Student? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: studentKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(Student.self, from: data)
    }

    // MARK: - Delete Student

    /// Deletes current student from Keychain
    func deleteStudent() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: studentKey
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw W4Error.keychainError("Could not delete student: \(status)")
        }
    }

    // MARK: - Device id (LoginForm[deviceId])

    /// The stable per-install id W4 binds 2FA to. See `W4DeviceID` for the policy —
    /// created once, never regenerated, and deliberately not cleared by `wipeAll()`.
    func loadDeviceId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: deviceService,
            kSecAttrAccount as String: deviceIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Persists the device id. `ThisDeviceOnly` on purpose: the value identifies *this*
    /// install to W4, so it must not ride an iCloud Keychain restore onto another device.
    func saveDeviceId(_ deviceId: String) throws {
        guard let data = deviceId.data(using: .utf8) else {
            throw W4Error.keychainError("Could not encode device id")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: deviceService,
            kSecAttrAccount as String: deviceIdKey
        ]

        if loadDeviceId() != nil {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw W4Error.keychainError("Could not update device id: \(status)")
            }
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw W4Error.keychainError("Could not save device id: \(status)")
        }
    }

    // MARK: - Wipe

    /// Removes every Keychain item this app stores for the signed-in user (all per-student
    /// credentials + the current-student record) in a single call. Called on logout.
    ///
    /// The device id is stored under a separate service and survives on purpose — wiping it
    /// would make W4 demand a fresh 2FA code on the next login from this same install.
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
        "w4.credentials.\(studentId)"
    }
}
