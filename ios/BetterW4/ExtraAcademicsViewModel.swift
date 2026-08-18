//
//  ExtraAcademicsViewModel.swift
//  BetterW4
//
//  One Extra Academics page: My activities, My EA diary, My portfolio, My CAS interviews or
//  My SafetyNet (features.md §1.11, plan Wave 5 item 5.8).
//
//  WHY THIS RENDERS A PAGE RATHER THAN A MODEL. None of these five pages has ever been captured —
//  features.md §1.11 says so in as many words. Writing selectors against markup nobody has seen
//  produces a parser that returns `[]` on the real site while every fixture test passes, so
//  `ExtraAcademicsRepository` hands back the page itself and this view model renders
//  `#content_inner` — W4's per-page content well, verified on 19 of the 20 fixtures — through
//  `HTMLContentRenderer`. The moment someone captures these pages, the parse moves into a parser
//  and this file keeps its shape.
//
//  The heading and the rendered blocks are computed once per load, not on every SwiftUI update.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ExtraAcademicsViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var blocks: [ContentBlock] = []
    @Published private(set) var heading: String?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// True when W4 answered but `#content_inner` held nothing we could render.
    @Published private(set) var hasContent = false

    // MARK: - Identity

    let page: ExtraAcademicsPage

    private let repository: ExtraAcademicsRepository
    private var loadGeneration: UUID?

    init(page: ExtraAcademicsPage, repository: ExtraAcademicsRepository = .shared) {
        self.page = page
        self.repository = repository
    }

    // MARK: - Loading

    func load() async {
        await run(forceRefresh: false)
    }

    func refresh() async {
        await run(forceRefresh: true)
    }

    private func run(forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation

        if !forceRefresh, !hasContent, let cached = await repository.cachedPage(page) {
            guard loadGeneration == generation else { return }
            apply(cached)
        }

        if !hasContent { isLoading = true }

        do {
            let loaded = try await repository.page(page, forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            apply(loaded)
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            handle(error)
        }

        if loadGeneration == generation { isLoading = false }
    }

    private func apply(_ loaded: W4Loaded<W4PageSnapshot>) {
        let snapshot = loaded.value
        freshness = loaded.freshness
        heading = snapshot.heading
        if let fragment = snapshot.contentFragmentHTML {
            blocks = Self.withoutLeadingHeading(
                HTMLContentRenderer.blocks(fromHTML: fragment, baseURL: W4Routes.originURL),
                matching: snapshot.heading
            )
            hasContent = !blocks.isEmpty
        } else {
            blocks = []
            hasContent = false
        }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        (error as? W4Error)?.notifyIfSessionExpired()
        guard !hasContent else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Derived state

    var isDemo: Bool { freshness == .demo }

    /// W4's own `<h2>` when it wrote one, the menu label otherwise — the two agree by design.
    var title: String {
        let parsed = heading?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return parsed.isEmpty ? page.displayName : parsed
    }

    /// The W4 page behind this screen, for the "Open in W4" affordance.
    var pageURL: URL { W4Routes.url(page.route) }

    /// `#content_inner` opens with the page's own `<h2>`, which the navigation bar is already
    /// showing. Dropping that one duplicate heading is the only edit made to W4's markup.
    static func withoutLeadingHeading(_ blocks: [ContentBlock], matching heading: String?) -> [ContentBlock] {
        guard let heading = heading?.trimmingCharacters(in: .whitespacesAndNewlines),
              !heading.isEmpty,
              case .heading(_, let inlines)? = blocks.first,
              HTMLContentRenderer.plainText(inlines)
                .caseInsensitiveCompare(heading) == .orderedSame
        else { return blocks }
        return Array(blocks.dropFirst())
    }
}
