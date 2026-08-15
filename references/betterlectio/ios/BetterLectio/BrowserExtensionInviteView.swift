import SwiftUI
import UIKit

enum BrowserExtensionEntrySource: String, Sendable {
    case more
    case settings
}

@MainActor
enum BrowserExtensionClipboard {
    static func copyDownloadURL(to pasteboard: UIPasteboard = .general) {
        pasteboard.url = BetterLectioLinks.downloadURL
    }
}

struct BrowserExtensionInviteView: View {
    let source: BrowserExtensionEntrySource

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(String(localized: "browser_extension.title", defaultValue: "BetterLectio på din computer"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(String(localized: "browser_extension.body", defaultValue: "Browser-udvidelsen forbedrer Lectio i Chrome, Firefox og Edge. Den installeres på din computer – ikke på din iPhone."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text(BetterLectioLinks.downloadURL.absoluteString)
                    .font(.callout.monospaced())
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)

                VStack(spacing: 10) {
                    ShareLink(
                        item: BetterLectioLinks.downloadURL,
                        subject: Text(String(localized: "browser_extension.share_subject", defaultValue: "BetterLectio browser-udvidelse")),
                        message: Text(String(localized: "browser_extension.share_message", defaultValue: "Installer BetterLectio på din computer:"))
                    ) {
                        Label(String(localized: "browser_extension.share", defaultValue: "Del link"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.borderedProminent)
                    .simultaneousGesture(TapGesture().onEnded {
                        Analytics.capture("browser_extension_shared", properties: ["source": source.rawValue])
                    })

                    Button(action: copyLink) {
                        Label(
                            copied
                                ? String(localized: "browser_extension.copied", defaultValue: "Kopieret")
                                : String(localized: "browser_extension.copy", defaultValue: "Kopiér link"),
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: 480, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "browser_extension.navigation_title", defaultValue: "Browser-udvidelse"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.close", defaultValue: "Luk")) { dismiss() }
                }
            }
            .onAppear {
                Analytics.capture("browser_extension_opened", properties: ["source": source.rawValue])
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func copyLink() {
        BrowserExtensionClipboard.copyDownloadURL()
        copied = true
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "browser_extension.copy_announcement", defaultValue: "Link kopieret")
        )
        Analytics.capture("browser_extension_copied", properties: ["source": source.rawValue])
    }
}
