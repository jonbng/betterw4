//
//  ExtensionState.swift
//  BetterLectioMac
//
//  Observes whether the embedded Safari Web Extension is enabled in Safari.
//
//  `SFSafariExtensionManager` is the only way to read this — there is no
//  notification when the user toggles the extension, so we refresh on app
//  activation (covers the common "user returns from Safari settings" case) plus
//  a light poll while onboarding is on screen. Neither this API nor
//  `SFSafariApplication.showPreferencesForExtension` requires an entitlement,
//  so both work inside the App Sandbox.
//

import SwiftUI
import SafariServices
// Explicit: the project enables SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY,
// so ObservableObject/@Published are not visible via SwiftUI's re-export.
import Combine

@MainActor
final class ExtensionState: ObservableObject {

    enum Status: Equatable {
        case unknown
        case enabled
        case disabled
        case failed(String)

        var isEnabled: Bool { self == .enabled }
    }

    @Published private(set) var status: Status = .unknown

    var isEnabled: Bool { status.isEnabled }

    private var pollTask: Task<Void, Never>?

    // MARK: - Reading state

    func refresh() async {
        do {
            let state = try await SFSafariExtensionManager
                .stateOfSafariExtension(withIdentifier: BL.extensionBundleID)
            status = state.isEnabled ? .enabled : .disabled
        } catch {
            // Most commonly: Safari has never seen the extension because the app
            // was launched from DerivedData rather than /Applications, or the
            // appex failed to embed.
            status = .failed(error.localizedDescription)
        }
    }

    /// Poll while a view that cares about live updates is on screen. Safari does
    /// not notify us, and `didBecomeActive` alone misses the case where both
    /// windows are visible side by side.
    func startPolling(every interval: Duration = .seconds(2)) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Actions

    /// Opens Safari's Extensions settings, scrolled to this extension.
    func openSafariSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: BL.extensionBundleID) { error in
            if let error {
                NSLog("Kunne ikke åbne Safari-indstillinger: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Bundled extension metadata

/// Reads `EXTENSION_BUILD_INFO.json` if it was bundled into the app, so the About
/// and Status screens can report which web-extension build shipped. Written by
/// `scripts/sync-safari-extension.sh`; absent in local builds that never ran it.
struct ExtensionBuildInfo: Decodable {
    let extensionVersion: String
    let sourceCommit: String?

    enum CodingKeys: String, CodingKey {
        case extensionVersion = "extension_version"
        case sourceCommit = "source_commit"
    }

    static let bundled: ExtensionBuildInfo? = {
        guard let url = Bundle.main.url(forResource: "EXTENSION_BUILD_INFO", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ExtensionBuildInfo.self, from: data)
    }()

    var shortCommit: String? {
        guard let sourceCommit, sourceCommit.count >= 8 else { return nil }
        return String(sourceCommit.prefix(8))
    }
}

// MARK: - App version helpers

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
