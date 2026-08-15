import Foundation

enum ReviewTrigger: String, Sendable {
    case homeworkDone = "homework_done"
    case scheduleLoaded = "schedule_loaded"
    case privateEventCreated = "private_event_created"
    case messageSent = "message_sent"

    var analyticsName: String { rawValue }
}

/// Pure eligibility checks for the soft rating pre-filter.
/// Mirrors Android `ReviewEligibility`.
enum ReviewEligibility {
    static let minInstallAgeDays = 14
    static let minLaunchesInWindow = 8
    static let promptHourStart = 16
    static let promptHourEnd = 21
    static let cooldownDays = 90
    static let maxLifetimePrompts = 3
    static let minSessionSeconds: TimeInterval = 30
    static let errorCooldownSeconds: TimeInterval = 60

    /// Mon–Thu only (same as Android).
    static let promptWeekdays: Set<Int> = [
        2, // Monday
        3, // Tuesday
        4, // Wednesday
        5, // Thursday
    ]

    static func isEligible(
        store: ReviewPromptStore = .shared,
        now: Date = Date(),
        calendar: Calendar = .current,
        sessionStartedAt: Date?,
        lastErrorAt: Date?
    ) -> Bool {
        if store.neverAsk() || store.completedStoreFlow() { return false }
        if store.promptCount() >= maxLifetimePrompts { return false }
        if !installedLongEnough(now: now) { return false }
        if store.launchCountInWindow(now: now) < minLaunchesInWindow { return false }
        if !inPromptWindow(now: now, calendar: calendar) { return false }
        if !cooldownElapsed(store: store, now: now) { return false }
        if !sessionCalm(now: now, sessionStartedAt: sessionStartedAt, lastErrorAt: lastErrorAt) {
            return false
        }
        return true
    }

    static func installedLongEnough(now: Date = Date()) -> Bool {
        guard let installedAt = firstInstallDate() else { return false }
        let days = Calendar.current.dateComponents([.day], from: installedAt, to: now).day ?? 0
        return days >= minInstallAgeDays
    }

    /// Approximate first-install time via the app documents directory creation date.
    static func firstInstallDate() -> Date? {
        guard
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let attrs = try? FileManager.default.attributesOfItem(atPath: docs.path),
            let created = attrs[.creationDate] as? Date
        else {
            return nil
        }
        return created
    }

    private static func inPromptWindow(now: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: now)
        guard promptWeekdays.contains(weekday) else { return false }
        let hour = calendar.component(.hour, from: now)
        return hour >= promptHourStart && hour < promptHourEnd
    }

    private static func cooldownElapsed(store: ReviewPromptStore, now: Date) -> Bool {
        guard let last = store.lastPromptAt() else { return true }
        let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
        return days >= cooldownDays
    }

    private static func sessionCalm(
        now: Date,
        sessionStartedAt: Date?,
        lastErrorAt: Date?
    ) -> Bool {
        guard let sessionStartedAt else { return false }
        if now.timeIntervalSince(sessionStartedAt) < minSessionSeconds { return false }
        if let lastErrorAt, now.timeIntervalSince(lastErrorAt) < errorCooldownSeconds {
            return false
        }
        return true
    }
}
