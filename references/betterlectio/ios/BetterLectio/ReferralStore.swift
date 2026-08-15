import Foundation

final class ReferralStore: @unchecked Sendable {
    static let shared = ReferralStore()
    // App Clip shared groups must be prefixed by the parent app bundle identifier.
    static let appGroup = "group.dk.echolabs.betterlectio.app.referral"
    static let pendingLifetime: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let pendingKey = "referral.pending.v1"

    init(defaults: UserDefaults = UserDefaults(suiteName: ReferralStore.appGroup) ?? .standard) {
        self.defaults = defaults
    }

    @discardableResult
    func saveFirstPending(token: UUID, now: Date = Date()) -> Bool {
        if pending(now: now) != nil { return false }
        let value = PendingReferral(token: token, capturedAt: now)
        guard let data = try? encoder.encode(value) else { return false }
        defaults.set(data, forKey: pendingKey)
        return true
    }

    func pending(now: Date = Date()) -> PendingReferral? {
        guard let data = defaults.data(forKey: pendingKey),
              let value = try? decoder.decode(PendingReferral.self, from: data) else { return nil }
        guard now.timeIntervalSince(value.capturedAt) <= Self.pendingLifetime else {
            clearPending()
            return nil
        }
        return value
    }

    func clearPending() {
        defaults.removeObject(forKey: pendingKey)
    }

    func wasFinalizeAttempted(studentID: String) -> Bool {
        defaults.bool(forKey: "referral.finalized.\(studentID)")
    }

    func markFinalizeAttempted(studentID: String) {
        defaults.set(true, forKey: "referral.finalized.\(studentID)")
    }

    func wasNudgeShown(studentID: String) -> Bool {
        defaults.bool(forKey: "referral.nudge.\(studentID)")
    }

    func markNudgeShown(studentID: String) {
        defaults.set(true, forKey: "referral.nudge.\(studentID)")
    }

    func lastKnownConversions(studentID: String) -> Int? {
        let key = "referral.conversions.\(studentID)"
        return defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key)
    }

    func setLastKnownConversions(_ value: Int, studentID: String) {
        defaults.set(value, forKey: "referral.conversions.\(studentID)")
    }
}
