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
    @Published private(set) var week: ScheduleWeek?
    @Published private(set) var selectedDate: Date = W4Dates.startOfDay(TimeProvider.now)
    /// Only ever set when there is nothing at all to show.
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingSchedule = false

    private let repository: ProfileRepository
    private let houseRepository: HouseRepository
    private let timetableRepository: TimetableRepository
    /// A newer load always wins, so a slow answer for a person the student has left cannot
    /// overwrite the one they are looking at now.
    private var generation = 0
    private var loadedUwcId = ""

    init(
        repository: ProfileRepository = .shared,
        houseRepository: HouseRepository = .shared,
        timetableRepository: TimetableRepository = .shared
    ) {
        self.repository = repository
        self.houseRepository = houseRepository
        self.timetableRepository = timetableRepository
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
        loadedUwcId = uwcId

        if profile == nil { profile = fallback }

        if !forceRefresh, let cached = await repository.cachedProfile(uwcId: uwcId) {
            guard token == generation else { return }
            profile = StudentProfile(profile: cached.value)
                .applying(placement: nil, classes: fallback?.classes ?? [])
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

        await loadPlacementAndSchedule(uwcId: uwcId, token: token, forceRefresh: forceRefresh)
    }

    func shiftWeek(_ delta: Int) async {
        let start = W4Dates.startOfWeek(containing: selectedDate)
        let next = W4Dates.adding(days: delta * 7, to: start)
        selectedDate = next
        await loadWeek(uwcId: loadedUwcId, containing: next, token: generation)
    }

    func goToToday() async {
        let today = W4Dates.startOfDay(TimeProvider.now)
        selectedDate = today
        await loadWeek(uwcId: loadedUwcId, containing: today, token: generation)
    }

    func select(date: Date) {
        selectedDate = W4Dates.startOfDay(date)
    }

    private func loadPlacementAndSchedule(uwcId: String, token: Int, forceRefresh: Bool) async {
        async let placementTask = houseRepository.findPlacement(uwcId: uwcId)
        await loadWeek(uwcId: uwcId, containing: selectedDate, token: token, forceRefresh: forceRefresh)
        let placement = await placementTask
        guard token == generation else { return }
        let classes = week.map(PersonClasses.from(week:)) ?? []
        if let current = profile {
            profile = current.applying(placement: placement, classes: classes)
        }
    }

    private func loadWeek(
        uwcId: String,
        containing date: Date,
        token: Int,
        forceRefresh: Bool = false
    ) async {
        guard !uwcId.isEmpty else { return }
        isLoadingSchedule = week == nil
        defer {
            if token == generation { isLoadingSchedule = false }
        }
        do {
            let loaded = try await timetableRepository.personWeek(
                uwcId: uwcId,
                containing: date,
                forceRefresh: forceRefresh
            )
            guard token == generation else { return }
            week = loaded.value
            if let current = profile {
                profile = current.applying(placement: nil, classes: PersonClasses.from(week: loaded.value))
            }
            let days = loaded.value.days
            if !days.contains(where: { W4Dates.isSameDay($0.date, selectedDate) }) {
                let today = W4Dates.startOfDay(TimeProvider.now)
                selectedDate = days.first(where: { W4Dates.isSameDay($0.date, today) })?.date
                    ?? days.first(where: { W4Dates.calendar.component(.weekday, from: $0.date) == W4Dates.calendar.component(.weekday, from: selectedDate) })?.date
                    ?? days.first?.date
                    ?? selectedDate
            }
        } catch {
            guard token == generation else { return }
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
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
    @StateObject private var houses = HousesViewModel()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingPhoto = false
    @State private var didCopyEmail = false
    @State private var tab: ProfileTab

    /// Pushed from a directory row: everything the row knew is on screen before the fetch starts.
    init(person: DirectoryPerson, directory: DirectoryViewModel) {
        self.uwcId = person.uwcId
        self.kind = person.kind
        self.fallback = StudentProfile(person: person)
        self._directory = ObservedObject(wrappedValue: directory)
        self._tab = State(initialValue: person.kind == .staff ? .about : .schedule)
    }

    /// Pushed from a house room: house + room are already known, so the hero paints them immediately.
    init(person: DirectoryPerson, placement: HousePlacement, directory: DirectoryViewModel) {
        self.uwcId = person.uwcId
        self.kind = person.kind
        self.fallback = StudentProfile(person: person).applying(placement: placement, classes: [])
        self._directory = ObservedObject(wrappedValue: directory)
        self._tab = State(initialValue: person.kind == .staff ? .about : .schedule)
    }

    /// Pushed from a bare UWC id (a deep link, or a person who has left the cached table).
    init(uwcId: String, directory: DirectoryViewModel) {
        self.uwcId = uwcId
        self.kind = nil
        self.fallback = nil
        self._directory = ObservedObject(wrappedValue: directory)
        self._tab = State(initialValue: .schedule)
    }

    private var profile: StudentProfile? { model.profile ?? fallback }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let profile {
                    hero(profile)
                    actions(profile)
                    Picker("Section", selection: $tab) {
                        Text("Schedule").tag(ProfileTab.schedule)
                        Text("About").tag(ProfileTab.about)
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case .schedule:
                        personSchedule
                    case .about:
                        if profile.kind == .staff {
                            staffAbout(profile)
                        } else {
                            about(profile)
                        }
                    }
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
            await houses.load()
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

                if profile.kind == .staff {
                    if let country = profile.country {
                        Text(country)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !profile.positions.isEmpty {
                        roleChips(profile.positions)
                    } else {
                        Label(profile.kindLabel, systemImage: "person.text.rectangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                } else {
                    if let subtitle = profile.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Label(profile.kindLabel, systemImage: "person.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
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

    // MARK: About

    @ViewBuilder
    private func about(_ profile: StudentProfile) -> some View {
        VStack(spacing: 16) {
            aboutCard {
                if let house = profile.house {
                    if let houseId = profile.houseId {
                        NavigationLink {
                            HouseDetailView(
                                houseId: houseId,
                                viewModel: houses,
                                directory: directory
                            )
                        } label: {
                            aboutLinkRow(
                                title: "House",
                                value: houseFlagLabel(house, houseId: houseId),
                                systemImage: "house.fill",
                                hint: "View house"
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        detailRow("House", value: houseFlagLabel(house), systemImage: "house.fill")
                    }
                }
                if let room = profile.room {
                    if let houseId = profile.houseId {
                        NavigationLink {
                            HouseDetailView(
                                houseId: houseId,
                                viewModel: houses,
                                directory: directory
                            )
                        } label: {
                            aboutLinkRow(
                                title: "Room",
                                value: room,
                                systemImage: "door.left.hand.closed",
                                hint: "View house"
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        detailRow("Room", value: room, systemImage: "door.left.hand.closed")
                    }
                }
                if profile.house == nil && profile.room == nil {
                    Text("House not listed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            aboutCard {
                Text("Classes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if profile.classes.isEmpty {
                    Text("No classes on this week's timetable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.classes) { item in
                        classRow(item)
                    }
                }
            }

            extraFields(profile)

            aboutCard {
                ForEach(Self.detailRows(for: profile)) { row in
                    detailRow(row.title, value: row.value, systemImage: row.systemImage)
                }
            }
        }
    }

    @ViewBuilder
    private func staffAbout(_ profile: StudentProfile) -> some View {
        VStack(spacing: 16) {
            aboutCard {
                Text("Contact")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                contactRow(
                    title: "Email",
                    value: profile.email,
                    systemImage: "envelope.fill",
                    url: URL(string: "mailto:\(profile.email)")
                )
                if let office = profile.officeTel {
                    detailRow("Office", value: office, systemImage: "phone.fill")
                }
                if let mobile = profile.mobile {
                    contactRow(
                        title: "Mobile",
                        value: mobile,
                        systemImage: "iphone",
                        url: Self.phoneURL(mobile)
                    )
                }
            }

            aboutCard {
                Text("Classes they teach")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if profile.classes.isEmpty {
                    Text("Not teaching any classes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.classes) { item in
                        classRow(item)
                    }
                }
            }

            aboutCard {
                Text("Extra academics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if profile.activities.isEmpty {
                    Text("No extra-academic activities listed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.activities) { activity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                                .font(.subheadline.weight(.medium))
                            let meta = [
                                activity.category?.capitalized,
                                activity.dates
                            ].compactMap { $0 }.joined(separator: " · ")
                            if !meta.isEmpty {
                                Text(meta)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            extraFields(profile)

            if profile.country != nil || profile.birthday != nil {
                aboutCard {
                    if let country = profile.country {
                        detailRow("Country", value: country, systemImage: "globe")
                    }
                    if let birthday = profile.birthday {
                        detailRow("Birthday", value: birthday, systemImage: "gift")
                    }
                }
            }
        }
    }

    private func roleChips(_ roles: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(roles, id: \.self) { role in
                Text(role)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func classRow(_ item: PersonClass) -> some View {
        if let classId = item.classId, item.canOpen {
            NavigationLink {
                ClassRosterView(
                    classId: classId,
                    title: item.name,
                    directory: directory
                )
            } label: {
                aboutLinkRow(
                    title: item.name,
                    value: item.subtitle,
                    systemImage: "book.fill",
                    hint: item.subtitle == nil ? "View class" : ""
                )
            }
            .buttonStyle(.plain)
        } else {
            detailRow(item.name, value: item.subtitle ?? "", systemImage: "book.fill")
        }
    }

    @ViewBuilder
    private func contactRow(title: String, value: String, systemImage: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                detailRow(title, value: value, systemImage: systemImage)
            }
            .buttonStyle(.plain)
        } else {
            detailRow(title, value: value, systemImage: systemImage)
        }
    }

    private static func phoneURL(_ raw: String) -> URL? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        let count = digits.filter(\.isNumber).count
        guard count >= 8 else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func aboutLinkRow(
        title: String,
        value: String?,
        systemImage: String,
        hint: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let value, !value.isEmpty {
                    Text(value).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                }
                if !hint.isEmpty {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// Remaining identity fields — house, room and classes have their own rows.
    private static func detailRows(for profile: StudentProfile) -> [ProfileDetailRow] {
        var rows: [ProfileDetailRow] = [
            ProfileDetailRow(title: "UWC id", value: profile.uwcId, systemImage: "person.text.rectangle"),
            ProfileDetailRow(title: "Email", value: profile.email, systemImage: "envelope")
        ]
        if let year = profile.year {
            rows.append(ProfileDetailRow(title: "Year", value: year, systemImage: "graduationcap"))
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
    private var personSchedule: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(scheduleTitle)
                    .font(.headline)
                Spacer()
                if model.isLoadingSchedule {
                    ProgressView().controlSize(.mini)
                }
                Button {
                    Task { await model.shiftWeek(-1) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(model.isLoadingSchedule)
                Button {
                    Task { await model.goToToday() }
                } label: {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                }
                .disabled(model.isLoadingSchedule)
                Button {
                    Task { await model.shiftWeek(1) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(model.isLoadingSchedule)
            }

            if let week = model.week {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(week.days, id: \.date) { day in
                            let selected = W4Dates.isSameDay(day.date, model.selectedDate)
                            Button {
                                model.select(date: day.date)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(String(W4Dates.weekdayName(of: day.date).prefix(3)))
                                        .font(.caption2.weight(.semibold))
                                    Text("\(W4Dates.calendar.component(.day, from: day.date))")
                                        .font(.headline)
                                    Circle()
                                        .fill(day.events.isEmpty ? Color.clear : Color.accentColor)
                                        .frame(width: 5, height: 5)
                                }
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .frame(width: 48, height: 64)
                                .background(
                                    selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let events = week.day(on: model.selectedDate)?.events ?? []
                if events.isEmpty {
                    Text("No lessons this day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text(eventTimeLine(event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if !model.isLoadingSchedule {
                Text("No lessons this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var scheduleTitle: String {
        if let week = model.week {
            return "Schedule · week \(week.week)"
        }
        return "Schedule"
    }

    private func eventTimeLine(_ event: TimetableEvent) -> String {
        var parts: [String] = []
        if let start = event.start, let end = event.end {
            parts.append("\(W4Dates.formatTime(start)) – \(W4Dates.formatTime(end))")
        } else if event.isAllDay {
            parts.append("All day")
        }
        if let room = event.room, !room.isEmpty { parts.append(room) }
        if let teacher = event.teacher, !teacher.isEmpty { parts.append(teacher) }
        return parts.joined(separator: " · ")
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

private enum ProfileTab: Hashable {
    case schedule
    case about
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
