//
//  MyTeachersViewModel.swift
//  BetterW4
//
//  My teachers — cache-first list, then a refresh.
//

import Combine
import Foundation

@MainActor
final class MyTeachersViewModel: ObservableObject {

    @Published private(set) var teachers: [MyTeacher] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var freshness: W4Freshness?

    private let repository: MyTeacherRepository
    private var loadGeneration: UUID?

    init(repository: MyTeacherRepository = .shared) {
        self.repository = repository
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

        if !forceRefresh, teachers.isEmpty, let cached = await repository.cached() {
            guard loadGeneration == generation else { return }
            teachers = cached.value
            freshness = cached.freshness
        }

        if teachers.isEmpty { isLoading = true }
        isRefreshing = true
        defer {
            if loadGeneration == generation {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let loaded = try await repository.load(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            teachers = loaded.value
            freshness = loaded.freshness
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if teachers.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
