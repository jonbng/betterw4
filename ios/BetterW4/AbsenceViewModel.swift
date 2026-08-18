//
//  AbsenceViewModel.swift
//  BetterW4
//
//  The Attendance screen's view model. Declares `AttendanceViewModel` (the file keeps its old name
//  so the Xcode synchronised group and `AbsenceView.swift` stay next to each other; the *type* is
//  named for what W4 calls this, which is attendance, not "fravær").
//
//  It talks to `AttendanceRepository` and to nothing else — no HTTP client, no parser, no Keychain
//  (`features.md` §0 rule 2). The repository already does the cache-first read, the demo branch and
//  the degrade-to-cache-on-failure dance; what is left here is the six behaviours from
//  `features.md` §3 that make the screen feel solid:
//
//    1. a generation `UUID` taken at entry and re-checked before *every* published mutation;
//    2. cached snapshot published first, then a forced refresh — never gate the fetch on staleness;
//    3. the blocking spinner only when there is nothing cached to show;
//    4. an error message only when there is nothing to show — offline with a warm cache is a
//       working app;
//    5. in-memory state cleared when the signed-in student changes (demo ⇄ real, mostly);
//    6. `W4Error.sessionExpired` — and only `.sessionExpired` — logs out. `.forbidden` is a role
//       problem, never a dead session, and the repository hands it back as a *failure next to the
//       data* rather than throwing, so it can never reach `notifyIfSessionExpired()` at all.
//
//  Cancellation is swallowed, never shown.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AttendanceViewModel: ObservableObject {

    // MARK: - Published state

    /// Meters + both ledgers. `nil` until the first read of any kind lands.
    @Published private(set) var snapshot: AttendanceSnapshot?
    /// Where `snapshot` came from, so the screen can say "Updated 4 h ago" honestly.
    @Published private(set) var freshness: W4Freshness?
    /// Which ledger's registrations the list below the meters is showing.
    @Published var selectedSource: AttendanceSource = .academics {
        didSet { rebuildSections() }
    }

    /// Blocking spinner. True only while loading with nothing to draw yet (§3.3).
    @Published private(set) var isLoading = false
    /// Subtle "refreshing" indicator over content that is already on screen.
    @Published private(set) var isRefreshing = false

    /// Shown only when there is nothing else to show (§3.4).
    @Published private(set) var errorMessage: String?
    /// Shown *next to* content that did render — "showing a saved copy", a 403, a pager hint.
    @Published private(set) var noticeMessage: String?

    // MARK: - Derived, computed once per snapshot

    @Published private(set) var meters: [AttendanceMeterDisplay] = AttendanceMeterDisplay.all(from: .empty)
    @Published private(set) var sections: [AttendanceDaySection] = []
    @Published private(set) var breakdown: [SubjectAttendance] = []

    // MARK: - Dependencies

    private let repository: AttendanceRepository
    private let now: @Sendable () -> Date

    private var loadGeneration: UUID?
    private var activeStudentID: String?

    init(
        repository: AttendanceRepository = .shared,
        now: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        self.repository = repository
        self.now = now
    }

    // MARK: - Loading

    /// Cache-first render, then a refresh. Safe to call from `.task` and from `.refreshable` — the
    /// generation guard makes the later call win.
    ///
    /// `forceRefresh` is what separates "the student opened the screen" from "the student pulled
    /// down". On open it stays `false`, which is what buys the free meters: when a Home page is
    /// already in the cache and inside its TTL, `AttendanceRepository` reads both meters out of it
    /// and issues **no request at all**. On a pull it is `true`, and every surface is refetched.
    func load(for student: Student, forceRefresh: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation

        // §3.5 — a different student means the previous student's data must not linger.
        if activeStudentID != student.studentId {
            activeStudentID = student.studentId
            applySnapshot(nil, freshness: nil)
            errorMessage = nil
            noticeMessage = nil
        }

        // §3.2 — paint whatever is on disk before asking the network for anything.
        if snapshot == nil, let cached = await repository.cachedSnapshot() {
            guard loadGeneration == generation else { return }
            applySnapshot(cached.value, freshness: cached.freshness)
        }

        // §3.3 — a spinner over content the student can already read is noise.
        let hadContent = hasContent
        if hadContent {
            isRefreshing = true
        } else {
            isLoading = true
        }

        defer {
            if loadGeneration == generation {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let loaded = try await repository.loadSnapshot(forceRefresh: forceRefresh)
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }

            applySnapshot(loaded.value, freshness: loaded.freshness)
            errorMessage = firstFailure(in: loaded.value).flatMap { failure in
                // §3.4 — only when the screen would otherwise be blank.
                hasContent ? nil : failure.message
            }
            noticeMessage = notice(for: loaded)
        } catch let error as W4Error {
            // Only `.sessionExpired` posts the logout notification; `.forbidden` never reaches here.
            error.notifyIfSessionExpired()
            guard loadGeneration == generation else { return }
            if !hasContent { errorMessage = error.errorDescription }
        } catch {
            guard loadGeneration == generation else { return }
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            if !hasContent { errorMessage = error.localizedDescription }
        }
    }

    /// Pull-to-refresh: the same path, with every cache TTL bypassed.
    func refresh(for student: Student) async {
        await load(for: student, forceRefresh: true)
    }

    // MARK: - Reading the snapshot

    /// True when there is something on screen worth keeping: any meter, or any registration.
    var hasContent: Bool {
        guard let snapshot else { return false }
        return !snapshot.isEmpty
    }

    var hasRecords: Bool { !(snapshot?.records.isEmpty ?? true) }

    /// The list snapshot for whichever ledger is selected.
    var selectedList: AttendanceListSnapshot? {
        switch selectedSource {
        case .academics: return snapshot?.academic
        case .extraAcademics: return snapshot?.extraAcademic
        }
    }

    /// W4's own empty-state sentence for the selected ledger, when it rendered one.
    var emptyMessage: String? {
        guard let list = selectedList, list.isEmpty else { return nil }
        return list.list.emptyMessage ?? "No absence records."
    }

    /// True when W4 paged the grid — page one is not the whole story (bug B10).
    var hasMorePages: Bool { selectedList?.list.hasMorePages ?? false }

    /// `people/students/absences/register`, opened in the browser.
    ///
    /// Read-only on purpose: the per-slot checkbox names are injected by W4's own JavaScript and
    /// have never been captured, so any payload this app could build would be a guess (OQ-10).
    var registerAbsencesURL: URL { W4Routes.url(W4Routes.R.absencesRegister) }

    /// "Updated 4 h ago" / "Demo data" / `nil` when it came straight off the wire.
    var freshnessLabel: String? {
        guard let freshness else { return nil }
        switch freshness {
        case .fresh:
            return nil
        case .demo:
            return "Demo data"
        case .cached(let fetchedAt, _):
            // `.distantPast` is `AttendanceRepository.nothingCached` — "we had nothing", not a date.
            if fetchedAt == .distantPast { return nil }
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.unitsStyle = .full
            return "Updated \(formatter.localizedString(for: fetchedAt, relativeTo: now()))"
        }
    }

    var isShowingCachedCopy: Bool {
        if case .cached(_, let isStale) = freshness { return isStale }
        return false
    }

    // MARK: - Internals

    private func applySnapshot(_ snapshot: AttendanceSnapshot?, freshness: W4Freshness?) {
        self.snapshot = snapshot
        self.freshness = freshness
        meters = AttendanceMeterDisplay.all(from: snapshot?.meters.meters ?? .empty)
        rebuildSections()
    }

    private func rebuildSections() {
        let records = selectedList?.records ?? []
        sections = AttendanceDaySection.sections(from: records, now: now())
        breakdown = SubjectAttendance.breakdown(of: records)
    }

    /// The failure worth naming: the selected ledger's, then the meters', then anything else.
    private func firstFailure(in snapshot: AttendanceSnapshot) -> AttendanceFetchFailure? {
        let selected: AttendanceListSnapshot = selectedSource == .academics
            ? snapshot.academic
            : snapshot.extraAcademic
        return selected.failure ?? snapshot.meters.failure ?? snapshot.failures.first
    }

    /// The banner shown *beside* data that did render.
    private func notice(for loaded: W4Loaded<AttendanceSnapshot>) -> String? {
        guard hasContent else { return nil }

        if let failure = firstFailure(in: loaded.value) {
            switch failure.kind {
            case .offline:
                return "Offline — showing the last saved copy."
            case .forbidden:
                return "W4 would not show this page for your account."
            case .server, .transport:
                return "Could not refresh from W4 — showing the last saved copy."
            }
        }

        if case .cached(_, let isStale) = loaded.freshness, isStale {
            return "Showing a saved copy."
        }
        return nil
    }
}
