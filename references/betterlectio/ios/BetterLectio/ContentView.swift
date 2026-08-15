//
//  ContentView.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 02/02/2026.
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authViewModel = AuthenticationViewModel()
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var referralCoordinator = ReferralCoordinator.shared
    @ObservedObject private var profilePictureReviewMonitor = ProfilePictureReviewMonitor.shared

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                LoadingView()

            case .unauthenticated:
                LoginView(viewModel: authViewModel)

            case .authenticated(let student):
                AuthenticatedTabShell(student: student, authViewModel: authViewModel)
            }
        }
        .preferredColorScheme(settingsStore.preferredColorScheme)
        .onAppear {
            FeedbackLogBuffer.shared.record("App root appeared")
        }
        .onChange(of: authViewModel.authState) { _, state in
            let label: String
            switch state {
            case .loading: label = "loading"
            case .unauthenticated: label = "unauthenticated"
            case .authenticated(let student): label = student.isDemo ? "demo" : "authenticated"
            }
            if let student = state.student {
                referralCoordinator.activate(for: student)
            } else {
                referralCoordinator.resetSession()
            }
            FeedbackLogBuffer.shared.record("Authentication state=\(label)")
        }
        .onOpenURL { url in
            Task {
                await referralCoordinator.handle(url: url, authenticatedStudent: authViewModel.authState.student)
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            Task {
                await referralCoordinator.handle(url: url, authenticatedStudent: authViewModel.authState.student)
            }
        }
        .task(id: authViewModel.authState.student?.id) {
            if let student = authViewModel.authState.student {
                await referralCoordinator.finalizeIfNeeded(for: student)
                await profilePictureReviewMonitor.refresh(for: student)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let student = authViewModel.authState.student else { return }
            Task { await profilePictureReviewMonitor.refresh(for: student) }
        }
        .alert(
            String(localized: "profile_picture.review_title", defaultValue: "Profilbillede gennemgået"),
            isPresented: Binding(
                get: { profilePictureReviewMonitor.outcomeMessage != nil },
                set: { if !$0 { profilePictureReviewMonitor.resetPresentation() } }
            )
        ) {
            Button(String(localized: "common.ok", defaultValue: "OK")) { profilePictureReviewMonitor.resetPresentation() }
        } message: {
            Text(profilePictureReviewMonitor.outcomeMessage ?? "")
        }
    }
}

// MARK: - Authenticated Tab Shell

private enum AuthenticatedTab: Int, Hashable {
    case schedule = 0
    case messages = 1
    case homework = 2
    case assignments = 3
    case more = 4
}

/// Pushes a focused `StudentSearchView` on the More tab’s single `NavigationPath` (no nested `NavigationStack`).
private enum MoreCatalogRoute: Hashable {
    case focused(DirectoryPresentation)
}

private enum AuthenticatedSheet: Identifiable {
    case feedback(FeedbackPresentation)
    case referral
    case review

    var id: String {
        switch self {
        case .feedback(let presentation): "feedback-\(presentation.id.uuidString)"
        case .referral: "referral"
        case .review: "review"
        }
    }
}

private struct AuthenticatedTabShell: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @ObservedObject private var settingsStore = SettingsStore.shared
    @State private var selectedTab = AuthenticatedTab.schedule.rawValue
    @State private var moreNavigationPath = NavigationPath()
    @State private var unreadMessageCount = 0
    @ObservedObject private var feedbackCoordinator = FeedbackCoordinator.shared
    @ObservedObject private var referralCoordinator = ReferralCoordinator.shared
    @ObservedObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScheduleView(student: student, authViewModel: authViewModel)
            }
            .tabItem {
                Label("Skema", systemImage: "calendar")
            }
            .tag(AuthenticatedTab.schedule.rawValue)

            MessagesTab(student: student, authViewModel: authViewModel)
                .tabItem {
                    Label("Beskeder", systemImage: "envelope.fill")
                }
                .badge(unreadMessageCount)
                .tag(AuthenticatedTab.messages.rawValue)

            NavigationStack {
                HomeworkView(student: student)
            }
            .tabItem {
                Label("Lektier", systemImage: "bookmark.fill")
            }
            .tag(AuthenticatedTab.homework.rawValue)

            NavigationStack {
                AssignmentsView(student: student, authViewModel: authViewModel)
            }
            .tabItem {
                Label("Opgaver", systemImage: "doc.text.fill")
            }
            .tag(AuthenticatedTab.assignments.rawValue)

            NavigationStack(path: $moreNavigationPath) {
                MoreView(student: student, authViewModel: authViewModel, navigationPath: $moreNavigationPath)
                    .navigationDestination(for: MoreCatalogRoute.self) { route in
                        switch route {
                        case .focused(let presentation):
                            StudentSearchView(
                                student: student,
                                authViewModel: authViewModel,
                                navigationPath: $moreNavigationPath,
                                presentation: presentation
                            )
                        }
                    }
            }
            .tabItem {
                Label("Mere", systemImage: "ellipsis.circle")
            }
            .tag(AuthenticatedTab.more.rawValue)
        }
        .onAppear {
            FeedbackLogBuffer.shared.record("Authenticated app appeared")
            reviewPromptCoordinator.onAuthenticatedLaunch(student: student)
            MessageListPrefetcher.schedulePrefetch(for: student)
            readUnreadCountFromCache()
        }
        .task(id: student.id) {
            settingsStore.activateScope(studentId: student.studentId, schoolId: String(student.gymId))
            await settingsStore.syncWithSupabase(studentId: student.studentId, schoolId: String(student.gymId))
        }
        .onChange(of: feedbackCoordinator.presentation != nil) { _, blocking in
            reviewPromptCoordinator.setExternalPromptBlocking("feedback", blocking: blocking)
        }
        .onChange(of: referralCoordinator.nudgeVisible) { _, blocking in
            reviewPromptCoordinator.setExternalPromptBlocking("referral", blocking: blocking)
        }
        .onChange(of: referralCoordinator.celebrationName != nil) { _, blocking in
            reviewPromptCoordinator.setExternalPromptBlocking("celebration", blocking: blocking)
        }
        .onChange(of: selectedTab) { _, newValue in
            FeedbackLogBuffer.shared.record("Selected tab index=\(newValue)")
            if newValue != AuthenticatedTab.messages.rawValue {
                MessageListPrefetcher.schedulePrefetch(for: student)
            }
            readUnreadCountFromCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: .unreadMessageCountDidChange)) { note in
            guard
                let sid = note.userInfo?["studentId"] as? String, sid == student.studentId,
                let count = note.userInfo?["count"] as? Int
            else { return }
            unreadMessageCount = count
        }
        .background {
            ShakeListener {
                guard !referralCoordinator.nudgeVisible,
                      referralCoordinator.celebrationName == nil,
                      !reviewPromptCoordinator.softPromptVisible else { return }
                feedbackCoordinator.present(for: student)
            }
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
        .sheet(item: authenticatedSheet) { sheet in
            switch sheet {
            case .feedback(let presentation):
                FeedbackSheet(presentation: presentation)
            case .referral:
                ReferralNudgeView(student: student)
            case .review:
                ReviewPromptSheet(
                    onPositive: { reviewPromptCoordinator.onPositive() },
                    onNegative: { reviewPromptCoordinator.onNegative() },
                    onDismiss: { reviewPromptCoordinator.onDismissed() }
                )
            }
        }
        .alert(
            "\(referralCoordinator.celebrationName ?? "En klassekammerat") er med takket være dig",
            isPresented: Binding(
                get: { referralCoordinator.celebrationName != nil },
                set: { if !$0 { referralCoordinator.celebrationName = nil } }
            )
        ) {
            Button("Fedt!") { referralCoordinator.celebrationName = nil }
        }
    }

    private func readUnreadCountFromCache() {
        Task {
            unreadMessageCount = await MessageCacheManager.loadThreads(
                studentId: student.studentId,
                folder: .unread
            )?.count ?? 0
        }
    }

    private var authenticatedSheet: Binding<AuthenticatedSheet?> {
        Binding(
            get: {
                if let presentation = feedbackCoordinator.presentation {
                    return .feedback(presentation)
                }
                if referralCoordinator.nudgeVisible {
                    return .referral
                }
                if reviewPromptCoordinator.softPromptVisible {
                    return .review
                }
                return nil
            },
            set: { value in
                guard case nil = value else { return }
                if feedbackCoordinator.presentation != nil {
                    feedbackCoordinator.dismiss()
                } else if referralCoordinator.nudgeVisible {
                    referralCoordinator.dismissNudge(for: student)
                } else if reviewPromptCoordinator.softPromptVisible {
                    reviewPromptCoordinator.onDismissed()
                }
            }
        )
    }
}

// MARK: - Messages Tab

struct MessagesTab: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            MessagesView(
                student: student,
                authViewModel: authViewModel,
                path: $path
            )
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Indlæser…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - More View

struct MoreView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @Binding var navigationPath: NavigationPath
    @State private var studentInfo: (pictureId: String?, classLabel: String?) = (nil, nil)
    @State private var cachedProfileName: String?
    @ObservedObject private var referralCoordinator = ReferralCoordinator.shared
    @State private var profilePictureState: ProfilePictureState?
    @State private var showingProfilePictureEditor = false
    @State private var showingBrowserExtension = false

    var body: some View {
        List {
            // MARK: - Profile Section
            Section {
                HStack(spacing: 16) {
                    // Profile Picture
                    if let imageURL = profilePictureState?.currentImageURL {
                        PublicProfileAvatarView(
                            url: imageURL,
                            name: profileDisplayName,
                            size: 60,
                            lectioFallbackURL: lectioProfileURL
                        )
                    } else if let pictureId = studentInfo.pictureId {
                        let imageURL = URL(string: "https://www.lectio.dk/lectio/\(student.gymId)/GetImage.aspx?pictureid=\(pictureId)&fullsize=1")
                        RateLimitedAvatarImage(url: imageURL, size: 60) {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text(initials)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.blue)
                                )
                        }
                    } else {
                        // Fallback initials
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(initials)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.blue)
                            )
                    }

                    // Name and Class
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileDisplayName)
                            .font(.headline)
                        if let classLabel = studentInfo.classLabel, !classLabel.isEmpty {
                            Text(classLabel)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        showingProfilePictureEditor = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "profile_picture.title", defaultValue: "Skift profilbillede"))
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                Button {
                    navigationPath.append(MoreCatalogRoute.focused(.full))
                } label: {
                    HStack {
                        Label("Elever", systemImage: "person.2.fill")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                NavigationLink {
                    GradesView(student: student)
                } label: {
                    Label("Karakterer", systemImage: "chart.bar.doc.horizontal")
                }
                NavigationLink {
                    AbsenceView(student: student)
                } label: {
                    Label("Fravær", systemImage: "exclamationmark.circle")
                }
            } header: {
                Text("Studie")
            }

            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    // `Button` + path append — `NavigationLink` inside `List` + `LazyVGrid` can eagerly push every destination (SwiftUI quirk).
                    catalogGridLink(.teachers, systemImage: "person.text.rectangle.fill", title: "Lærere")
                    catalogGridLink(.classes, systemImage: "book.closed.fill", title: "Klasser")
                    catalogGridLink(.holds, systemImage: "person.3.fill", title: "Hold")
                    catalogGridLink(.rooms, systemImage: "door.left.hand.closed", title: "Lokaler")
                    catalogGridLink(.groups, systemImage: "person.3.sequence.fill", title: "Grupper")
                    catalogGridLink(.resources, systemImage: "shippingbox.fill", title: "Ressourcer")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // MARK: - Student Card Section
            Section {
                NavigationLink {
                    StudentCardView(student: studentForCard)
                } label: {
                    Label("Studiekort", systemImage: "person.text.rectangle.fill")
                }
            } header: {
                Text("Legitimation")
            }

            Section {
                NavigationLink {
                    ReferralView(student: student)
                        .onAppear { Analytics.capture("referral_screen_opened") }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Inviter venner")
                            if let stats = referralCoordinator.cachedStats(for: student) {
                                let progress = ReferralProgress(conversions: stats.conversions)
                                Text(progress.unlocked
                                     ? "Profilbillede låst op"
                                     : "\(progress.current)/\(progress.target) · Lås profilbillede op")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
                Button {
                    showingBrowserExtension = true
                } label: {
                    Label(String(localized: "browser_extension.navigation_title", defaultValue: "Browser-udvidelse"), systemImage: "puzzlepiece.extension")
                }
                NavigationLink {
                    SettingsView(student: student)
                } label: {
                    Label("Indstillinger", systemImage: "gear")
                }
            }

            Section {
                Button(role: .destructive) {
                    LiveActivityManager.shared.endActivity()
                    Task { await authViewModel.logout() }
                } label: {
                    Label("Log ud", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listSectionSpacing(14)
        .navigationTitle("Mere")
        .task(id: student.id) {
            await loadStudentInfo()
            _ = await referralCoordinator.refreshStats(for: student)
            profilePictureState = student.isDemo
                ? .demo
                : try? await SupabaseProfilePictureService.shared.state(studentID: student.studentId)
        }
        .sheet(isPresented: $showingProfilePictureEditor, onDismiss: {
            Task {
                profilePictureState = student.isDemo
                    ? .demo
                    : try? await SupabaseProfilePictureService.shared.state(studentID: student.studentId)
            }
        }) {
            ProfilePictureEditorView(student: studentForCard)
        }
        .sheet(isPresented: $showingBrowserExtension) {
            BrowserExtensionInviteView(source: .more)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task { await loadStudentInfo() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profilePictureDidChange)) { _ in
            Task {
                profilePictureState = student.isDemo
                    ? .demo
                    : try? await SupabaseProfilePictureService.shared.state(studentID: student.studentId)
            }
        }
    }

    @ViewBuilder
    private func catalogGridLink(_ presentation: DirectoryPresentation, systemImage: String, title: String) -> some View {
        Button {
            navigationPath.append(MoreCatalogRoute.focused(presentation))
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(UIColor.separator).opacity(0.55), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Resolves a real name when auth stored the `StudentParser` placeholder or the header was missing on SkemaNy.
    private var profileDisplayName: String {
        let trimmed = student.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = trimmed.isEmpty || trimmed.caseInsensitiveCompare("Student") == .orderedSame
        if !isPlaceholder { return trimmed }
        if let cachedProfileName {
            let n = cachedProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { return n }
        }
        return "Elev"
    }

    private var initials: String {
        let name = profileDisplayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay(Text(initials).font(.system(size: 20, weight: .medium)).foregroundStyle(.blue))
    }

    private var lectioProfileURL: URL? {
        guard let pictureID = studentInfo.pictureId else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(student.gymId)/GetImage.aspx?pictureid=\(pictureID)&fullsize=1")
    }

    private func loadStudentInfo() async {
        let store = DirectoryStore.shared
        guard let info = await store.loadStudentInfoAsync(for: student.studentId, gymId: student.gymId) else {
            studentInfo = (nil, nil)
            cachedProfileName = nil
            return
        }
        guard !Task.isCancelled else { return }
        studentInfo = (info.pictureId, info.classLabel)
        cachedProfileName = info.name
    }

    /// Student enriched with `pictureId`/`classLabel` from `DirectoryStore` — the keychain-stored
    /// `Student` never carries these fields, so the card needs them merged in at the call site.
    private var studentForCard: Student {
        var enriched = student
        enriched.pictureId = studentInfo.pictureId
        enriched.classLabel = studentInfo.classLabel
        return enriched
    }
}

#Preview("ContentView") {
    ContentView()
}

/// Canvas: select this preview in the picker next to Resume, or split the canvas to compare with `ContentView`.
#Preview("Mere") {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        MoreView(
            student: Student(
                studentId: "preview",
                gymId: 9,
                name: "Preview Student",
                pictureId: nil,
                classLabel: "3a",
                schoolName: nil
            ),
            authViewModel: AuthenticationViewModel(),
            navigationPath: $path
        )
    }
}
