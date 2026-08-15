//
//  StudentProfileView.swift
//  BetterLectio
//

import SwiftUI

private enum RichProfileState: Equatable {
    case loading
    case available
    case inactive
    case missing
    case unavailable(String)
}

struct StudentProfileView: View {
    let entity: DirectoryEntity
    let authenticatedStudent: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @ObservedObject var directoryViewModel: DirectoryViewModel
    let lectioImageURL: URL?
    let onOpenClass: (DirectoryEntity) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var profile: StudentProfile?
    @State private var profileState: RichProfileState = .loading
    @State private var resolvedLectioImageURL: URL?
    @State private var showingComposer = false
    @State private var showingImagePreview = false
    @State private var descriptionExpanded = false

    private var activeProfile: StudentProfile? {
        profileState == .available ? profile : nil
    }

    private var displayName: String {
        activeProfile?.displayName(fallback: entity.name) ?? entity.name
    }

    private var classLabel: String? {
        nonEmpty(activeProfile?.className) ?? nonEmpty(entity.classCode) ?? nonEmpty(entity.displaySubtitle)
    }

    private var publicProfileImageURL: URL? {
        activeProfile?.pictureURL(fallback: nil)
    }

    private var scheduleTarget: SchedulableTarget? {
        guard let target = entity.schedulableTarget else { return nil }
        return SchedulableTarget(
            kind: target.kind,
            id: target.id,
            displayName: displayName,
            gymId: target.gymId
        )
    }

    private var classEntity: DirectoryEntity? {
        guard let classLabel else { return nil }
        return directoryViewModel.classes.first {
            $0.classCode?.caseInsensitiveCompare(classLabel) == .orderedSame
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                actionRow
                profileDetails
                scheduleCard
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "student_profile.title", defaultValue: "Profil"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadProfile(forceRefresh: true)
        }
        .task(id: entity.id) {
            descriptionExpanded = false
            resolvedLectioImageURL = lectioImageURL ?? DirectoryStore.shared.pictureURL(for: entity)
            if resolvedLectioImageURL == nil {
                await DirectoryStore.shared.fetchPictureIDIfNeeded(
                    for: entity,
                    authenticatedStudentID: authenticatedStudent.studentId
                )
                resolvedLectioImageURL = DirectoryStore.shared.pictureURL(for: entity)
            }
        }
        .task(id: entity.numericID) {
            await loadProfile(forceRefresh: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task { await loadProfile(forceRefresh: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profilePictureDidChange)) { _ in
            Task { await loadProfile(forceRefresh: true) }
        }
        .sheet(isPresented: $showingComposer) {
            ComposeMessageView(
                student: authenticatedStudent,
                authViewModel: authViewModel,
                initialRecipients: entity.asMessageRecipient().map { [$0] } ?? []
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingImagePreview) {
            ProfileImagePreview(
                name: displayName,
                publicURL: publicProfileImageURL,
                lectioURL: resolvedLectioImageURL
            )
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Button {
                showingImagePreview = publicProfileImageURL != nil || resolvedLectioImageURL != nil
            } label: {
                profileAvatar
            }
            .buttonStyle(.plain)
            .disabled(publicProfileImageURL == nil && resolvedLectioImageURL == nil)
            .accessibilityLabel(
                String(localized: "student_profile.photo", defaultValue: "Profilbillede for \(displayName)")
            )
            .accessibilityHint(
                String(localized: "student_profile.photo_hint", defaultValue: "Åbner billedet i stor størrelse")
            )

            VStack(spacing: 5) {
                Text(displayName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)

                if let classLabel {
                    Text(classLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    profileBadge(
                        String(localized: "student_profile.student_badge", defaultValue: "Elev"),
                        systemImage: "person.fill",
                        color: .blue
                    )
                    profileStatusBadge
                }
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: profileState)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let publicProfileImageURL {
            PublicProfileAvatarView(
                url: publicProfileImageURL,
                name: displayName,
                size: 108,
                lectioFallbackURL: resolvedLectioImageURL
            )
                .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3))
        } else {
            LectioAvatarView(url: resolvedLectioImageURL, name: displayName, size: 108)
                .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3))
        }
    }

    @ViewBuilder
    private var profileStatusBadge: some View {
        switch profileState {
        case .loading:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(String(localized: "student_profile.loading", defaultValue: "Henter profil"))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
        case .available:
            profileBadge("BetterLectio", systemImage: "checkmark.seal.fill", color: .purple)
        case .inactive, .missing, .unavailable:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                wideAction(
                    String(localized: "student_profile.write", defaultValue: "Skriv besked"),
                    systemImage: "square.and.pencil",
                    prominent: true
                ) { showingComposer = true }
                wideAction(pinTitle, systemImage: pinIcon) { togglePin() }
                if let classEntity {
                    wideAction(
                        String(localized: "student_profile.class", defaultValue: "Se klasse"),
                        systemImage: "person.2.fill",
                        action: { onOpenClass(classEntity) }
                    )
                }
            }
        } else {
            HStack(spacing: 10) {
                profileAction(pinTitle, systemImage: pinIcon) { togglePin() }
                profileAction(
                    String(localized: "student_profile.write_short", defaultValue: "Skriv"),
                    systemImage: "square.and.pencil",
                    prominent: true
                ) { showingComposer = true }
                if let classEntity {
                    profileAction(
                        String(localized: "student_profile.class_short", defaultValue: "Klasse"),
                        systemImage: "person.2.fill",
                        action: { onOpenClass(classEntity) }
                    )
                }
            }
        }
    }

    private var pinTitle: String {
        directoryViewModel.isPinned(entity)
            ? String(localized: "student_profile.unpin", defaultValue: "Frigør")
            : String(localized: "student_profile.pin", defaultValue: "Fastgør")
    }

    private var pinIcon: String {
        directoryViewModel.isPinned(entity) ? "pin.slash.fill" : "pin.fill"
    }

    @ViewBuilder
    private var profileDetails: some View {
        switch profileState {
        case .available:
            richDetails
        case .inactive:
            statusCard(
                String(localized: "student_profile.inactive", defaultValue: "Denne BetterLectio-profil er ikke aktiv længere."),
                systemImage: "person.crop.circle.badge.clock"
            )
        case .missing:
            statusCard(
                String(localized: "student_profile.missing", defaultValue: "Denne elev har ikke en BetterLectio-profil endnu."),
                systemImage: "person.crop.circle.badge.questionmark"
            )
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 12) {
                statusCard(message, systemImage: "wifi.exclamationmark")
                Button {
                    Task { await loadProfile(forceRefresh: true) }
                } label: {
                    Label(
                        String(localized: "student_profile.retry", defaultValue: "Prøv igen"),
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .loading:
            EmptyView()
        }
    }

    @ViewBuilder
    private var richDetails: some View {
        if let activeProfile {
            let description = nonEmpty(activeProfile.profileDescription)
            let birthday = activeProfile.formattedBirthday
            let instagramText = InstagramProfileLink.displayText(for: activeProfile.instagram)
            let instagramURL = InstagramProfileLink.url(for: activeProfile.instagram)

            if description != nil || birthday != nil || instagramText != nil {
                VStack(alignment: .leading, spacing: 14) {
                    if let description {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(description)
                                .font(.body)
                                .lineLimit(descriptionExpanded ? nil : 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if description.count > 220 {
                                Button(descriptionExpanded
                                    ? String(localized: "student_profile.show_less", defaultValue: "Vis mindre")
                                    : String(localized: "student_profile.show_more", defaultValue: "Vis mere")) {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        descriptionExpanded.toggle()
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }

                    if description != nil && (birthday != nil || instagramText != nil) { Divider() }

                    if let birthday {
                        detailRow(
                            String(localized: "student_profile.birthday", defaultValue: "Fødselsdag"),
                            value: birthday,
                            systemImage: "birthday.cake.fill"
                        )
                    }

                    if let instagramText, let instagramURL {
                        Link(destination: instagramURL) {
                            detailRow("Instagram", value: instagramText, systemImage: "link", showsExternalLink: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var scheduleCard: some View {
        if let scheduleTarget {
            NavigationLink {
                ScheduleView(
                    authenticatedStudent: authenticatedStudent,
                    authViewModel: authViewModel,
                    target: scheduleTarget,
                    targetImageURL: resolvedLectioImageURL,
                    targetPublicImageURL: publicProfileImageURL
                )
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "student_profile.schedule", defaultValue: "Se skema"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(
                            String(
                                localized: "student_profile.schedule_description",
                                defaultValue: "Åbn \(displayName)s skema"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func loadProfile(forceRefresh: Bool) async {
        if authenticatedStudent.isDemo {
            profile = StudentProfile(
                id: entity.numericID,
                name: entity.name,
                profileDescription: String(
                    localized: "student_profile.demo_bio",
                    defaultValue: "Her kan en elev fortælle lidt om sig selv."
                ),
                birthdate: "2008-05-12",
                showBirthday: true,
                className: entity.classCode,
                appInstalledAt: "2026-01-01T00:00:00Z"
            )
            profileState = .available
            return
        }
        if !forceRefresh { profileState = .loading }

        do {
            let fetched = try await SupabaseStudentProfileService.shared.profile(
                studentID: entity.numericID,
                viewer: authenticatedStudent,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            let newState: RichProfileState
            if let fetched {
                newState = fetched.hasBetterLectio ? .available : .inactive
            } else {
                newState = .missing
            }
            applyLoadedProfile(fetched, state: newState)
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? StudentProfileServiceError)?.errorDescription
                ?? String(localized: "student_profile.unavailable", defaultValue: "Profilen kunne ikke hentes lige nu.")
            applyLoadedProfile(nil, state: .unavailable(message))
        }
    }

    private func applyLoadedProfile(_ profile: StudentProfile?, state: RichProfileState) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            self.profile = profile
            profileState = state
        }
    }

    private func togglePin() {
        directoryViewModel.togglePin(for: entity, currentStudentID: authenticatedStudent.studentId)
    }

    private func profileBadge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func profileAction(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.headline)
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.vertical, 2)
            .background(prominent ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func wideAction(
        _ title: String,
        systemImage: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 16)
                .background(prominent ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func detailRow(
        _ title: String,
        value: String,
        systemImage: String,
        showsExternalLink: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            }
            Spacer()
            if showsExternalLink {
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func statusCard(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private struct ProfileImagePreview: View {
    let name: String
    let publicURL: URL?
    let lectioURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let publicURL {
                    PublicProfileAvatarView(
                        url: publicURL,
                        name: name,
                        size: 300,
                        lectioFallbackURL: lectioURL
                    )
                } else {
                    LectioAvatarView(url: lectioURL, name: name, size: 300)
                }
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
                    .accessibilityLabel(String(localized: "common.close", defaultValue: "Luk"))
                }
            }
        }
    }
}
