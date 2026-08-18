//
//  CampusStatusViewModel.swift
//  BetterW4
//
//  The boarding-school feature: "I am currently …" (features.md §1.7, plan D-12, bug B6).
//
//  The chip is rendered into the chrome of every authenticated W4 page, so the happy path costs no
//  request at all — `ChromeObserver` feeds `CampusStatusRepository` from pages other screens already
//  fetched, and this view model just follows the repository's update stream.
//
//  THE WRITE RULES, which live in the repository and the parser and are only *surfaced* here:
//
//    * "On campus"   → `status=on`, with **no `location` key at all**
//    * "Other"       → `status=off`, `location=<free text>` capped at 20 characters
//    * anything else → `status=off`, `location=<the option's POST value>` — never its label
//
//  The response is re-parsed rather than assumed: W4's own JS throws the body away, but when the
//  server does echo the widget back, the server is right and our projection is a guess.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class CampusStatusViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var status: CampusStatus?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var isSubmitting = false
    /// A failed write, in W4's own words where it gave any. Cleared by the next successful write.
    @Published var errorMessage: String?

    /// The free-text box behind the "Other" option. Capped at the widget's own `maxlength=20`.
    @Published var freeText: String = "" {
        didSet {
            if freeText.count > CampusStatus.freeTextMaxLength {
                freeText = String(freeText.prefix(CampusStatus.freeTextMaxLength))
            }
        }
    }

    // MARK: - Dependencies

    private let repository: CampusStatusRepository
    private var observationTask: Task<Void, Never>?
    private var loadGeneration: UUID?

    init(repository: CampusStatusRepository = .shared) {
        self.repository = repository
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Paints the cached chip, starts following the repository, then refreshes cache-first.
    func start() async {
        observe()
        let cached = await repository.loadCached()
        if let cached { apply(cached) }
        await load()
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    private func observe() {
        guard observationTask == nil else { return }
        let stream = repository.updatesStream()
        // `Task { }` inside a `@MainActor` type inherits main-actor isolation, so the loop body
        // touches published state directly.
        observationTask = Task { [weak self] in
            for await update in stream {
                guard let self else { return }
                // A write in flight owns the chip: a page harvested mid-POST would flip the label
                // back under the student's finger.
                if self.isSubmitting { continue }
                self.apply(update)
            }
        }
    }

    /// Cache-first read; only reaches `site/index` when nothing fresh is held.
    func load(forceRefresh: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation
        do {
            let loaded = try await repository.load(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            apply(loaded)
        } catch {
            guard loadGeneration == generation else { return }
            handle(error, isWrite: false)
        }
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    // MARK: - Writing

    /// Posts one option. Optimistic: the chip flips immediately and reverts if W4 refuses.
    func setStatus(_ option: CampusLocationOption) async {
        let previous = status
        let previousFreshness = freshness

        if option.isFreeText, freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = CampusStatusWriteError.locationRequired.errorDescription
            return
        }

        errorMessage = nil
        isSubmitting = true
        status = CampusStatusRepository.projected(
            option: option,
            freeText: option.isFreeText ? freeText : nil,
            onto: previous
        )

        do {
            let confirmed = try await repository.setStatus(
                option: option,
                freeText: option.isFreeText ? freeText : nil
            )
            apply(confirmed)
            if option.isFreeText { freeText = "" }
        } catch {
            // Never leave a student believing they are signed off campus when W4 says otherwise.
            status = previous
            freshness = previousFreshness
            handle(error, isWrite: true)
        }
        isSubmitting = false
    }

    /// "I am back on campus" — the one write that posts no `location` key.
    func setOnCampus() async {
        guard let option = onCampusOption else { return }
        await setStatus(option)
    }

    // MARK: - Derived state

    var isDemo: Bool { freshness == .demo }

    /// The live radio list when W4 rendered one, the eleven captured options otherwise.
    var options: [CampusLocationOption] { status?.options ?? CampusStatus.defaultOptions }

    var onCampusOption: CampusLocationOption? {
        options.first { $0.isOnCampus }
    }

    var freeTextOption: CampusLocationOption? {
        options.first { $0.isFreeText }
    }

    var isOnCampus: Bool { status?.isOnCampus ?? false }

    /// What the chip shows: "On campus", or the location W4 recorded.
    var label: String { status?.label ?? "Campus status" }

    var selectedOptionID: String? { status?.selectedOption?.id }

    var tint: Color {
        guard let status else { return .secondary }
        return status.isOnCampus ? .green : .orange
    }

    var accessibilityLabel: String { "Campus status, \(label)" }

    // MARK: - Internals

    private func apply(_ loaded: W4Loaded<CampusStatus>) {
        status = loaded.value
        freshness = loaded.freshness
    }

    private func handle(_ error: Error, isWrite: Bool) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        (error as? W4Error)?.notifyIfSessionExpired()
        // Only a failed **write** is worth interrupting anybody for. A failed read simply leaves the
        // chip showing whatever it last knew (or nothing at all) — a toolbar control that pops an
        // alert because the phone is on a train is worse than a chip that stays quiet.
        guard isWrite else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
