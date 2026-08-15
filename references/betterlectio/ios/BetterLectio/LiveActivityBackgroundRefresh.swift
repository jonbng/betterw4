//
//  LiveActivityBackgroundRefresh.swift
//  BetterLectio
//

import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// Thin wrapper around BGTaskScheduler for the Live Activity refresh task.
/// iOS decides when to actually run the task — `earliestBeginDate` is only a hint — so
/// this is a best-effort backup for when the app is suspended. Precise in-process updates
/// are handled by LiveActivityBoundaryScheduler.
enum LiveActivityBackgroundRefresh {
    static let identifier = "dk.echolabs.betterlectio.app.refresh-live-activity"

    #if os(iOS)
    /// Registers the handler for the refresh task identifier. Must be called during app
    /// launch (before the first scene is connected).
    static func register(_ handler: @escaping @Sendable (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(refresh)
        }
    }

    static func schedule(earliestAt date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("BGAppRefreshTask submit failed: \(error)")
            #endif
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
    #endif
}
