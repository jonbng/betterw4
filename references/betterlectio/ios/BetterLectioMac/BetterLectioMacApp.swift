//
//  BetterLectioMacApp.swift
//  BetterLectioMac
//
//  Host app for the BetterLectio Safari Web Extension on macOS.
//
//  Shares the bundle identifier `dk.echolabs.betterlectio.app` with the iOS app so
//  the two ship as one App Store record under Universal Purchase — anyone who owns
//  one sees the other as already purchased on their other device.
//

import SwiftUI

@main
struct BetterLectioMacApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var extensionState = ExtensionState()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingView(onFinish: { hasCompletedOnboarding = true })
                }
            }
            .environmentObject(extensionState)
            .frame(minWidth: 720, minHeight: 520)
            .task { await extensionState.refresh() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )
            ) { _ in
                // The user most likely just came back from Safari's settings.
                Task { await extensionState.refresh() }
            }
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("Kør opsætningen igen") { hasCompletedOnboarding = false }
            }

            CommandGroup(replacing: .help) {
                Button("BetterLectio Hjælp") {
                    NSWorkspace.shared.open(BL.githubURL)
                }
                Button("Rapportér et problem") {
                    NSWorkspace.shared.open(BL.feedbackURL)
                }
            }
        }
    }
}
