//
//  HousesViewModel.swift
//  BetterW4
//
//  Boarding-house overview. The index paints first; each house page fills in rooms
//  underneath so opening More ▸ Houses is never blocked on five sequential fetches.
//

import Combine
import Foundation

@MainActor
final class HousesViewModel: ObservableObject {

    @Published private(set) var houses: [House] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var freshness: W4Freshness?

    private let repository: HouseRepository
    private var loadGeneration: UUID?

    init(repository: HouseRepository = .shared) {
        self.repository = repository
    }

    func house(id: String) -> House? {
        houses.first { $0.id == id }
    }

    func load() async {
        await run(forceRefresh: false)
    }

    func refresh() async {
        await run(forceRefresh: true)
    }

    private func run(forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation

        if !forceRefresh, houses.isEmpty, let cached = await repository.cachedIndex() {
            guard loadGeneration == generation else { return }
            houses = cached.value
            freshness = cached.freshness
            await applyCachedHouses(generation: generation)
        }

        if houses.isEmpty { isLoading = true }
        isRefreshing = true
        defer {
            if loadGeneration == generation {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let index = try await repository.loadIndex(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            mergeIndex(index.value)
            freshness = index.freshness
            errorMessage = nil
            await loadHousePages(forceRefresh: forceRefresh, generation: generation)
        } catch {
            guard loadGeneration == generation else { return }
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if houses.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func applyCachedHouses(generation: UUID) async {
        var next = houses
        for index in next.indices {
            guard loadGeneration == generation else { return }
            if let cached = await repository.cachedHouse(id: next[index].id) {
                next[index] = cached.value
            }
        }
        guard loadGeneration == generation else { return }
        houses = next
    }

    private func loadHousePages(forceRefresh: Bool, generation: UUID) async {
        for (offset, house) in houses.enumerated() {
            guard loadGeneration == generation else { return }
            let priority: FetchPriority = offset == 0 ? .important : .opportunistic
            do {
                let loaded = try await repository.loadHouse(
                    id: house.id,
                    forceRefresh: forceRefresh,
                    priority: priority
                )
                guard loadGeneration == generation else { return }
                upsert(loaded.value)
                if case .fresh = loaded.freshness { freshness = .fresh }
            } catch {
                if error is CancellationError { return }
                (error as? W4Error)?.notifyIfSessionExpired()
            }
        }
    }

    private func mergeIndex(_ incoming: [House]) {
        houses = incoming.map { listed in
            if let existing = houses.first(where: { $0.id == listed.id }), existing.loaded {
                return existing
            }
            return listed
        }
    }

    private func upsert(_ house: House) {
        if let index = houses.firstIndex(where: { $0.id == house.id }) {
            houses[index] = house
        } else {
            houses.append(house)
        }
    }
}
