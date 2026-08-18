//
//  DocumentsViewModel.swift
//  BetterW4
//
//  One node of the W4 Documents CMS — a folder listing or a rendered leaf page
//  (features.md §1.10, ui.md §4.15).
//
//  One view model per node, because Documents is a *tree*: pushing a folder creates a new view
//  model for that folder's route, and popping back leaves the parent's already-loaded state
//  untouched. `DocumentRepository` caches every node under its own key, so walking back into a
//  folder is free.
//
//  The two CMS roots (`documents/index` for School, `extraacademics/documents` for Extra Academics)
//  share this type: same renderer on the server, same models here.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class DocumentsViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var listing: DocumentListing?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// The leaf page's TinyMCE body, rendered once per load rather than on every SwiftUI update.
    @Published private(set) var contentBlocks: [ContentBlock] = []

    // MARK: - Identity

    /// Which CMS this node belongs to.
    let library: DocumentLibrary
    /// The exact route this view model loads, siblings included (`documents/index&folder_id=27`).
    let route: String

    private let repository: DocumentRepository
    private var loadGeneration: UUID?

    init(
        library: DocumentLibrary = .school,
        route: String? = nil,
        repository: DocumentRepository = DocumentRepository()
    ) {
        let trimmed = route?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = trimmed.isEmpty ? library.rootRoute : trimmed
        // A route always wins over the passed-in library, so following a node out of the School CMS
        // into the Extra Academics one cannot mislabel the node.
        self.library = trimmed.isEmpty ? library : DocumentLibrary.library(forRoute: resolved)
        self.route = resolved
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

        if !forceRefresh, listing == nil, let cached = await repository.cachedListing(forRoute: route) {
            guard loadGeneration == generation else { return }
            apply(cached)
        }

        if listing == nil { isLoading = true }

        do {
            let loaded = try await repository.load(route: route, forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            apply(loaded)
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            handle(error)
        }

        if loadGeneration == generation { isLoading = false }
    }

    private func apply(_ loaded: W4Loaded<DocumentListing>) {
        listing = loaded.value
        freshness = loaded.freshness
        contentBlocks = loaded.value.page.map { HTMLContentRenderer.blocks(fromHTML: $0.contentHTML) } ?? []
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        (error as? W4Error)?.notifyIfSessionExpired()
        guard listing == nil else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Derived state

    var isDemo: Bool { freshness == .demo }

    /// The page's own heading, falling back to the library name at the root.
    var title: String {
        let parsed = listing?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return parsed.isEmpty ? library.displayName : parsed
    }

    var isRoot: Bool { route == library.rootRoute }

    var folders: [DocumentNode] { listing?.folders ?? [] }
    var pages: [DocumentNode] { listing?.pages ?? [] }
    var items: [DocumentNode] { listing?.items ?? [] }

    var breadcrumb: [DocumentBreadcrumb] { listing?.breadcrumb ?? [] }

    /// The trail W4 rendered, as one line: `Home › Documents › Internal Information`.
    var breadcrumbText: String? {
        let titles = breadcrumb
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return nil }
        return titles.joined(separator: " › ")
    }

    /// `div.up > a` — the level above this one, when W4 offered it.
    var parentRoute: String? {
        guard let parent = listing?.parentRoute?.trimmingCharacters(in: .whitespacesAndNewlines),
              !parent.isEmpty, parent != route else { return nil }
        return parent
    }

    /// Non-nil only when this node really is a rendered page (never guessed from an empty folder).
    var page: DocumentPage? { listing?.page }

    var isPage: Bool { listing?.isPage ?? false }

    /// True when W4 answered with a folder that has nothing in it.
    var isEmptyFolder: Bool {
        guard let listing else { return false }
        return !listing.isPage && listing.items.isEmpty
    }
}
