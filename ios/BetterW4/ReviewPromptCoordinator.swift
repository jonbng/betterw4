import Combine
import Foundation

/// Orchestrates the soft rating pre-filter + App Store review after happy moments.
///
/// Self-contained: the only way anything else can hold the prompt back is
/// `setExternalPromptBlocking(_:blocking:)`, which the authenticated shell calls
/// whenever it puts its own sheet on screen.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    @Published private(set) var softPromptVisible = false

    private let store: ReviewPromptStore
    private var launchRecordedThisProcess = false
    private var sessionStartedAt: Date?
    private var lastErrorAt: Date?
    private var pendingTask: Task<Void, Never>?
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
            guard self.blockers.isEmpty else { return }
            guard ReviewEligibility.isEligible(
                store: self.store,
                sessionStartedAt: self.sessionStartedAt,
                lastErrorAt: self.lastErrorAt
            ) else { return }
            self.responseHandled = false
            self.store.markSoftPromptShown()
            self.softPromptVisible = true
        }
    }

    func onPositive() {
        guard !responseHandled else {
            dismissSoftPromptUi()
            return
        }
        responseHandled = true
        dismissSoftPromptUi()
        store.markStoreFlowRequested()
        Task {
            // Let the soft sheet finish dismissing before asking the system for a review.
            try? await Task.sleep(nanoseconds: 400_000_000)
            AppStoreReviewLauncher.request()
        }
    }

    func onNegative() {
        guard !responseHandled else {
            dismissSoftPromptUi()
            return
        }
        responseHandled = true
        dismissSoftPromptUi()
    }

    func onDismissed() {
        guard !responseHandled else {
            dismissSoftPromptUi()
            return
        }
        responseHandled = true
        dismissSoftPromptUi()
    }

    private func dismissSoftPromptUi() {
        softPromptVisible = false
    }
}
