import Combine
import Foundation

/// Orchestrates soft rating pre-filter + App Store review after happy moments.
/// Mirrors Android `ReviewPromptCoordinator`.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    @Published private(set) var softPromptVisible = false

    private let store: ReviewPromptStore
    private var launchRecordedThisProcess = false
    private var sessionStartedAt: Date?
    private var lastErrorAt: Date?
    private var pendingTask: Task<Void, Never>?
    private var shownTrigger: ReviewTrigger?
    private var responseHandled = false
    private var scheduleLoadedAttempted = false
    private var currentStudent: Student?
    private var blockers = Set<String>()

    private static let promptDelayNanoseconds: UInt64 = 1_800_000_000

    init(store: ReviewPromptStore = .shared) {
        self.store = store
    }

    /// Call once per authenticated process from the authenticated shell.
    /// Records a launch for the 8-opens / 14-days gate.
    func onAuthenticatedLaunch(student: Student) {
        currentStudent = student
        guard !student.isDemo else { return }
        guard !launchRecordedThisProcess else { return }
        launchRecordedThisProcess = true
        sessionStartedAt = Date()
        scheduleLoadedAttempted = false
        store.recordLaunch()
    }

    func reportRecentError() {
        lastErrorAt = Date()
    }

    func setExternalPromptBlocking(_ source: String, blocking: Bool) {
        if blocking {
            blockers.insert(source)
        } else {
            blockers.remove(source)
        }
    }

    /// Schedule-loaded is only attempted once per process (same as Android ViewModel gate).
    func maybePromptScheduleLoaded() {
        guard !scheduleLoadedAttempted else { return }
        scheduleLoadedAttempted = true
        maybePrompt(.scheduleLoaded)
    }

    /// After a happy moment — delays briefly, re-checks gates, then may show the soft sheet.
    func maybePrompt(_ trigger: ReviewTrigger) {
        guard let student = currentStudent, !student.isDemo else { return }
        guard !softPromptVisible else { return }

        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.promptDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            guard !self.softPromptVisible else { return }
            if self.hasConflictingPrompt() {
                FeedbackLogBuffer.shared.record(
                    "Review prompt skipped: conflicting UI (\(trigger.analyticsName))"
                )
                return
            }
            guard ReviewEligibility.isEligible(
                store: self.store,
                sessionStartedAt: self.sessionStartedAt,
                lastErrorAt: self.lastErrorAt
            ) else {
                FeedbackLogBuffer.shared.record(
                    "Review prompt ineligible (\(trigger.analyticsName))"
                )
                return
            }
            self.shownTrigger = trigger
            self.responseHandled = false
            self.store.markSoftPromptShown()
            self.softPromptVisible = true
            Analytics.capture(
                "review_prompt_shown",
                properties: ["trigger": trigger.analyticsName]
            )
        }
    }

    func onPositive() {
        guard !responseHandled else {
            dismissSoftPromptUi()
            return
        }
        responseHandled = true
        let trigger = shownTrigger?.analyticsName ?? ""
        Analytics.capture("review_prompt_positive", properties: ["trigger": trigger])
        dismissSoftPromptUi()
        store.markStoreFlowRequested()
        Task {
            // Let the soft sheet finish dismissing before asking the system for a review.
            try? await Task.sleep(nanoseconds: 400_000_000)
            let launched = AppStoreReviewLauncher.request()
            Analytics.capture(
                "review_play_flow_requested",
                properties: [
                    "trigger": trigger,
                    "play_accepted": launched,
                ]
            )
        }
    }

    func onNegative() {
        guard !responseHandled else {
            dismissSoftPromptUi()
            return
        }
        responseHandled = true
        let trigger = shownTrigger?.analyticsName ?? ""
        Analytics.capture("review_prompt_negative", properties: ["trigger": trigger])
        dismissSoftPromptUi()
        if let student = currentStudent {
            FeedbackCoordinator.shared.present(for: student)
        }
    }

    func onDismissed() {
        guard !responseHandled else {
            dismissSoftPromptUi()
            return
        }
        responseHandled = true
        let trigger = shownTrigger?.analyticsName ?? ""
        Analytics.capture("review_prompt_dismissed", properties: ["trigger": trigger])
        dismissSoftPromptUi()
    }

    private func dismissSoftPromptUi() {
        softPromptVisible = false
        shownTrigger = nil
    }

    private func hasConflictingPrompt() -> Bool {
        if !blockers.isEmpty { return true }
        if ReferralCoordinator.shared.nudgeVisible { return true }
        if FeedbackCoordinator.shared.presentation != nil { return true }
        return false
    }
}
