import Combine
import Foundation

@MainActor
final class ReferralCoordinator: ObservableObject {
    static let shared = ReferralCoordinator()

    @Published private(set) var cachedStats: ReferralStats?
    @Published var nudgeVisible = false
    @Published var celebrationName: String?
    @Published private(set) var lastAttribution: ReferralFinalizeResult?
    private var activeStudentID: String?
    private var captureInFlight = false

    private let service: SupabaseReferralService
    private let store: ReferralStore

    init(service: SupabaseReferralService = .shared, store: ReferralStore = .shared) {
        self.service = service
        self.store = store
    }

    func cachedStats(for student: Student) -> ReferralStats? {
        activeStudentID == student.studentId ? cachedStats : nil
    }

    func activate(for student: Student) {
        guard activeStudentID != student.studentId else { return }
        resetSession()
        activeStudentID = student.studentId
    }

    func resetSession() {
        activeStudentID = nil
        cachedStats = nil
        nudgeVisible = false
        celebrationName = nil
        lastAttribution = nil
    }

    func handle(url: URL, authenticatedStudent: Student?) async {
        guard let link = ReferralLink.parse(url) else { return }
        guard !captureInFlight else { return }
        captureInFlight = true
        defer { captureInFlight = false }
        do {
            let token: UUID
            if let candidate = link.token {
                guard try await service.validate(token: candidate, referrerStudentID: link.studentID) else { return }
                token = candidate
            } else {
                token = try await service.registerClick(referrerStudentID: link.studentID)
            }
            _ = store.saveFirstPending(token: token)
            if let authenticatedStudent {
                await finalizeIfNeeded(for: authenticatedStudent)
            }
        } catch {
            print("⚠️ [Referral] Could not capture link: \(error.localizedDescription)")
        }
    }

    func finalizeIfNeeded(for student: Student) async {
        activate(for: student)
        guard !student.isDemo,
              !store.wasFinalizeAttempted(studentID: student.studentId),
              let pending = store.pending() else { return }
        do {
            let result = try await service.finalize(student: student, token: pending.token)
            lastAttribution = result
            store.markFinalizeAttempted(studentID: student.studentId)
            store.clearPending()
        } catch {
            // A transport/server failure is intentionally retryable on next launch.
            print("⚠️ [Referral] Finalization deferred: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func refreshStats(for student: Student) async -> ReferralStats? {
        activate(for: student)
        if student.isDemo {
            cachedStats = .demo
            return .demo
        }
        do {
            let stats = try await service.stats(studentID: student.studentId)
            if let previous = store.lastKnownConversions(studentID: student.studentId),
               stats.conversions > previous {
                celebrationName = stats.recentReferrals.first?.name ?? "En klassekammerat"
            }
            store.setLastKnownConversions(stats.conversions, studentID: student.studentId)
            cachedStats = stats
            return stats
        } catch {
            print("⚠️ [Referral] Stats unavailable: \(error.localizedDescription)")
            return cachedStats(for: student)
        }
    }

    func maybeShowNudge(for student: Student) async {
        guard !student.isDemo, !store.wasNudgeShown(studentID: student.studentId) else { return }
        guard let stats = await refreshStats(for: student) else { return }
        if ReferralProgress(conversions: stats.conversions).unlocked {
            store.markNudgeShown(studentID: student.studentId)
        } else {
            nudgeVisible = true
        }
    }

    func dismissNudge(for student: Student) {
        store.markNudgeShown(studentID: student.studentId)
        nudgeVisible = false
    }
}
