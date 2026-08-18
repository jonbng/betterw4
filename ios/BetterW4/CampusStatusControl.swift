//
//  CampusStatusControl.swift
//  BetterW4
//
//  The campus-status chip: a capsule that says where the student currently is, with the eleven
//  captured options behind it (ui.md §2.2, features.md §1.7).
//
//  It belongs in the app's chrome rather than in a tab because it is W4's own chrome: the widget is
//  rendered into every authenticated page, so the chip is refreshed for free by whatever screen the
//  student is already looking at.
//
//  The two rules that are easy to get wrong and are enforced below:
//
//    * "On campus" is a *different write* from every other option — it posts no location at all.
//      The view never builds that body itself; `CampusStatusRepository` does.
//    * "Other" is free text with a hard 20-character cap, taken from `input#other[maxlength=20]`.
//      The cap is enforced in the field here **and** again before the POST.
//

import SwiftUI

/// The toolbar chip plus its option picker.
struct CampusStatusControl: View {

    @StateObject private var viewModel = CampusStatusViewModel()
    @State private var showsFreeTextPrompt = false

    /// `true` shows the chip's location text next to the dot; `false` shows the dot alone, for
    /// tight toolbars.
    var showsLabel: Bool = true

    init(showsLabel: Bool = true) {
        self.showsLabel = showsLabel
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            chip
        }
        .disabled(viewModel.isSubmitting)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .alert("Set your location", isPresented: $showsFreeTextPrompt) {
            TextField("Where are you?", text: $viewModel.freeText)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) { viewModel.freeText = "" }
            Button("Set status") {
                guard let option = viewModel.freeTextOption else { return }
                Task { await viewModel.setStatus(option) }
            }
        } message: {
            Text("W4 allows up to \(CampusStatus.freeTextMaxLength) characters.")
        }
        .alert(
            "Could not set your campus status",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .accessibilityLabel(viewModel.accessibilityLabel)
    }

    // MARK: - Chip

    private var chip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.tint)
                .frame(width: 8, height: 8)
            if showsLabel {
                Text(viewModel.label)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
            }
            if viewModel.isSubmitting {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(viewModel.tint.opacity(0.12), in: Capsule())
        .foregroundStyle(.primary)
        .contentShape(Capsule())
    }

    // MARK: - Menu

    @ViewBuilder
    private var menuContent: some View {
        Section("I am currently") {
            ForEach(viewModel.options) { option in
                Button {
                    if option.isFreeText {
                        showsFreeTextPrompt = true
                    } else {
                        Task { await viewModel.setStatus(option) }
                    }
                } label: {
                    if option.id == viewModel.selectedOptionID {
                        Label(menuTitle(for: option), systemImage: "checkmark")
                    } else {
                        Text(menuTitle(for: option))
                    }
                }
            }
        }

        Section {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh status", systemImage: "arrow.clockwise")
            }
            if let caption = viewModel.freshness.flatMap(W4SurfaceFreshnessLabel.caption(for:)) {
                Text(caption)
            }
        }
    }

    /// The label W4 wrote, never the POST value — the two differ for "On campus" and "Other".
    private func menuTitle(for option: CampusLocationOption) -> String {
        option.isFreeText ? "\(option.label)…" : option.label
    }
}
