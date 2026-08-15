//
//  SettingsView.swift
//  BetterLectio
//
//  Created by Kilo Code on 04/03/2026.
//

import SwiftUI

struct SettingsView: View {
    let student: Student?
    @StateObject private var settingsStore = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearCacheAlert = false
    @State private var showSessionCookieDeletedAlert = false
    @State private var showSetASPSessionIdAlert = false
    @State private var showSessionCookieSetAlert = false
    @State private var aspSessionIdDraft = ""
    @State private var showSetAutologinkeyV2Alert = false
    @State private var showAutologinkeyV2SetAlert = false
    @State private var autologinkeyV2Draft = ""
    @State private var scheduleEventTitles: [String] = []
    @State private var showingBrowserExtension = false

    private var currentStudentId: String? {
        student?.studentId ?? KeychainManager.shared.loadStudent()?.studentId
    }

    // App version info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Ukendt"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Ukendt"
    }

    var body: some View {
        List {
            // MARK: - Appearance Section
            Section {
                Picker("Tema", selection: $settingsStore.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settingsStore.appearanceMode) { _, newValue in
                    settingsStore.saveAppearanceMode(newValue)
                }

                Picker("Kalenderstil", selection: $settingsStore.calendarStyle) {
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
                        Text("Fagfarver")
                        Text("Vis unikke farver for hvert fag. Når slået fra vises blå for normale, grøn for ændrede og rød for aflyste lektioner")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settingsStore.useSubjectColors) { _, newValue in
                    settingsStore.saveUseSubjectColors(newValue)
                }

                NavigationLink {
                    SubjectSettingsView(student: student, eventTitles: scheduleEventTitles)
                } label: {
                    Label("Fagindstillinger", systemImage: "paintpalette")
                }
            } header: {
                Text("Udseende")
            } footer: {
                Text("Tilpas kalenderens udseende, fagnavne og farver.")
            }

            // MARK: - Live Activity Section
            Section {
                Picker("Variant", selection: $settingsStore.liveActivityVariant) {
                    ForEach(LiveActivityVariant.allCases) { variant in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(variant.displayName)
                            Text(variant.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(variant)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: settingsStore.liveActivityVariant) { _, newValue in
                    settingsStore.saveLiveActivityVariant(newValue)
                    // Restart with new variant on next timer tick
                    LiveActivityManager.shared.endActivity()
                }

                if student != nil {
                    Button {
                        testLiveActivity()
                    } label: {
                        Label("Test live-aktivitet", systemImage: "play.circle")
                    }
                }
            } header: {
                Text("Live-aktivitet")
            } footer: {
                Text("Vælg hvor meget info der vises på låseskærmen under lektioner.")
            }

            // MARK: - Notifications Section
            Section {
                Toggle("Aktiver notifikationer", isOn: $settingsStore.notificationsEnabled)
                    .onChange(of: settingsStore.notificationsEnabled) { _, newValue in
                        settingsStore.saveNotificationsEnabled(newValue)
                        if newValue {
                            requestNotificationPermission()
                        }
                    }
            } header: {
                Text("Notifikationer")
            } footer: {
                Text("Modtag påmindelser om kommende lektioner og ændringer i skemaet.")
            }

            // MARK: - Messages Section
            Section {
                Toggle("Tilføj BetterLectio-signatur", isOn: $settingsStore.messageSignatureEnabled)
                    .onChange(of: settingsStore.messageSignatureEnabled) { _, newValue in
                        settingsStore.saveMessageSignatureEnabled(newValue)
                    }
            } header: {
                Text("Beskeder")
            } footer: {
                Text("Tilføjer et link til BetterLectio nederst i beskeder til elever. Signaturen tilføjes ikke i beskeder til lærere.")
            }

            // MARK: - Feedback Section
            Section {
                Button {
                    showingBrowserExtension = true
                } label: {
                    Label(String(localized: "browser_extension.navigation_title", defaultValue: "Browser-udvidelse"), systemImage: "puzzlepiece.extension")
                }

                Button {
                    if let student {
                        FeedbackCoordinator.shared.present(for: student)
                    }
                } label: {
                    Label("Send feedback", systemImage: "exclamationmark.bubble")
                }
                .disabled(student == nil)
            } header: {
                Text(String(localized: "settings.app_section", defaultValue: "BetterLectio"))
            } footer: {
                Text("Du kan også ryste telefonen for at åbne feedback fra andre steder i appen.")
            }

            // MARK: - Data Section
            Section {
                Button(role: .destructive) {
                    showClearCacheAlert = true
                } label: {
                    Label("Ryd cache", systemImage: "trash")
                }

                Button {
                    Task {
                        await CookieManager.shared.clearASPNETSessionIdEverywhere(forStudentId: currentStudentId)
                        showSessionCookieDeletedAlert = true
                    }
                } label: {
                    Label("Slet ASP.NET_SessionId-cookie", systemImage: "xmark.circle")
                }

                Button {
                    if let studentId = currentStudentId, let creds = KeychainManager.shared.loadCredentials(for: studentId) {
                        aspSessionIdDraft = creds.sessionId
                    } else {
                        aspSessionIdDraft = ""
                    }
                    showSetASPSessionIdAlert = true
                } label: {
                    Label("Opdater ASP.NET_SessionId …", systemImage: "pencil")
                }

                Button {
                    if let studentId = currentStudentId, let creds = KeychainManager.shared.loadCredentials(for: studentId) {
                        autologinkeyV2Draft = creds.autologinkey
                    } else {
                        autologinkeyV2Draft = ""
                    }
                    showSetAutologinkeyV2Alert = true
                } label: {
                    Label("Opdater autologinkeyV2 …", systemImage: "pencil")
                }

                Button {
                    CookieManager.shared.logKeychainLectioCookies(forStudentId: currentStudentId)
                } label: {
                    Label("Log cookies (nøglering)", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Slet lokalt cachede data. Dette vil ikke logge dig ud. ASP.NET_SessionId fjernes i WebKit og i gemte loginoplysninger (nøglering). autologinkeyV2 bibeholdes; næste API-kald kan udstede en ny session via Set-Cookie.")
            }

            // MARK: - About Section
            Section {
                HStack {
                    Text("App")
                    Spacer()
                    Text("BetterLectio")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/elliott-friedrich/betterlectio")!) {
                    HStack {
                        Label("GitHub", systemImage: "link")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Om")
            }
        }
        .task(id: student?.studentId) {
            guard let student else {
                scheduleEventTitles = []
                return
            }
            scheduleEventTitles = await ScheduleStore.shared.loadScheduleAsync(for: student.studentId)?.events.map(\.title) ?? []
        }
        .navigationTitle("Indstillinger")
        .sheet(isPresented: $showingBrowserExtension) {
            BrowserExtensionInviteView(source: .settings)
        }
        .alert("Ryd cache?", isPresented: $showClearCacheAlert) {
            Button("Annuller", role: .cancel) { }
            Button("Ryd", role: .destructive) {
                clearCache()
            }
        } message: {
            Text("Dette vil slette alle cachede data. Du bliver ikke logget ud.")
        }
        .alert("ASP.NET_SessionId slettet", isPresented: $showSessionCookieDeletedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("ASP.NET_SessionId er slettet fra web-lager og fra nøglering for denne elev. autologinkeyV2 er ikke slettet.")
        }
        .alert("Opdater ASP.NET_SessionId", isPresented: $showSetASPSessionIdAlert) {
            TextField("Værdi", text: $aspSessionIdDraft)
            Button("Annuller", role: .cancel) { }
            Button("Gem") {
                let studentId = student?.studentId ?? KeychainManager.shared.loadStudent()?.studentId
                Task {
                    await CookieManager.shared.setASPNETSessionIdEverywhere(sessionId: aspSessionIdDraft, forStudentId: studentId)
                    showSessionCookieSetAlert = true
                }
            }
            .disabled(aspSessionIdDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Indsæt den nye session-id-streng. Den gemmes i WebKit-cookie-lageret og i nøgleringen (hvis der findes login for eleven). autologinkeyV2 ændres ikke.")
        }
        .alert("ASP.NET_SessionId opdateret", isPresented: $showSessionCookieSetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Den nye værdi er skrevet til web-lager og til nøglering (hvis det var muligt).")
        }
        .alert("Opdater autologinkeyV2", isPresented: $showSetAutologinkeyV2Alert) {
            TextField("Værdi", text: $autologinkeyV2Draft)
            Button("Annuller", role: .cancel) { }
            Button("Gem") {
                let studentId = student?.studentId ?? KeychainManager.shared.loadStudent()?.studentId
                Task {
                    await CookieManager.shared.setAutologinkeyV2Everywhere(autologinkey: autologinkeyV2Draft, forStudentId: studentId)
                    showAutologinkeyV2SetAlert = true
                }
            }
            .disabled(autologinkeyV2Draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Indsæt den nye autologin-nøgle. Den gemmes i WebKit-cookie-lageret og i nøgleringen (hvis der findes login for eleven). ASP.NET_SessionId ændres ikke.")
        }
        .alert("autologinkeyV2 opdateret", isPresented: $showAutologinkeyV2SetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Den nye værdi er skrevet til web-lager og til nøglering (hvis det var muligt).")
        }
    }

    // MARK: - Actions

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            DispatchQueue.main.async {
                settingsStore.saveNotificationsEnabled(granted)
            }
        }
    }

    private func clearCache() {
        settingsStore.clearAllCaches()
    }

    private func testLiveActivity() {
        guard student != nil else { return }
        let events = makeTestLiveActivitySchedule()
        guard !events.isEmpty else { return }
        LiveActivityManager.shared.updateLiveActivity(events: events, currentTime: Date())
    }

    /// One lesson on today: starts in 1 minute (upcoming in the real `updateLiveActivity` path).
    private func makeTestLiveActivitySchedule() -> [ScheduleEvent] {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.startOfDay(for: now)
        guard let startDate = calendar.date(byAdding: .minute, value: 1, to: now) else { return [] }
        let durationMinutes = 60
        var endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate
        if !calendar.isDate(startDate, inSameDayAs: endDate) {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? endDate
            endDate = calendar.date(byAdding: .second, value: -1, to: nextDay) ?? endDate
        }
        let sh = calendar.component(.hour, from: startDate)
        let sm = calendar.component(.minute, from: startDate)
        let eh = calendar.component(.hour, from: endDate)
        let em = calendar.component(.minute, from: endDate)
        let startTime = String(format: "%02d:%02d", sh, sm)
        let endTime = String(format: "%02d:%02d", eh, em)
        return [
            ScheduleEvent(
                title: "Matematik",
                subtitle: "1x",
                startTime: startTime,
                endTime: endTime,
                teacher: "Test",
                room: "A2.14",
                date: day
            )
        ]
    }
}

#Preview {
    NavigationStack {
        SettingsView(student: nil)
    }
}
