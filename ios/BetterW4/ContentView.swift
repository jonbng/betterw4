//
//  ContentView.swift
//  BetterW4
//
//  The app shell: the three-state root (loading → login → tabs), the four-tab bar, and the More
//  root that reaches every remaining W4 surface (ui.md §2.1, §4.6).
//
//  Four tabs, and no more (ui.md §1.1):
//
//    Timetable — `ScheduleView`      AC + EA lessons, merged
//    Students  — `StudentSearchView` people directory (the thing people actually open)
//    Absence   — `AbsenceView`       AC + EA attendance meters and registrations
//    More      — `MoreView`          everything else, including assessments and the unused W4 mailer
//
//  Every tab owns a `NavigationStack`. Students and More bind a `NavigationPath`, because the
//  directory pushes people onto it from inside.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var authViewModel = AuthenticationViewModel()
    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                LoadingView()

            case .unauthenticated:
                LoginView(viewModel: authViewModel)

            case .authenticated(let student):
                AuthenticatedTabShell(student: student, authViewModel: authViewModel)
                    .task {
                        await NotificationRefresh.requestAuthorizationIfNeeded()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        NotificationBackgroundRefresh.schedule()
                    }
            }
        }
        .preferredColorScheme(settingsStore.preferredColorScheme)
    }
}

// MARK: - Tab order

/// The tab bar's indices, in one place.
///
/// `TabBarSameTabReselectDetector` works off `UITabBarController.selectedIndex`, so any screen
/// that wants "tap the selected tab to scroll to top" needs the same numbers the `TabView` uses.
enum AuthenticatedTabIndex {
    static let timetable = 0
    static let students = 1
    /// Attendance is the daily check; assessments live under More.
    static let absences = 2
    static let more = 3
}

// MARK: - Authenticated Tab Shell

private enum AuthenticatedSheet: Identifiable {
    case review

    var id: String {
        switch self {
        case .review: "review"
        }
    }
}

private struct AuthenticatedTabShell: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @ObservedObject private var settingsStore = SettingsStore.shared
    @State private var selectedTab = AuthenticatedTabIndex.timetable
    @State private var studentsNavigationPath = NavigationPath()
    @State private var moreNavigationPath = NavigationPath()
    @ObservedObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScheduleView(student: student)
            }
            .tabItem {
                Label("Timetable", systemImage: "calendar")
            }
            .tag(AuthenticatedTabIndex.timetable)

            NavigationStack(path: $studentsNavigationPath) {
                StudentSearchView(
                    student: student,
                    authViewModel: authViewModel,
                    navigationPath: $studentsNavigationPath,
                    presentation: .full
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        CampusStatusControl()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NotificationsBellButton()
                    }
                }
            }
            .tabItem {
                Label("Students", systemImage: "person.2.fill")
            }
            .tag(AuthenticatedTabIndex.students)
            .background {
                TabBarSameTabReselectDetector(tabIndex: AuthenticatedTabIndex.students) {
                    if !studentsNavigationPath.isEmpty {
                        studentsNavigationPath = NavigationPath()
                    }
                }
            }

            NavigationStack {
                AbsenceView(student: student)
            }
            .tabItem {
                Label("Absence", systemImage: "exclamationmark.circle")
            }
            .tag(AuthenticatedTabIndex.absences)

            NavigationStack(path: $moreNavigationPath) {
                MoreView(
                    student: student,
                    authViewModel: authViewModel,
                    navigationPath: $moreNavigationPath
                )
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
            .tag(AuthenticatedTabIndex.more)
        }
        .onAppear {
            reviewPromptCoordinator.onAuthenticatedLaunch(student: student)
            MessageListPrefetcher.schedulePrefetch(for: student)
        }
        .task(id: student.id) {
            settingsStore.activateScope(studentId: student.studentId)
            CustomEventsStore.shared.activate(studentId: student.studentId)
        }
        .onChange(of: selectedTab) { _, newValue in
            // Mail now lives under More; warm the inbox when that tab is about to be used.
            if newValue == AuthenticatedTabIndex.more {
                MessageListPrefetcher.schedulePrefetch(for: student)
            }
        }
        .sheet(item: authenticatedSheet) { sheet in
            switch sheet {
            case .review:
                ReviewPromptSheet(
                    onPositive: { reviewPromptCoordinator.onPositive() },
                    onNegative: { reviewPromptCoordinator.onNegative() },
                    onDismiss: { reviewPromptCoordinator.onDismissed() }
                )
            }
        }
    }

    private var authenticatedSheet: Binding<AuthenticatedSheet?> {
        Binding(
            get: {
                if reviewPromptCoordinator.softPromptVisible {
                    return .review
                }
                return nil
            },
            set: { value in
                guard case nil = value else { return }
                if reviewPromptCoordinator.softPromptVisible {
                    reviewPromptCoordinator.onDismissed()
                }
            }
        )
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - More View

/// The More root. Every W4 surface that is not one of the three content tabs is reachable from
/// here (including the W4 mailer), grouped the way W4's own side menus group them (ui.md §4.6).
struct MoreView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @Binding var navigationPath: NavigationPath

    @State private var profile: DirectoryPersonProfile?
    @State private var showLogOutAlert = false

    var body: some View {
        List {
            headerSection

            if student.isDemo {
                demoSection
            }

            Section {
                row("Home", systemImage: "house") { HomeView(student: student) }
                row("Notifications", systemImage: "bell") { NotificationsView() }
                if MailFeatureFlags.visible {
                    row("Mail", systemImage: "envelope") { MessagesView(student: student) }
                }
                row("Houses", systemImage: "building.2") { HousesView() }
            } header: {
                Text("School")
            }

            Section {
                row("Assessments", systemImage: "checklist") { AssessmentsView(student: student) }
                row("Grades", systemImage: "chart.bar.doc.horizontal") { GradesView(student: student) }
                row("My classes", systemImage: "books.vertical") { MyClassesView() }
                row("My teachers", systemImage: "person.3") { MyTeachersView() }
                row("Extra Academics", systemImage: "figure.outdoor.cycle") { ExtraAcademicsView() }
            } header: {
                Text("Academics")
            }

            Section {
                directoryRow("Teachers", systemImage: "person.text.rectangle.fill", presentation: .teachers)
                row("On duty", systemImage: "person.badge.shield.checkmark") { OnDutyView() }
                row("Birthdays", systemImage: "birthday.cake") { BirthdaysView() }
            } header: {
                Text("People")
            }

            Section {
                row("Trips and travel", systemImage: "airplane") { TripsView() }
                row("Documents", systemImage: "folder") { DocumentsView() }
            } header: {
                Text("Boarding")
            }

            Section {
                // Also reachable by tapping the header card; kept as a row because that is where
                // people look for it.
                row("ID card", systemImage: "person.text.rectangle") {
                    StudentCardView(student: student)
                }
                row("Settings", systemImage: "gear") {
                    SettingsView(student: student, authViewModel: authViewModel)
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogOutAlert = true
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listSectionSpacing(14)
        .navigationTitle("More")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CampusStatusControl()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NotificationsBellButton()
            }
        }
        .alert("Log out?", isPresented: $showLogOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log out", role: .destructive) {
                Task { await authViewModel.logout() }
            }
        } message: {
            Text("Your saved W4 data on this device is removed. You can log in again at any time.")
        }
        .refreshable {
            await loadProfile(forceRefresh: true)
        }
        .task(id: student.id) {
            await loadProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
            Task { await loadProfile() }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            NavigationLink {
                StudentCardView(student: student)
            } label: {
                HStack(spacing: 16) {
                    W4AvatarView(url: portraitURL, name: displayName, size: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var demoSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DemoDataProvider.bannerText)
                        .font(.subheadline.weight(.semibold))
                    Text("Everything you see is sample data stored on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Rows

    private func row<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func directoryRow(
        _ title: String,
        systemImage: String,
        presentation: DirectoryPresentation
    ) -> some View {
        NavigationLink {
            StudentSearchView(
                student: student,
                authViewModel: authViewModel,
                navigationPath: $navigationPath,
                presentation: presentation
            )
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    // MARK: Identity

    /// The name W4 knows this student by, falling back to whatever the session stored.
    private var displayName: String {
        if let profile {
            let name = profile.person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name.caseInsensitiveCompare(profile.uwcId) != .orderedSame {
                return name
            }
        }
        let stored = student.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "Student" : stored
    }

    /// `nc26abcd · Year 2 · Haugland` — whichever parts W4 actually gave us.
    private var subtitle: String {
        guard let profile else {
            return student.isDemo ? "Demo session" : ""
        }
        var parts: [String] = [profile.uwcId]
        if let year = profile.person.year, !year.isEmpty { parts.append("Year \(year)") }
        if let house = profile.person.house, !house.isEmpty { parts.append(house) }
        return parts.joined(separator: " · ")
    }

    /// Demo never has a portrait URL: `W4ImageLoader` refuses the network in demo mode anyway,
    /// and handing it a URL it will not fetch just makes the intent harder to read.
    private var portraitURL: URL? {
        guard !student.isDemo else { return nil }
        guard let profile else { return nil }
        return profile.person.photoURL ?? W4PeopleParser.photoURL(forUWCId: profile.uwcId)
    }

    /// Cache-first: the stored profile paints immediately, then W4 refreshes underneath. A failed
    /// refresh leaves whatever is on screen alone — never wipe a good header on a transient error.
    private func loadProfile(forceRefresh: Bool = false) async {
        if profile == nil,
           let cached = await ProfileRepository.shared.cachedProfile(uwcId: currentUWCId) {
            guard !Task.isCancelled else { return }
            profile = cached.value
        }
        // `.opportunistic`: the header is decoration, and it must never queue in front of the
        // screen the student actually opened (features.md §3 rule 12). A failed refresh keeps
        // whatever is already on screen — never wipe a good header on a transient error.
        let refreshed = try? await ProfileRepository.shared.myProfile(
            forceRefresh: forceRefresh,
            priority: forceRefresh ? .important : .opportunistic
        )
        guard let refreshed, !Task.isCancelled else { return }
        profile = refreshed.value
    }

    /// In demo mode the session's student id is a sentinel, not a UWC id, so the demo roster's id
    /// is used instead — that is the person every demo screen shows.
    private var currentUWCId: String {
        student.isDemo ? DemoDataProvider.uwcId : student.studentId
    }
}

// MARK: - Previews

#Preview("ContentView") {
    ContentView()
}

#Preview("More") {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        MoreView(
            student: Student.demo,
            authViewModel: AuthenticationViewModel(),
            navigationPath: $path
        )
    }
}
