//
//  BetterW4App.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 02/02/2026.
//

import SwiftUI
import UserNotifications

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
                .task {
                    await requestNotificationsIfNeeded()
                }
        }
    }

    private func requestNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                SettingsStore.shared.saveNotificationsEnabled(granted)
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }
}
