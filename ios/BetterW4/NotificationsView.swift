//
//  NotificationsView.swift
//  BetterW4
//
//  The notification bell and its list (ui.md §2.3, features.md §1.8).
//
//  Two entry points, one view model:
//
//    * `NotificationsBellButton` — the badged bell for a toolbar; presents the list as a sheet and
//      tells the repository to pause its 60-second poll while that sheet is open.
//    * `NotificationsView` — the same list as a pushable screen, for More ▸ Notifications.
//
//  THE EMPTY STATE IS THE MAIN STATE. Both real captures of this school's W4 ship an empty
//  `div.notifications` (bug B8), so "nothing here" is the shape we have actually seen. It is
//  rendered as an accomplishment, not as a failure — no error styling, no retry nag.
//

import SwiftUI

// MARK: - Bell

/// A badged bell for a toolbar. Tapping presents the notification list.
struct NotificationsBellButton: View {

    @StateObject private var viewModel = NotificationsViewModel()
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: viewModel.bellSymbol)
                    .imageScale(.large)
                if viewModel.hasUnread {
                    Text(viewModel.unreadCount > 9 ? "9+" : "\(viewModel.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(viewModel.badgeTint, in: Capsule())
                        .offset(x: 10, y: -8)
                }
            }
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(viewModel.accessibilityLabel)
        .task { await viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: isPresented) { _, newValue in
            Task { await viewModel.sheetDidChange(isOpen: newValue) }
        }
        .sheet(isPresented: $isPresented) {
            NotificationsView(viewModel: viewModel, isSheet: true)
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - List

/// The notification list: tasks first, then emails, with mark-read / clear actions.
struct NotificationsView: View {

    @StateObject private var viewModel: NotificationsViewModel
    private let isSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var sheetTarget: W4SurfaceSheetTarget?

    /// - Parameter viewModel: pass the bell's view model so the sheet and the badge stay in step;
    ///   omit it when the list is pushed on its own.
    init(viewModel: NotificationsViewModel? = nil, isSheet: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel ?? NotificationsViewModel())
        self.isSheet = isSheet
    }

    var body: some View {
        Group {
            if isSheet {
                NavigationStack { list }
            } else {
                list
            }
        }
        .task { await viewModel.start() }
        .sheet(item: $sheetTarget) { target in
            W4SurfacePageSheet(target: target)
        }
    }

    private var list: some View {
        List {
            if viewModel.isEmpty {
                Section {
                    Group {
                        if let failure = viewModel.loadErrorMessage {
                            unavailableState(failure)
                        } else {
                            emptyState
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                groupSections(viewModel.taskGroups, title: "Tasks", markAllTitle: "Mark all read") {
                    Task { await viewModel.markAllRead() }
                }
                groupSections(viewModel.emailGroups, title: "Emails", markAllTitle: "Mark all emails read") {
                    Task { await viewModel.markAllEmailsRead() }
                }
            }

            if viewModel.freshness != nil {
                Section {
                    W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh(force: true) }
        .overlay {
            if viewModel.isLoading, viewModel.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            if !viewModel.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            Task { await viewModel.markAllRead() }
                        } label: {
                            Label("Mark all read", systemImage: "envelope.open")
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.clearAll() }
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .disabled(viewModel.isWorking)
                }
            }
        }
        .alert(
            "Could not update that notification",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func groupSections(
        _ groups: [W4NotificationGroup],
        title: String,
        markAllTitle: String,
        markAll: @escaping () -> Void
    ) -> some View {
        if !groups.isEmpty {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                    }
                } header: {
                    HStack {
                        Text(index == 0 ? "\(title) · \(group.title)" : group.title)
                        Spacer()
                        if group.type != nil {
                            Button("Mark read") {
                                Task { await viewModel.markGroupRead(group) }
                            }
                            .font(.caption)
                            .textCase(nil)
                            .disabled(viewModel.isWorking)
                        }
                    }
                } footer: {
                    if index == groups.count - 1 {
                        Button(markAllTitle, action: markAll)
                            .font(.caption)
                            .disabled(viewModel.isWorking)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: W4Notification) -> some View {
        Button {
            Task { await viewModel.markRead(item) }
            if let url = item.url {
                sheetTarget = W4SurfaceSheetTarget(title: item.title, url: url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(NotificationsViewModel.tint(for: item.severity))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if item.url != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.clear(item) }
            } label: {
                Label("Clear", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await viewModel.markRead(item) }
            } label: {
                Label("Read", systemImage: "envelope.open")
            }
            .tint(.blue)
        }
    }

    // MARK: Empty

    /// A read that failed with nothing cached. Deliberately *not* the "all caught up" state — that
    /// would claim W4 said something it never got the chance to say.
    private func unavailableState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Notifications unavailable")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.refresh(force: true) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("You're all caught up")
                .font(.headline)
            Text(viewModel.isDemo
                 ? "Demo data. Not connected to W4."
                 : "W4 has no notifications for you right now. New assessments and mail show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}
