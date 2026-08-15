//
//  BetterLectioApp.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 02/02/2026.
//

import SwiftUI
import UserNotifications

@main
struct BetterLectioApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Analytics.configure()
        Task.detached(priority: .utility) {
            OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        }

        #if os(iOS)
        // Register the BGAppRefreshTask handler. Must happen before the first scene is
        // connected, otherwise iOS will refuse to dispatch the task.
        LiveActivityBackgroundRefresh.register { task in
            Task { @MainActor in
                LiveActivityManager.shared.handleBackgroundRefresh(task: task)
            }
        }
        #endif

        Task { @MainActor in
            LiveActivityManager.shared.startObservingContentUpdates()
            CookieManager.shared.logKeychainLectioCookies(
                forStudentId: KeychainManager.shared.loadStudent()?.studentId
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await requestNotificationsIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            let label: String
            switch phase {
            case .active: label = "active"
            case .inactive: label = "inactive"
            case .background: label = "background"
            @unknown default: label = "unknown"
            }
            FeedbackLogBuffer.shared.record("App scene=\(label)")
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
