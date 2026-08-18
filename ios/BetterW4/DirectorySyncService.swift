//
//  DirectorySyncService.swift
//  BetterW4
//
//  The full-directory sweep, as an `ObservableObject` the existing screens can still observe
//  (plan Wave 5 item 5.5).
//
//  All the work moved to `DirectoryRepository`; what is left here is the UI-facing shell:
//  a re-entrancy guard, `isSyncing`, and `lastSyncDate`. The Lectio machinery it replaced —
//  fetch the advanced schedule page, scrape a dropdown URL out of it, download a dropdown JSON,
//  then walk "holds" to discover their members — described a school information system this app
//  no longer talks to.
//
//  Wave 6 deletes this type and points `DirectoryViewModel` straight at the repository.
//
//  PII: never log a name or a UWC id.
//

import Combine
import Foundation

@MainActor
final class DirectorySyncService: ObservableObject {

    static let shared = DirectorySyncService()

    @Published private(set) var isSyncing = false
    @Published var lastSyncDate: Date?

    private let repository = DirectoryRepository.shared
    /// Serialises callers as well as requests: `DirectoryViewModel` calls this from both
    /// `loadDirectory` and `refreshDirectory`, and two overlapping sweeps would double the load
    /// on the school's server for no new data.
    private var inFlight: Task<Void, Never>?

    private init() {}

    /// Sweeps every directory source, serially and opportunistically, and replaces the people
    /// table with the result.
    ///
    /// - Parameter student: kept for source compatibility with the Wave-4 call sites. The session
    ///   actually used is the one in the Keychain, resolved by `W4RequestContext` inside the
    ///   repository — a sweep for anybody but the signed-in student is not a thing W4 can do.
    func syncDirectory(for student: Student) async {
        if let inFlight {
            await inFlight.value
            return
        }

        isSyncing = true
        let task = Task { @MainActor [repository] in
            do {
                let loaded = try await repository.syncFullDirectory()
                self.lastSyncDate = TimeProvider.now
                print("✅ [DirectorySync] \(loaded.value.count) people")
            } catch {
                if error is CancellationError { return }
                (error as? W4Error)?.notifyIfSessionExpired()
                print("❌ [DirectorySync] Failed: \(error.localizedDescription)")
            }
        }
        inFlight = task
        await task.value
        inFlight = nil
        isSyncing = false
    }

    /// W4 publishes no page listing the members of a class or activity, so there is nothing to
    /// load (`features.md` §1.12 — `ParsedHoldMember` and the membership table are deleted).
    /// Kept as a no-op until Wave 6 removes the call site.
    func ensureHoldMembersLoaded(for hold: DirectoryEntity, authenticatedStudent: Student) async {}
}
