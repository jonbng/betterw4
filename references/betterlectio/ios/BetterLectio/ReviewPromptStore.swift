import Foundation

/// Persists launch timestamps and rating-prompt anti-spam flags.
/// Mirrors Android `ReviewPromptStore`.
final class ReviewPromptStore: @unchecked Sendable {
    static let shared = ReviewPromptStore()

    static let launchWindowDays: Int = 14

    private let defaults: UserDefaults
    private let prefix = "bl_review_prompt."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records one authenticated launch (caller ensures at most once per process).
    /// Prunes launches older than ``launchWindowDays``.
    func recordLaunch(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.launchWindowSeconds)
        var pruned = launchTimestamps().filter { $0 >= cutoff }
        pruned.append(now)
        defaults.set(pruned.map(\.timeIntervalSince1970), forKey: key(Self.keyLaunchTimestamps))
    }

    func launchCountInWindow(now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-Self.launchWindowSeconds)
        return launchTimestamps().filter { $0 >= cutoff }.count
    }

    func promptCount() -> Int {
        defaults.integer(forKey: key(Self.keyPromptCount))
    }

    func lastPromptAt() -> Date? {
        let ms = defaults.double(forKey: key(Self.keyLastPromptAt))
        guard ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms)
    }

    func completedStoreFlow() -> Bool {
        defaults.bool(forKey: key(Self.keyCompletedStore))
    }

    func neverAsk() -> Bool {
        defaults.bool(forKey: key(Self.keyNeverAsk))
    }

    func markSoftPromptShown(now: Date = Date()) {
        defaults.set(promptCount() + 1, forKey: key(Self.keyPromptCount))
        defaults.set(now.timeIntervalSince1970, forKey: key(Self.keyLastPromptAt))
    }

    func markStoreFlowRequested() {
        defaults.set(true, forKey: key(Self.keyCompletedStore))
        defaults.set(true, forKey: key(Self.keyNeverAsk))
    }

    func markNeverAsk() {
        defaults.set(true, forKey: key(Self.keyNeverAsk))
    }

    private func launchTimestamps() -> [Date] {
        guard let raw = defaults.array(forKey: key(Self.keyLaunchTimestamps)) as? [Double] else {
            return []
        }
        return raw.map { Date(timeIntervalSince1970: $0) }
    }

    private func key(_ name: String) -> String { prefix + name }

    private static let launchWindowSeconds: TimeInterval =
        TimeInterval(launchWindowDays) * 24 * 60 * 60

    private static let keyLaunchTimestamps = "launch_timestamps"
    private static let keyPromptCount = "prompt_count"
    private static let keyLastPromptAt = "last_prompt_at"
    private static let keyCompletedStore = "completed_store_flow"
    private static let keyNeverAsk = "never_ask"
}
