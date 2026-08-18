//
//  W4DeviceID.swift
//  BetterW4
//
//  Stable per-install device id for `LoginForm[deviceId]`.
//  Ported from android/.../core/w4/auth/W4DeviceIdStore.kt.
//

import Foundation

/// W4 binds two-factor authentication to `LoginForm[deviceId]`. In a browser that value is a
/// ClientJS fingerprint; we deliberately do **not** reimplement fingerprinting (README §4.4).
/// A stable UUID created once and kept in the Keychain is enough: the first login on this
/// install looks like a new device (one OTP prompt), every later launch reuses the same id.
///
/// Never regenerate this value — a fresh id means W4 prompts for 2FA on every launch.
/// It deliberately survives logout, so `KeychainManager.wipeAll()` does not remove it.
enum W4DeviceID {
    private static let lock = NSLock()
    private static var cached: String?

    /// The device id for this install, creating and persisting it on first use.
    static func current() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let cached, !cached.isEmpty { return cached }

        if let stored = KeychainManager.shared.loadDeviceId(), !stored.isEmpty {
            cached = stored
            return stored
        }

        let created = UUID().uuidString
        do {
            try KeychainManager.shared.saveDeviceId(created)
        } catch {
            // Falling through with an unpersisted id still logs the user in; it only costs
            // an extra OTP prompt next launch. Never block login on a Keychain hiccup.
            print("⚠️ [W4DeviceID] Could not persist device id: \(error.localizedDescription)")
        }
        cached = created
        return created
    }
}
