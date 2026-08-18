//
//  NotificationsViewModel.swift
//  BetterW4
//
//  The notification bell (features.md §1.8, ui.md §2.3, bug B8).
//
//  `NotificationRepository` owns the snapshot, the eight `notifications/*` writes and the 60-second
//  foreground poll; this view model is the thin main-actor layer that publishes the snapshot and
//  tells the repository when the sheet opens (the poll pauses while it is open, exactly as W4's own
//  `notifications.js` does).
//
//  BUG B8, and why the empty state matters more than the list: `div.notifications` is EMPTY in both
//  real captures of this school's W4. Zero notifications is the normal state, not a failure — so an
//  empty bell must read as "you are up to date", never as an error or a broken screen.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var snapshot: W4NotificationSnapshot = .empty
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    /// A failed **write**, surfaced as an alert. Cleared by the next successful action.
    @Published var errorMessage: String?
    /// A failed **read** with nothing cached to fall back on, surfaced inline in the list. A read
    /// that failed while rows are on screen sets nothing at all: the rows are still true.
    @Published private(set) var loadErrorMessage: String?

    // MARK: - Dependencies

    private let repository: NotificationRepository
    private var observationTask: Task<Void, Never>?
    private var loadGeneration: UUID?
    private var hasLoadedOnce = false

    init(repository: NotificationRepository = .shared) {
        self.repository = repository
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Paints the cached bell, follows the repository, refreshes, and starts the foreground poll.
    func start() async {
        observe()
        if let cached = await repository.loadCached() { apply(cached) }
        await refresh()
        await repository.startPolling()
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func observe() {
        guard observationTask == nil else { return }
        let stream = repository.updatesStream()
        // Inherits main-actor isolation from this type.
        observationTask = Task { [weak self] in
            for await update in stream {
                guard let self else { return }
                self.apply(update)
            }
        }
    }

    /// Cache-first; only posts `notifications/refresh` when the held copy is missing or stale.
    func refresh(force: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation
        if !hasLoadedOnce, snapshot.isEmpty { isLoading = true }

        do {
            let loaded = try await repository.load(forceRefresh: force)
            guard loadGeneration == generation else { return }
            apply(loaded)
            loadErrorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            handle(error, isWrite: false)
        }

        if loadGeneration == generation {
            isLoading = false
            hasLoadedOnce = true
        }
    }

    /// The sheet is open ⇒ the repository's poll pauses, so the list cannot reshuffle under a
    /// finger that is already reaching for a row.
    func sheetDidChange(isOpen: Bool) async {
        await repository.setSheetOpen(isOpen)
        if isOpen {
            await refresh()
        }
    }

    func applicationDidChangeActive(_ isActive: Bool) async {
        await repository.setForegroundActive(isActive)
        if isActive {
            await repository.startPolling()
        }
    }

    // MARK: - Writes

    /// Every write re-parses W4's answering fragment rather than assuming what it did.
    func markRead(_ notification: W4Notification) async {
        await perform(.read, identifier: notification.id)
    }

    func markGroupRead(_ group: W4NotificationGroup) async {
        guard let type = group.type, !type.isEmpty else { return }
        await perform(.readGroup, identifier: type)
    }

    func markAllRead() async {
        await perform(.readAll)
    }

    func markAllEmailsRead() async {
        await perform(.readAllEmails)
    }

    func clear(_ notification: W4Notification) async {
        await perform(.clear, identifier: notification.id)
    }

    func clearAll() async {
        await perform(.clearAll)
    }

    /// The single write path: one `$.post`, then the returned fragment replaces the snapshot.
    private func perform(_ action: W4NotificationAction, identifier: String? = nil) async {
        isWorking = true
        do {
            let loaded = try await repository.perform(action, identifier: identifier)
            apply(loaded)
            errorMessage = nil
        } catch {
            handle(error, isWrite: true)
        }
        isWorking = false
    }

    // MARK: - Derived state

    var isDemo: Bool { freshness == .demo }

    /// What the badge shows. Zero means no badge at all.
    var unreadCount: Int { max(0, snapshot.count) }

    var hasUnread: Bool { unreadCount > 0 }

    var taskGroups: [W4NotificationGroup] { snapshot.taskGroups }
    var emailGroups: [W4NotificationGroup] { snapshot.emailGroups }

    var isEmpty: Bool { snapshot.isEmpty }

    var bellSymbol: String { hasUnread ? "bell.badge.fill" : "bell" }

    var badgeTint: Color { Self.tint(for: snapshot.severity) }

    var accessibilityLabel: String {
        unreadCount == 0
            ? "Notifications, none unread"
            : "Notifications, \(unreadCount) unread"
    }

    static func tint(for severity: W4NotificationSeverity) -> Color {
        switch severity {
        case .normal: return .blue
        case .new: return .green
        case .overdue: return .red
        }
    }

    // MARK: - Internals

    private func apply(_ loaded: W4Loaded<W4NotificationSnapshot>) {
        snapshot = loaded.value
        freshness = loaded.freshness
    }

    private func handle(_ error: Error, isWrite: Bool) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        (error as? W4Error)?.notifyIfSessionExpired()
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if isWrite {
            // A write that did not happen must be said out loud: the student thinks it did.
            errorMessage = message
        } else if snapshot.isEmpty {
            // Nothing to show and nothing to fall back on — say why, inline.
            loadErrorMessage = message
        }
    }
}
