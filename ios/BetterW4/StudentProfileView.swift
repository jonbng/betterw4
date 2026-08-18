//
//  StudentProfileView.swift
//  BetterW4
//
//  One person's public W4 profile — `people/students/student&uwc_id=` for a student,
//  `people/staff/staff&uwc_id=` for staff — served by `ProfileRepository`.
//
//  The row that pushed this screen is already a profile's worth of data, so it paints instantly
//  and the page fetch fills in the rest. A profile the signed-in student is not allowed to open
//  (`W4Error.forbidden`) leaves the row data on screen and never logs anybody out.
//

import Combine
import SwiftUI
import UIKit

// MARK: - View model

@MainActor
final class PersonProfileModel: ObservableObject {

    @Published private(set) var profile: StudentProfile?
    @Published private(set) var freshness: W4Freshness?
    /// Only ever set when there is nothing at all to show.
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false

    private let repository: ProfileRepository
    /// A newer load always wins, so a slow answer for a person the student has left cannot
    /// overwrite the one they are looking at now.
    private var generation = 0

    init(repository: ProfileRepository = .shared) {
        self.repository = repository
    }

    /// - Parameter fallback: what the directory row already knew, shown until the page answers.
    func load(
        uwcId: String,
        kind: DirectoryPersonKind?,
        fallback: StudentProfile?,
        forceRefresh: Bool = false
    ) async {
        generation += 1
        let token = generation

        if profile == nil { profile = fallback }

        if !forceRefresh, let cached = await repository.cachedProfile(uwcId: uwcId) {
            guard token == generation else { return }
            profile = StudentProfile(profile: cached.value)
            freshness = cached.freshness
        }

        // A spinner is only justified when the screen would otherwise be blank.
        isLoading = profile == nil
        isRefreshing = true
        defer {
            if token == generation {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let loaded = try await repository.profile(
                uwcId: uwcId,
                kind: kind,
                forceRefresh: forceRefresh
            )
            guard token == generation else { return }
            profile = StudentProfile(profile: loaded.value)
            freshness = loaded.freshness
            errorMessage = nil
        } catch {
            guard token == generation else { return }
            if error is CancellationError { return }
            // Only a dead session logs out. `.forbidden` just means this profile is not ours
            // to read, and the row data stays exactly where it is.
            (error as? W4Error)?.notifyIfSessionExpired()
            if profile == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Screen

struct StudentProfileView: View {

    private let uwcId: String
    private let kind: DirectoryPersonKind?
    private let fallback: StudentProfile?

    @ObservedObject var directory: DirectoryViewModel
    @StateObject private var model = PersonProfileModel()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingPhoto = false
    @State private var didCopyEmail = false

    /// Pushed from a directory row: everything the row knew is on screen before the fetch starts.
    init(person: DirectoryPerson, directory: DirectoryViewModel) {
        self.uwcId = person.uwcId
        self.kind = person.kind
        self.fallback = StudentProfile(person: person)
        self._directory = ObservedObject(wrappedValue: directory)
    }

    /// Pushed from a bare UWC id (a deep link, or a person who has left the cached table).
    init(uwcId: String, directory: DirectoryViewModel) {
        self.uwcId = uwcId
        self.kind = nil
        self.fallback = nil
        self._directory = ObservedObject(wrappedValue: directory)
    }

    private var profile: StudentProfile? { model.profile ?? fallback }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let profile {
                    hero(profile)
                    actions(profile)
                    details(profile)
                    extraFields(profile)
                    footer
                } else if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                } else {
                    unavailable
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.load(uwcId: uwcId, kind: kind, fallback: fallback, forceRefresh: true)
        }
        .task(id: uwcId) {
            await model.load(uwcId: uwcId, kind: kind, fallback: fallback)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
            Task { await model.load(uwcId: uwcId, kind: kind, fallback: fallback, forceRefresh: true) }
        }
        .sheet(isPresented: $showingPhoto) {
            if let profile {
                PersonPhotoPreview(name: profile.displayName, url: profile.photoURL)
            }
        }
    }

    // MARK: Hero

    private func hero(_ profile: StudentProfile) -> some View {
        VStack(spacing: 12) {
            Button {
                showingPhoto = profile.photoURL != nil
            } label: {
                W4AvatarView(url: profile.photoURL, name: profile.displayName, size: 108)
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3))
            }
            .buttonStyle(.plain)
            .disabled(profile.photoURL == nil)
            .accessibilityLabel("Photo of \(profile.displayName)")
            .accessibilityHint("Opens the photo at full size")

            VStack(spacing: 5) {
                Text(profile.displayName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if let secondary = profile.secondaryName {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let subtitle = profile.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Label(
                    profile.kindLabel,
                    systemImage: profile.kind == .staff ? "person.text.rectangle.fill" : "person.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ profile: StudentProfile) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                Button { togglePin() } label: { wideActionLabel(pinTitle, systemImage: pinIcon) }
                    .buttonStyle(.plain)
                Button { copyEmail(profile) } label: { wideActionLabel(emailTitle, systemImage: "envelope") }
                    .buttonStyle(.plain)
                NavigationLink {
                    W4PageScreen(title: profile.displayName, url: profile.profileURL)
                } label: {
                    wideActionLabel("Open on W4", systemImage: "safari")
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 10) {
                Button { togglePin() } label: { compactActionLabel(pinTitle, systemImage: pinIcon) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pinTitle)
                Button { copyEmail(profile) } label: { compactActionLabel(emailTitle, systemImage: "envelope") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy email address")
                NavigationLink {
                    W4PageScreen(title: profile.displayName, url: profile.profileURL)
                } label: {
                    compactActionLabel("Open on W4", systemImage: "safari")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pinTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    private var pinIcon: String {
        isPinned ? "pin.slash.fill" : "pin.fill"
    }

    private var emailTitle: String {
        didCopyEmail ? "Copied" : "Email"
    }

    private var isPinned: Bool {
        directory.pinnedUwcIds.contains(uwcId)
    }

    private func togglePin() {
        guard let person = directory.person(uwcId: uwcId) ?? fallbackPerson else { return }
        directory.togglePin(person)
    }

    /// A person the cached table has never seen can still be pinned: the id is the whole key.
    private var fallbackPerson: DirectoryPerson? {
        guard let profile else { return nil }
        return DirectoryPerson(
            uwcId: profile.uwcId,
            name: profile.name.isEmpty ? profile.uwcId : profile.name,
            kind: profile.kind,
            preferredName: profile.preferredName,
            year: profile.year,
            house: profile.house,
            country: profile.country,
            pronouns: profile.pronouns,
            subtitle: profile.subtitle,
            photoURL: profile.photoURL
        )
    }

    private func copyEmail(_ profile: StudentProfile) {
        UIPasteboard.general.string = profile.email
        didCopyEmail = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopyEmail = false
        }
    }

    // MARK: Details

    private func details(_ profile: StudentProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.detailRows(for: profile)) { row in
                detailRow(row.title, value: row.value, systemImage: row.systemImage)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Every field W4 can tell us about a person, in a fixed order, skipping the ones it did not.
    private static func detailRows(for profile: StudentProfile) -> [ProfileDetailRow] {
        var rows: [ProfileDetailRow] = [
            ProfileDetailRow(title: "UWC id", value: profile.uwcId, systemImage: "person.text.rectangle"),
            ProfileDetailRow(title: "Email", value: profile.email, systemImage: "envelope")
        ]
        if let year = profile.year {
            rows.append(ProfileDetailRow(title: "Year", value: year, systemImage: "graduationcap"))
        }
        if let house = profile.house {
            rows.append(ProfileDetailRow(title: "House", value: house, systemImage: "house.fill"))
        }
        if let country = profile.country {
            rows.append(ProfileDetailRow(title: "Country", value: country, systemImage: "globe"))
        }
        if let pronouns = profile.pronouns {
            rows.append(ProfileDetailRow(title: "Pronouns", value: pronouns, systemImage: "text.bubble"))
        }
        if let birthday = profile.birthday {
            rows.append(ProfileDetailRow(title: "Birthday", value: birthday, systemImage: "gift"))
        }
        if let lastLogin = profile.lastLogin {
            rows.append(ProfileDetailRow(title: "Last login", value: lastLogin, systemImage: "clock"))
        }
        return rows
    }

    @ViewBuilder
    private func extraFields(_ profile: StudentProfile) -> some View {
        if !profile.extraFields.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("More")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(profile.extraFields, id: \.self) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(field.value)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Text(freshnessLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(model.errorMessage ?? "This profile is not available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await model.load(uwcId: uwcId, kind: kind, fallback: fallback, forceRefresh: true) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var freshnessLabel: String {
        switch model.freshness {
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
            return model.isRefreshing ? "Loading…" : ""
        }
    }

    // MARK: Building blocks

    private func detailRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func wideActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func compactActionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.headline)
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 2)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

}

// MARK: - Detail row

/// One labelled fact on a profile. A struct rather than a tuple so `ForEach` has a real id.
private struct ProfileDetailRow: Identifiable {
    let title: String
    let value: String
    let systemImage: String

    var id: String { title }
}

// MARK: - Photo preview

private struct PersonPhotoPreview: View {
    let name: String
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                W4AvatarView(url: url, name: name, size: 300)
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}
