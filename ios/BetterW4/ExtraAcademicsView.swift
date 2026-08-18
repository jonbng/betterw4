//
//  ExtraAcademicsView.swift
//  BetterW4
//
//  Extra Academics — the half of UWC RCN that has no academic timetable: activities, the EA diary,
//  the portfolio, the three CAS interviews and SafetyNet (features.md §1.11, ui.md §4.16–4.20).
//
//  A sectioned list of the five surfaces plus the EA documents CMS. Each page pushes
//  `ExtraAcademicsPageView`, which renders W4's own `#content_inner` well: none of these five pages
//  has ever been captured, so the app shows exactly what W4 sent rather than a parser's guess about
//  markup nobody has seen.
//
//  SafetyNet is pastoral rather than academic: it is listed without a badge, without a count and
//  without any summary of its numbers on this screen.
//

import SwiftUI

struct ExtraAcademicsView: View {

    init() {}

    var body: some View {
        List {
            Section {
                ForEach(Self.activityPages, id: \.rawValue) { page in
                    NavigationLink {
                        ExtraAcademicsPageView(page: page)
                    } label: {
                        Label(page.displayName, systemImage: Self.symbol(for: page))
                    }
                }
            } header: {
                Text("Activities")
            }

            Section {
                ForEach(Self.reviewPages, id: \.rawValue) { page in
                    NavigationLink {
                        ExtraAcademicsPageView(page: page)
                    } label: {
                        Label(page.displayName, systemImage: Self.symbol(for: page))
                    }
                }
            } header: {
                Text("Reviews")
            } footer: {
                Text("SafetyNet is your weekly wellness report. It stays on this device only as page content.")
            }

            Section("Documents") {
                NavigationLink {
                    DocumentsView(library: .extraAcademics)
                } label: {
                    Label("Extra Academics documents", systemImage: "folder")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Extra Academics")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Grouping

    /// The doing half.
    static let activityPages: [ExtraAcademicsPage] = [.myActivities, .diary, .portfolio]
    /// The reflecting half.
    static let reviewPages: [ExtraAcademicsPage] = [.interviews, .safetyNet]

    static func symbol(for page: ExtraAcademicsPage) -> String {
        switch page {
        case .myActivities: return "figure.outdoor.cycle"
        case .diary: return "book"
        case .portfolio: return "folder.badge.person.crop"
        case .interviews: return "person.line.dotted.person"
        case .safetyNet: return "heart.text.square"
        }
    }
}

// MARK: - One page

/// One Extra Academics page, rendered from W4's own content well.
struct ExtraAcademicsPageView: View {

    @StateObject private var viewModel: ExtraAcademicsViewModel
    @State private var sheetTarget: W4SurfaceSheetTarget?

    init(page: ExtraAcademicsPage) {
        _viewModel = StateObject(wrappedValue: ExtraAcademicsViewModel(page: page))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.hasContent {
                    W4SurfaceRichText(blocks: viewModel.blocks)
                } else if !viewModel.isLoading, viewModel.errorMessage == nil {
                    emptyState
                }

                W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay { overlay }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetTarget = W4SurfaceSheetTarget(
                        title: viewModel.title,
                        url: viewModel.pageURL
                    )
                } label: {
                    Label("Open in W4", systemImage: "arrow.up.forward.square")
                }
            }
        }
        .sheet(item: $sheetTarget) { target in
            W4SurfacePageSheet(target: target)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if viewModel.isLoading, !viewModel.hasContent {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else if let message = viewModel.errorMessage, !viewModel.hasContent {
            ContentUnavailableView {
                Label("\(viewModel.page.displayName) is unavailable", systemImage: "figure.outdoor.cycle")
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nothing here yet", systemImage: "tray")
                .font(.headline)
            Text(viewModel.isDemo
                 ? "Demo data. Not connected to W4."
                 : "W4 returned this page with no content. Open it in W4 to check.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
