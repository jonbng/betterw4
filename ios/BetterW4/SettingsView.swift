//
//  SettingsView.swift
//  BetterW4
//
//  Settings ▸ Appearance · Notifications · Data · Privacy · About · Sign out (features.md §6).
//
//  Every preference here is device-local and survives "Clear cache" on purpose: clearing data is
//  not the same as resetting the app (features.md §3 rule 10).
//

import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    let student: Student?
    /// Optional so the previews can render without a session. Only used for Sign out.
    var authViewModel: AuthenticationViewModel? = nil

    @StateObject private var settingsStore = SettingsStore.shared
    @State private var showClearCacheAlert = false
    @State private var showSignOutAlert = false
    @State private var subjectTitles: [String] = []
    @State private var hasStoredSession = false
    @State private var cacheSize: Int64?
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    private var currentStudentId: String? {
        student?.studentId ?? KeychainManager.shared.loadStudent()?.studentId
    }

    private var isDemo: Bool { student?.isDemo ?? false }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        List {
            appearanceSection
            notificationsSection
            dataSection
            privacySection
            aboutSection
            signOutSection
        }
        .navigationTitle("Settings")
        .task(id: student?.studentId) {
            hasStoredSession = loadSessionPresence()
            await refreshNotificationAuthorization()
            await refreshCacheSize()
            await loadSubjectTitles()
        }
        .alert("Clear cache?", isPresented: $showClearCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                settingsStore.clearAllCaches()
                Task { await refreshCacheSize() }
            }
        } message: {
            Text("This deletes the W4 pages saved on this device. You stay signed in, and your settings are kept.")
        }
        .alert("Log out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log out", role: .destructive) {
                Task { await authViewModel?.logout() }
            }
        } message: {
            Text("Your saved W4 data on this device is removed. You can log in again at any time.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $settingsStore.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settingsStore.appearanceMode) { _, newValue in
                settingsStore.saveAppearanceMode(newValue)
            }

            Picker("Calendar style", selection: $settingsStore.calendarStyle) {
                ForEach(CalendarStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.displayName)
                        Text(style.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.inline)
            .onChange(of: settingsStore.calendarStyle) { _, newValue in
                settingsStore.saveCalendarStyle(newValue)
            }

            Toggle(isOn: $settingsStore.useSubjectColors) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subject colours")
                    Text("Give every subject its own colour. When this is off, lessons are blue when normal, green when changed and red when cancelled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: settingsStore.useSubjectColors) { _, newValue in
                settingsStore.saveUseSubjectColors(newValue)
            }

            Toggle(isOn: $settingsStore.showSchoolCalendar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("School calendar")
                    Text("Show college events from the public school Google Calendar on the timetable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: settingsStore.showSchoolCalendar) { _, newValue in
                settingsStore.saveShowSchoolCalendar(newValue)
            }

            NavigationLink {
                SubjectSettingsView(student: student, eventTitles: subjectTitles)
            } label: {
                Label("Subjects", systemImage: "paintpalette")
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Change how the timetable looks, and rename or recolour your subjects.")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Allow notifications", isOn: $settingsStore.notificationsEnabled)
                .onChange(of: settingsStore.notificationsEnabled) { _, newValue in
                    settingsStore.saveNotificationsEnabled(newValue)
                    if newValue {
                        requestNotificationPermission()
                    } else {
                        NotificationBackgroundRefresh.cancel()
                    }
                }

            if settingsStore.notificationsEnabled {
                Toggle("Timetable changes", isOn: $settingsStore.notifyTimetableChanges)
                    .onChange(of: settingsStore.notifyTimetableChanges) { _, value in
                        settingsStore.saveNotifyTimetableChanges(value)
                    }

                Toggle("Assessments", isOn: $settingsStore.notifyAssessments)
                    .onChange(of: settingsStore.notifyAssessments) { _, value in
                        settingsStore.saveNotifyAssessments(value)
                    }

                Toggle("Trips", isOn: $settingsStore.notifyTrips)
                    .onChange(of: settingsStore.notifyTrips) { _, value in
                        settingsStore.saveNotifyTrips(value)
                    }
            }

            LabeledContent("System permission") {
                Text(notificationAuthorizationLabel)
                    .foregroundStyle(.secondary)
            }

            if notificationAuthorization == .denied {
                Button("Open Settings") {
                    openSystemSettings()
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("BetterW4 checks W4 in the background while Background App Refresh is on, and notifies you on this device only. Mail is your Gmail — it is not notified here.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            LabeledContent("Session") {
                Text(sessionLabel)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Storage used") {
                Text(cacheSizeLabel)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                showClearCacheAlert = true
            } label: {
                Label("Clear cache", systemImage: "trash")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Clearing the cache deletes the W4 pages saved on this device. It does not log you out.")
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyDetailView()
            } label: {
                Label("What BetterW4 stores", systemImage: "hand.raised")
            }
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("App") {
                Text("BetterW4").foregroundStyle(.secondary)
            }
            LabeledContent("Version") {
                Text("\(appVersion) (\(buildNumber))").foregroundStyle(.secondary)
            }
            LabeledContent("School") {
                Text("UWC Red Cross Nordic").foregroundStyle(.secondary)
            }
            LabeledContent("Server") {
                Text(W4Routes.host).foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        } footer: {
            Text("BetterW4 is an unofficial client for W4. It is not made by UWC Red Cross Nordic.")
        }
    }

    // MARK: - Sign out

    @ViewBuilder
    private var signOutSection: some View {
        if authViewModel != nil {
            Section {
                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Labels

    private var sessionLabel: String {
        if isDemo { return "Demo" }
        return hasStoredSession ? "Signed in" : "None"
    }

    private var cacheSizeLabel: String {
        guard let cacheSize else { return "…" }
        return ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    private var notificationAuthorizationLabel: String {
        switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Actions

    /// Read-only: whether a W4 session cookie is stored for this student. The value itself is
    /// never shown and never editable.
    private func loadSessionPresence() -> Bool {
        guard
            let studentId = currentStudentId,
            let credentials = KeychainManager.shared.loadCredentials(for: studentId)
        else {
            return false
        }
        return !credentials.isEmpty
    }

    /// The subjects the Subjects screen offers to rename. Sourced from the cached timetable week
    /// through the repository — never from a parser, and never from the network.
    private func loadSubjectTitles() async {
        guard student != nil else {
            subjectTitles = []
            return
        }
        guard let week = await TimetableRepository.shared.cachedWeek(containing: TimeProvider.now) else {
            subjectTitles = []
            return
        }
        guard !Task.isCancelled else { return }
        let titles = week.value.days.flatMap { $0.events.map(\.title) }
        subjectTitles = Array(Set(titles)).sorted()
    }

    private func refreshCacheSize() async {
        let size = await SettingsStore.cacheSizeInBytes()
        guard !Task.isCancelled else { return }
        cacheSize = size
    }

    private func refreshNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard !Task.isCancelled else { return }
        notificationAuthorization = settings.authorizationStatus
    }

    /// Permission is asked for lazily, the first time the student turns notifications on —
    /// never at launch (features.md §5.2).
    private func requestNotificationPermission() {
        Task {
            await NotificationRefresh.requestAuthorizationIfNeeded()
            await refreshNotificationAuthorization()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Privacy detail

/// A static, English statement of everything the app keeps. There is no external privacy URL to
/// link to yet, so the text lives in the app where it can never rot away behind a dead link.
struct PrivacyDetailView: View {
    var body: some View {
        List {
            Section {
                Text("BetterW4 has no servers and no account of its own. Everything it knows lives on this device.")
            }

            Section("On this device") {
                privacyRow(
                    icon: "key.fill",
                    title: "Your W4 session",
                    detail: "The W4 session cookie and a device identifier are stored in the iOS Keychain. Your password is never saved."
                )
                privacyRow(
                    icon: "internaldrive",
                    title: "Cached W4 pages",
                    detail: "Timetable, mail, assessments, attendance and directory pages are cached so the app works offline. Clear cache removes all of it."
                )
                privacyRow(
                    icon: "slider.horizontal.3",
                    title: "Your settings",
                    detail: "Theme, calendar style, subject names and colours, and notification choices."
                )
            }

            Section("Never") {
                privacyRow(
                    icon: "chart.bar.xaxis",
                    title: "No analytics",
                    detail: "No tracking, no crash reporting to a third party, no advertising identifiers."
                )
                privacyRow(
                    icon: "network.slash",
                    title: "No third parties",
                    detail: "The app talks to \(W4Routes.host). If you turn on the school calendar, it also fetches the public college calendar from Google. Your data is never uploaded anywhere."
                )
            }

            Section {
                Text("Logging out removes the session and every cached page for that account, so the next person to use this device cannot read them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("What BetterW4 stores")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView(student: nil)
    }
}

#Preview("Privacy") {
    NavigationStack {
        PrivacyDetailView()
    }
}
