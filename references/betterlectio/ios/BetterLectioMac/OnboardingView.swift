//
//  OnboardingView.swift
//  BetterLectioMac
//
//  First-run flow: enable the extension in Safari, then grant it access to
//  lectio.dk. Step 2 is verifiable (SFSafariExtensionManager tells us), step 3 is
//  not — Safari exposes no API for per-site grants, so that step is instructional.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var extensionState: ExtensionState
    @State private var step = 0

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            footer
        }
        .background(BL.Palette.windowBackground)
        .animation(.snappy(duration: 0.32), value: step)
        .onAppear { extensionState.startPolling() }
        .onDisappear { extensionState.stopPolling() }
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: enableStep
        default: permissionStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: BL.Space.m) {
            Spacer()

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, BL.Space.s)

            Text("BetterLectio")
                .font(BL.wordmark())

            Text("Gør Lectio suverent bedre, nu også i Safari.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Opsætningen tager under et minut.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .padding(.top, BL.Space.xs)

            Spacer()
        }
        .padding(BL.Space.xl)
    }

    private var enableStep: some View {
        StepScaffold(
            icon: "puzzlepiece.extension.fill",
            title: "Slå BetterLectio til i Safari",
            subtitle: "Udvidelser skal aktiveres manuelt i Safari, første gang de installeres."
        ) {
            VStack(alignment: .leading, spacing: BL.Space.m) {
                InstructionRow(number: 1, text: "Klik på knappen herunder. Safari åbner på siden med udvidelser.")
                InstructionRow(number: 2, text: "Sæt flueben ved **BetterLectio** i listen til venstre.")
                InstructionRow(number: 3, text: "Kom tilbage hertil. Status opdaterer sig selv.")

                Button {
                    extensionState.openSafariSettings()
                } label: {
                    Label("Åbn Safari-indstillinger", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, BL.Space.s)

                HStack {
                    Spacer()
                    StatusPill(
                        isOn: extensionState.isEnabled,
                        onText: "Aktiveret i Safari",
                        offText: "Ikke aktiveret endnu"
                    )
                    Spacer()
                }
            }
        }
    }

    private var permissionStep: some View {
        StepScaffold(
            icon: "lock.open.fill",
            title: "Giv adgang til lectio.dk",
            subtitle: "Safari spørger om lov, første gang du besøger Lectio med udvidelsen slået til."
        ) {
            VStack(alignment: .leading, spacing: BL.Space.m) {
                InstructionRow(number: 1, text: "Åbn lectio.dk i Safari.")
                InstructionRow(number: 2, text: "Klik på **BetterLectio**-ikonet i værktøjslinjen, når Safari spørger.")
                InstructionRow(number: 3, text: "Vælg **Tillad altid på lectio.dk**. Ellers skal du give lov igen ved hvert besøg.")

                Button {
                    NSWorkspace.shared.open(BL.lectioURL)
                } label: {
                    Label("Åbn lectio.dk", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, BL.Space.s)

                Text("BetterLectio kører kun på lectio.dk og sender aldrig dit Lectio-login videre.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: BL.Space.m) {
                if step > 0 {
                    Button("Tilbage") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StepIndicator(current: step, total: stepCount)

                Spacer()

                Button(step == stepCount - 1 ? "Færdig" : "Fortsæt") {
                    if step == stepCount - 1 { onFinish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(step == 1 && !extensionState.isEnabled)
            }
            .padding(.horizontal, BL.Space.l)
            .padding(.vertical, BL.Space.m)
        }
        .background(.bar)
    }
}

// MARK: - Pieces

private struct StepScaffold<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: BL.Space.l) {
            Spacer(minLength: BL.Space.l)

            VStack(spacing: BL.Space.m) {
                IconChip(systemName: icon, size: 64)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            content
                .padding(BL.Space.l)
                .blCard(radius: BL.Radius.prominent)
                .frame(maxWidth: 520)

            Spacer(minLength: BL.Space.l)
        }
        .padding(.horizontal, BL.Space.xl)
    }
}

private struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: BL.Space.m) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: BL.Space.s) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.28), value: current)
        .accessibilityLabel("Trin \(current + 1) af \(total)")
    }
}
