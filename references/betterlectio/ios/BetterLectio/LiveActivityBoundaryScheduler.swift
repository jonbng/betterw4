//
//  LiveActivityBoundaryScheduler.swift
//  BetterLectio
//

import Foundation

/// Fires in-process updates exactly at each lesson/break boundary while the app is alive,
/// so the Live Activity flips to the next lesson immediately instead of waiting for the
/// next 60-second tick. When the app is suspended, these tasks pause and BG refresh
/// (LiveActivityBackgroundRefresh) takes over.
@MainActor
final class LiveActivityBoundaryScheduler {
    static let shared = LiveActivityBoundaryScheduler()

    private var tasks: [Task<Void, Never>] = []

    private init() {}

    /// Replace the scheduled fires with a new set derived from `boundaries`.
    /// Each entry is shifted 1 second forward so the fire observes the post-boundary state.
    func reschedule(boundaries: [Date], onFire: @escaping @MainActor () -> Void) {
        cancel()

        let now = Date()
        let futureFires = boundaries
            .map { $0.addingTimeInterval(1) }
            .filter { $0 > now }
            .sorted()

        for fireDate in futureFires {
            let delay = fireDate.timeIntervalSince(now)
            let task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                onFire()
            }
            tasks.append(task)
        }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
