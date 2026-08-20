//
//  BetterW4App.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 02/02/2026.
//

import SwiftUI

@main
struct BetterW4App: App {
    init() {
        Task.detached(priority: .utility) {
            OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//  Notification permission is deliberately *not* requested here.
//
//  It used to be: the root view ran `requestAuthorization` from `.task` on first launch, so the
//  very first thing a new student saw was a system prompt — asked before they had opened a single
//  screen, and with nothing behind it, because no notification was ever sent. A student who
//  declined could not be asked again.
//
//  It is now asked lazily by `SettingsView`, the first time the "Allow notifications" toggle is
//  turned on, which is the only moment the app has something concrete to schedule.
//  `NotificationScheduler` does the scheduling from timetable and assessment data the app has
//  already loaded.
