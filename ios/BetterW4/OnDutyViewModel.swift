//
//  OnDutyViewModel.swift
//  BetterW4
//
//  Who is on duty today. Cache-first, then refresh. A failed schedule fetch
//  never blanks the contact list the student opened the screen for.
//

import Combine
import Foundation

@MainActor
final class OnDutyViewModel: ObservableObject {

    @Published private(set) var snapshot: OnDutySnapshot?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: OnDutyRepository
    private var loadGeneration: UUID?

    init(repository: OnDutyRepository = OnDutyRepository()) {
        self.repository = repository
    }

    var groups: [OnDutyGroup] { snapshot?.today.groups ?? [] }
    var upcoming: [OnDutyDay] { snapshot?.upcoming ?? [] }
    var dateLabel: String? { snapshot?.today.dateLabel }
    var isEmpty: Bool { snapshot?.today.isEmpty ?? true }

    func load() async {
        await run(forceRefresh: false)
    }

    func refresh() async {
        await run(forceRefresh: true)
    }

    private func run(forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation

        if !forceRefresh, snapshot == nil, let cached = await repository.cachedSnapshot() {
            guard loadGeneration == generation else { return }
            snapshot = cached.value
            freshness = cached.freshness
        }

        if snapshot == nil { isLoading = true }

        do {
            let loaded = try await repository.load(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            snapshot = loaded.value
            freshness = loaded.freshness
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            if snapshot == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load who is on duty."
            }
        }

        if loadGeneration == generation { isLoading = false }
    }

    static func caption(for day: OnDutyDay, now: Date = TimeProvider.now) -> String {
        guard let date = day.date else { return day.dateLabel }
        let today = W4Dates.startOfDay(now)
        if W4Dates.startOfDay(date) == today { return "Today" }
        if W4Dates.startOfDay(date) == W4Dates.adding(days: 1, to: today) { return "Tomorrow" }
        return day.dateLabel
    }
}
