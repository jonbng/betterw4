//
//  DocumentsView.swift
//  BetterW4
//
//  The W4 Documents CMS as a drill-down browser (features.md §1.10, ui.md §4.15).
//
//  Folders push another `DocumentsView`; a leaf page renders its TinyMCE body through
//  `HTMLContentRenderer`. Breadcrumbs come from W4's own `#breadcrumb` trail rather than from the
//  navigation stack, so a deep link opened straight from a Home link still says where it is.
//
//  Serves both CMS roots: `documents/index` (School) and `extraacademics/documents`
//  (Extra Academics). Same renderer on the server, same screen here.
//

import SwiftUI

struct DocumentsView: View {

    @StateObject private var viewModel: DocumentsViewModel
    /// Shown when this screen was opened straight at a sub-folder (a Home link, a deep link) and
    /// the level above it is therefore *not* the previous screen.
    private let showsUpLink: Bool

    @Environment(\.openURL) private var openURL

    init(
        library: DocumentLibrary = .school,
        route: String? = nil,
        showsUpLink: Bool = false
    ) {
        _viewModel = StateObject(
            wrappedValue: DocumentsViewModel(library: library, route: route)
        )
        self.showsUpLink = showsUpLink
    }

    var body: some View {
        List {
            if let trail = viewModel.breadcrumbText {
                Section {
                    Text(trail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }

            if showsUpLink, let parent = viewModel.parentRoute {
                Section {
                    NavigationLink {
                        DocumentsView(library: viewModel.library, route: parent)
                    } label: {
                        Label("Up one level", systemImage: "arrow.turn.left.up")
                    }
                }
            }

            if viewModel.isPage {
                pageSection
            } else {
                folderSections
            }

            if viewModel.freshness != nil {
                Section {
                    W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay { overlay }
    }

    // MARK: - States

    @ViewBuilder
    private var overlay: some View {
        if viewModel.isLoading, viewModel.listing == nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else if let message = viewModel.errorMessage, viewModel.listing == nil {
            ContentUnavailableView {
                Label("Documents unavailable", systemImage: "folder.badge.questionmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    Task { await viewModel.refresh() }
                }
            }
            .background(.background)
        }
    }

    // MARK: - Folder listing

    @ViewBuilder
    private var folderSections: some View {
        if viewModel.isEmptyFolder {
            Section {
                W4SurfaceEmptyRow(text: "No documents.", systemImage: "folder")
            }
        } else {
            if !viewModel.folders.isEmpty {
                Section("Folders") {
                    ForEach(viewModel.folders) { node in
                        nodeRow(node)
                    }
                }
            }
            if !viewModel.pages.isEmpty {
                Section("Pages") {
                    ForEach(viewModel.pages) { node in
                        nodeRow(node)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nodeRow(_ node: DocumentNode) -> some View {
        if let route = node.route, !route.isEmpty {
            NavigationLink {
                DocumentsView(library: DocumentLibrary.library(forRoute: route), route: route)
            } label: {
                label(for: node)
            }
        } else if let url = URL(string: node.href), !node.href.isEmpty {
            // Not an `index.php?r=…` link: W4 pointed somewhere else entirely, so it leaves the app
            // rather than being guessed into a route.
            Button {
                openURL(url)
            } label: {
                HStack {
                    label(for: node)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            label(for: node)
        }
    }

    private func label(for node: DocumentNode) -> some View {
        Label(
            node.title.isEmpty ? (node.isFolder ? "Folder" : "Page") : node.title,
            systemImage: node.isFolder ? "folder" : "doc.text"
        )
    }

    // MARK: - Leaf page

    @ViewBuilder
    private var pageSection: some View {
        if let page = viewModel.page {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(page.title.isEmpty ? viewModel.title : page.title)
                        .font(.title3.weight(.semibold))
                    if let details = page.details, !details.isEmpty {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if viewModel.contentBlocks.isEmpty {
                        Text("This page has no content.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        W4SurfaceRichText(blocks: viewModel.contentBlocks)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
