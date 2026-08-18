//
//  StudentSearchView.swift
//  BetterW4
//
//  The people directory: students (all / first year / second year) and staff, every row keyed on
//  a UWC id, every photo derived from that id (`{uwc_id}_thumb.jpg`) with initials as the
//  fallback.
//
//  Data comes from `DirectoryViewModel`, which reads `DirectoryRepository` — cached rows paint
//  first, W4 refreshes underneath, and a failed refresh leaves what is on screen alone.
//

import Combine
import SwiftUI
import UIKit

/// Where a directory row leads. The UWC id is the only id W4 has, so it is the whole route.
private enum DirectoryRoute: Hashable {
    case person(String)
}

// MARK: - Screen

struct StudentSearchView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @Binding var navigationPath: NavigationPath
    var presentation: DirectoryPresentation = .full

    @StateObject private var viewModel = DirectoryViewModel()

    var body: some View {
        ScrollView {
            let sections = viewModel.sections
            LazyVStack(alignment: .leading, spacing: 20) {
                if viewModel.isSearching {
                    searchResults
                } else {
                    ForEach(sections) { section in
                        peopleSection(section)
                    }
                    if sections.isEmpty {
                        emptyState
                    }
                }
                if !sections.isEmpty || viewModel.isSearching {
                    footer
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchQuery, prompt: "Search students and staff")
        .refreshable {
            await viewModel.refresh()
        }
        .task(id: student.studentId) {
            await viewModel.load(presentation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
            Task { await viewModel.reloadAfterCacheClear() }
        }
        .navigationDestination(for: DirectoryRoute.self) { route in
            switch route {
            case .person(let uwcId):
                if let person = viewModel.person(uwcId: uwcId) {
                    StudentProfileView(person: person, directory: viewModel)
                } else {
                    StudentProfileView(uwcId: uwcId, directory: viewModel)
                }
            }
        }
    }

    // MARK: Sections

    private func peopleSection(_ section: DirectoryPeopleSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(section.title, count: section.people.count)

            if section.id == "pinned" {
                pinnedGrid(section.people)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(section.people) { person in
                        row(person)
                    }
                }
            }
        }
    }

    private func pinnedGrid(_ people: [DirectoryPerson]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 16
        ) {
            ForEach(people) { person in
                NavigationLink(value: DirectoryRoute.person(person.uwcId)) {
                    VStack(spacing: 6) {
                        W4AvatarView(
                            url: viewModel.photoURL(for: person),
                            name: person.displayName,
                            size: 56
                        )
                        Text(firstName(of: person))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if let subtitle = shortSubtitle(for: person) {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: person) }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.searchResults.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("No results")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Results", count: viewModel.searchResults.count)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.searchResults) { person in
                        row(person)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !viewModel.isLoading {
            VStack(spacing: 10) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 34))
                    .foregroundColor(.secondary)
                Text(viewModel.errorMessage ?? viewModel.notice ?? "No people found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                if viewModel.errorMessage != nil {
                    Button("Try again") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if viewModel.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Text(freshnessLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.3)
            Text("Loading people…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: Rows

    private func row(_ person: DirectoryPerson) -> some View {
        NavigationLink(value: DirectoryRoute.person(person.uwcId)) {
            HStack(spacing: 12) {
                W4AvatarView(
                    url: viewModel.photoURL(for: person),
                    name: person.displayName,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    if let subtitle = subtitle(for: person) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if viewModel.isPinned(person) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: person) }
    }

    @ViewBuilder
    private func menu(for person: DirectoryPerson) -> some View {
        Section {
            Button {
                navigationPath.append(DirectoryRoute.person(person.uwcId))
            } label: {
                Label("Open profile", systemImage: "person.crop.circle")
            }
            Button {
                viewModel.togglePin(person)
            } label: {
                Label(
                    viewModel.isPinned(person) ? "Unpin" : "Pin",
                    systemImage: viewModel.isPinned(person) ? "pin.slash" : "pin"
                )
            }
            Button {
                UIPasteboard.general.string = person.email
            } label: {
                Label("Copy email", systemImage: "envelope")
            }
        } header: {
            Text(person.displayName)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
    }

    private func subtitle(for person: DirectoryPerson) -> String? {
        if let subtitle = person.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subtitle.isEmpty {
            return subtitle
        }
        let parts = [
            person.year.map { "Year \($0)" },
            person.house,
            person.country
        ].compactMap { $0 }
        if parts.isEmpty {
            return person.kind == .staff ? "Staff" : nil
        }
        return parts.joined(separator: " · ")
    }

    private func shortSubtitle(for person: DirectoryPerson) -> String? {
        if let year = person.year { return "Year \(year)" }
        if person.kind == .staff { return "Staff" }
        return person.house ?? person.country
    }

    private func firstName(of person: DirectoryPerson) -> String {
        person.displayName.split(separator: " ").first.map(String.init) ?? person.displayName
    }

    private var freshnessLabel: String {
        switch viewModel.freshness {
        case .fresh:
            return "Up to date"
        case .demo:
            return "Demo data"
        case .cached(let fetchedAt, let isStale):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let when = formatter.localizedString(for: fetchedAt, relativeTo: TimeProvider.now)
            return isStale ? "Offline copy from \(when)" : "Updated \(when)"
        case nil:
            return viewModel.isRefreshing ? "Refreshing…" : ""
        }
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        StudentSearchView(
            student: .demo,
            authViewModel: AuthenticationViewModel(),
            navigationPath: $path
        )
    }
}
