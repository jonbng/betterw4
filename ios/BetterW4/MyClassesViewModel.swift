//
//  MyClassesViewModel.swift
//  BetterW4
//
//  My classes — cache-first index, then a refresh. A class page already in
//  the cache is merged in so student counts appear without a second request.
//

import Combine
import Foundation

@MainActor
final class MyClassesViewModel: ObservableObject {

    @Published private(set) var classes: [MyClass] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var nextLessons: [String: ClassNextLesson] = [:]

    private let repository: MyClassRepository
    private var loadGeneration: UUID?

    init(repository: MyClassRepository = .shared) {
        self.repository = repository
    }

    /// UWC id of the signed-in student, mapped onto the demo roster id.
    var selfUwcId: String? {
        W4RequestContext.current()?.rosterUwcId
    }

    func `class`(id: String) -> MyClass? {
        classes.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    func nextLesson(for classId: String) -> ClassNextLesson? {
        nextLessons[classId.lowercased()]
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

        if !forceRefresh, classes.isEmpty, let cached = await repository.cachedIndex() {
            guard loadGeneration == generation else { return }
            classes = cached.value
            freshness = cached.freshness
            await applyCachedClasses(generation: generation)
            await applyNextLessons(generation: generation)
        }

        if classes.isEmpty { isLoading = true }
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
            await applyNextLessons(generation: generation)
        } catch {
            guard loadGeneration == generation else { return }
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if classes.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func applyNextLessons(generation: UUID) async {
        guard let cached = await TimetableRepository.shared.cachedWeek(containing: TimeProvider.now) else {
            guard loadGeneration == generation else { return }
            nextLessons = [:]
            return
        }
        guard loadGeneration == generation else { return }
        nextLessons = ClassNextLessons.map(in: cached.value, now: TimeProvider.now)
    }

    private func applyCachedClasses(generation: UUID) async {
        var next = classes
        for index in next.indices {
            guard loadGeneration == generation else { return }
            if let cached = await repository.cachedClass(id: next[index].id) {
                next[index] = W4ClassParser.merge(base: next[index], detail: cached.value)
            }
        }
        guard loadGeneration == generation else { return }
        classes = next
    }

    private func mergeIndex(_ incoming: [MyClass]) {
        guard !classes.isEmpty else {
            classes = incoming
            return
        }
        let previous = Dictionary(uniqueKeysWithValues: classes.map { ($0.id.lowercased(), $0) })
        classes = incoming.map { item in
            guard let existing = previous[item.id.lowercased()] else { return item }
            return W4ClassParser.merge(base: item, detail: existing)
        }
    }
}
