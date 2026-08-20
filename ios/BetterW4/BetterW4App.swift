//
//  BetterW4App.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 02/02/2026.
//
//  Notification permission is deliberately *not* requested here.
//
//  It used to be: this file ran `requestAuthorization` from the root view's `.task` on first
//  launch, so the very first thing a new student saw was a system prompt — asked before they had
//  opened a single screen, and with nothing behind it, because no notification was ever sent. A
//  student who declined could not be asked again.
//
//  It is now asked from `ContentView`'s authenticated shell, once there is a session and something
//  concrete to schedule, and again from `SettingsView` when the student turns notifications on.
//
//  Two systems sit behind those toggles, and they answer different questions:
//    * `NotificationRefresh` + `NotificationDiff` — "something changed on the server". Runs from a
//      `BGAppRefreshTask` registered below, fetches, diffs against the last snapshot and posts.
//    * `NotificationScheduler` — "your lesson starts in ten minutes". Pre-schedules
//      `UNCalendarNotificationTrigger` reminders from data already cached, and needs no background
//      execution at all.
//

import SwiftUI
#if os(iOS)
import BackgroundTasks
#endif

@main
struct BetterW4App: App {
    init() {
        Task.detached(priority: .utility) {
            OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        }
        // Must happen in `init`, before the app finishes launching: BGTaskScheduler refuses
        // registrations made after that point.
        #if os(iOS)
        NotificationBackgroundRefresh.register { task in
            NotificationRefresh.handle(task)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
