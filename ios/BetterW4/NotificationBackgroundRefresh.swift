//
//  NotificationBackgroundRefresh.swift
//  BetterW4
//
//  BGAppRefresh wrapper. iOS decides the real cadence; earliestBeginDate is a hint.
//

import Foundation
#if os(iOS)
import BackgroundTasks
#endif

enum NotificationBackgroundRefresh {
    static let identifier = "dk.jonathanb.w4.refresh"

    #if os(iOS)
    static func register(_ handler: @escaping @Sendable (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handler(refresh)
        }
    }

    static func schedule(earliestAt date: Date = Date().addingTimeInterval(15 * 60)) {
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
