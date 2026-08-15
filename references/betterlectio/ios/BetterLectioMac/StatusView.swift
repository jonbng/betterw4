//
//  StatusView.swift
//  BetterLectioMac
//
//  Answers the app's primary question: is BetterLectio actually running in Safari?
//

import SwiftUI

struct StatusView: View {
    @EnvironmentObject private var extensionState: ExtensionState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ScrollView {
            VStack(spacing: BL.Space.l) {
                heroCard
                detailsCard
            }
            .frame(maxWidth: 560)
            .padding(BL.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .onAppear { extensionState.startPolling(every: .seconds(4)) }
        .onDisappear { extensionState.stopPolling() }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: BL.Space.m) {
            Image(systemName: heroIcon)
                .font(.system(size: 52))
                .foregroundStyle(heroTint)
                .symbolRenderingMode(.hierarchical)

            Text(heroTitle)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(heroMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !extensionState.isEnabled {
                Button {
                    extensionState.openSafariSettings()
                } label: {
                    Label("Åbn Safari-indstillinger", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, BL.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(BL.Space.xl)
        .blCard(radius: BL.Radius.prominent)
    }

    private var heroIcon: String {
        switch extensionState.status {
        case .enabled: "checkmark.seal.fill"
        case .disabled: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .unknown: "hourglass"
        }
    }

    private var heroTint: Color {
        switch extensionState.status {
        case .enabled: .green
        case .disabled: .orange
        case .failed: .red
        case .unknown: .secondary
        }
    }

    private var heroTitle: String {
        switch extensionState.status {
        case .enabled: "BetterLectio er aktiv"
        case .disabled: "BetterLectio er slået fra"
        case .failed: "Kunne ikke læse status"
        case .unknown: "Tjekker status…"
        }
    }

    private var heroMessage: String {
        switch extensionState.status {
        case .enabled:
            "Udvidelsen kører i Safari. Åbn lectio.dk, så er du i gang."
        case .disabled:
            "Slå BetterLectio til under Safari → Indstillinger → Udvidelser."
        case .failed(let message):
            "Safari kunne ikke fortælle os, om udvidelsen er slået til.\n\(message)"
        case .unknown:
            "Henter status fra Safari…"
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        VStack(spacing: 0) {
            DetailRow(
                icon: "app.badge.checkmark",
                title: "App-version",
                value: "\(AppVersion.marketing) (\(AppVersion.build))"
            )

            if let info = ExtensionBuildInfo.bundled {
                Divider().padding(.leading, 60)
                DetailRow(
                    icon: "puzzlepiece.extension",
                    title: "Udvidelsesversion",
                    value: info.shortCommit.map { "\(info.extensionVersion) · \($0)" }
                        ?? info.extensionVersion
                )
            }

            Divider().padding(.leading, 60)

            Button {
                hasCompletedOnboarding = false
            } label: {
                DetailRow(
                    icon: "arrow.counterclockwise",
                    title: "Kør opsætningen igen",
                    value: nil,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 60)

            Button {
                NSWorkspace.shared.open(BL.lectioURL)
            } label: {
                DetailRow(
                    icon: "safari",
                    title: "Åbn lectio.dk",
                    value: nil,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
        .blCard()
    }
}

// MARK: - Row

struct DetailRow: View {
    let icon: String
    let title: String
    var value: String?
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: BL.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            Text(title)
                .font(.callout)

            Spacer(minLength: BL.Space.m)

            if let value {
                Text(value)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, BL.Space.m)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
