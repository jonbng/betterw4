//
//  ScheduleView.swift
//  BetterW4
//
//  The Timetable tab — the screen the app opens on.
//
//  It renders one W4 week at a time (`ScheduleWeek` → `ScheduleDay` → `TimetableEvent`, merged
//  from Academics and Extra Academics by `TimetableRepository`) through a week strip, a
//  horizontal day pager that fills leftover space, and one of two timeline styles. Each day page
//  owns its own vertical scroller — the week strip is not nested inside the day scroll.
//
//  The parts that are load-bearing rather than decorative:
//
//    * the pager is a virtual index space (today at page 5000), so jumping a week never shifts
//      identities or rebuilds a growing date window;
//    * cached data paints first and a refresh happens behind it — the spinner only appears when
//      there is genuinely nothing to show, and a failure leaves the week on screen with a banner;
//    * the "last updated" line is driven by `W4Loaded.freshness`, so an offline launch says how
//      old the grid is rather than pretending it is live;
//    * the now-line and the header countdown share `TimeProvider.now` in Europe/Oslo, ticked
//      on the minute and again when the app becomes active — never W4's baked-in `#current_time`
//      (plan D-10).
//

import SwiftUI
import UIKit

struct ScheduleView: View {

    let student: Student

    @StateObject private var viewModel = ScheduleViewModel()
    @StateObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var customEvents = CustomEventsStore.shared

    @State private var currentPage: Int
    @State private var customEventEditor: CustomEventEditor?
    /// `scrollPosition` writes `0` during the first layout pass. Ignore that or
    /// the tab opens thousands of days away from today.
    @State private var pagerAcceptsScroll = false
    /// Strip taps / today / week changes snap the pager; ignore the echo so we
    /// do not `select` twice and fight the strip gesture.
    @State private var ignorePagerSync = false
    @State private var selectedEvent: TimetableEvent?
    @State private var currentTime = TimeProvider.now
    @Environment(\.scenePhase) private var scenePhase

    /// Virtual pager: page `dayCenterPage` is `dayAnchor` (today at init). Identity never shifts.
    private let dayAnchor: Date
    private static let dayCenterPage = 5000
    private static let dayPageCount = 10_000

    /// W4 is one student's own timetable; there is no "someone else's schedule" surface to target.
    /// `authViewModel` is accepted and ignored so the tab shell can keep passing it.
    init(student: Student, authViewModel: AuthenticationViewModel? = nil) {
        self.student = student
        let today = W4Dates.startOfDay(TimeProvider.now)
        self.dayAnchor = today
        _currentPage = State(initialValue: Self.dayCenterPage)
    }

    // MARK: - Pager dates

    private func dateForPage(_ page: Int) -> Date {
        W4Dates.startOfDay(W4Dates.adding(days: page - Self.dayCenterPage, to: dayAnchor))
    }

    private func pageForDate(_ date: Date) -> Int {
        let days = W4Dates.calendar
            .dateComponents([.day], from: dayAnchor, to: W4Dates.startOfDay(date)).day ?? 0
        return Self.dayCenterPage + days
    }

    /// Snap the pager and the view model to today. Opening the tab must never
    /// resume on whichever day was last on screen.
    private func showToday(animated: Bool) {
        selectDate(viewModel.today, animated: animated)
        Task { await viewModel.goToToday() }
    }

    private func selectDate(_ date: Date, animated: Bool) {
        let page = pageForDate(date)
        guard page != currentPage else { return }
        ignorePagerSync = true
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { currentPage = page }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) { currentPage = page }
        }
        Task { ignorePagerSync = false }
    }

    private var selectedDate: Date {
        let page = currentPage
        guard page >= 0, page < Self.dayPageCount else { return viewModel.selectedDate }
        return dateForPage(page)
    }

    private var datesWithEvents: Set<Date> {
        var dates = Set<Date>()
        for week in viewModel.weeks.values {
            for day in week.days {
                let date = W4Dates.startOfDay(day.date)
                if !viewModel.events(on: date).isEmpty {
                    dates.insert(date)
                }
            }
        }
        return dates
    }

    // MARK: - Header lesson

    private var currentLesson: TimetableEvent? {
        viewModel.currentLesson(at: currentTime)
    }

    private var upcomingLesson: TimetableEvent? {
        viewModel.nextLesson(at: currentTime)
    }

    private var headerLesson: TimetableEvent? {
        currentLesson ?? upcomingLesson
    }

    @ViewBuilder
    private var headerLayer: some View {
        if let lesson = headerLesson {
            let isUpcoming = currentLesson == nil
            ScheduleHeaderView(
                subjectName: lesson.displayTitle,
                room: lesson.room,
                minutesValue: isUpcoming
                    ? lesson.minutesUntilStart(from: currentTime)
                    : lesson.minutesRemaining(at: currentTime),
                progress: isUpcoming ? nil : lesson.progress(at: currentTime),
                isUpcoming: isUpcoming,
                accent: lesson.accentColor(useSubjectColors: settingsStore.useSubjectColors)
            )
            .zIndex(0)
        } else {
            Color.clear.frame(height: 0)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                headerLayer

                VStack(spacing: 0) {
                    calendarStripHeader
                    Divider()
                    freshnessBanner
                    dayPager
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(uiColor: .systemBackground))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CampusStatusControl()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    customEventEditor = .blank(on: selectedDate)
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                }
                .accessibilityLabel("Add custom event")
                schoolCalendarToolbarButton
                NotificationsBellButton()
            }
        }
        .onAppear {
            showToday(animated: false)
            DispatchQueue.main.async {
                pagerAcceptsScroll = true
            }
        }
        .background {
            TabBarSameTabReselectDetector(tabIndex: AuthenticatedTabIndex.timetable) {
                showToday(animated: true)
            }
        }
        .task {
            CustomEventsStore.shared.activate(studentId: student.studentId)
            showToday(animated: false)
            await viewModel.onAppear()

            guard !Task.isCancelled, !student.isDemo else { return }
            if viewModel.errorMessage == nil {
                ReviewPromptCoordinator.shared.maybePromptScheduleLoaded()
            } else {
                ReviewPromptCoordinator.shared.reportRecentError()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
            Task { await viewModel.reset() }
        }
        .task {
            currentTime = TimeProvider.now
            var lastToday = W4Dates.startOfDay(currentTime)
            while !Task.isCancelled {
                let wait = TimeProvider.secondsUntilNextMinute(after: TimeProvider.now)
                let nanoseconds = UInt64((wait * 1_000_000_000).rounded())
                try? await Task.sleep(nanoseconds: nanoseconds)
                currentTime = TimeProvider.now
                let newToday = W4Dates.startOfDay(currentTime)
                if !W4Dates.isSameDay(lastToday, newToday) {
                    lastToday = newToday
                    showToday(animated: false)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            currentTime = TimeProvider.now
            Task { await viewModel.load(weekContaining: selectedDate) }
        }
        .onChange(of: settingsStore.showSchoolCalendar) { _, _ in
            Task { await viewModel.applySchoolCalendarPreference() }
        }
        .onChange(of: customEvents.events) { _, _ in
            viewModel.applyCustomEvents()
        }
        .overlay(alignment: .top) {
            if let message = viewModel.errorMessage {
                errorBanner(message)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .sheet(item: $selectedEvent) { event in
            if CustomEvents.isCustomEvent(event) {
                CustomEventDetailSheet(
                    event: event,
                    onEdit: { editing in
                        selectedEvent = nil
                        customEventEditor = .editing(editing)
                    },
                    onDelete: { deleting in
                        selectedEvent = nil
                        customEvents.delete(id: deleting.id)
                    }
                )
            } else {
                LessonDetailSheet(event: event)
            }
        }
        .sheet(item: $customEventEditor) { editor in
            AddCustomEventView(editor: editor) { saved in
                if editor.isNew {
                    ReviewPromptCoordinator.shared.maybePrompt(.privateEventCreated)
                }
                selectDate(saved.date, animated: true)
            }
        }
    }

    // MARK: - Strip and pager

    @ViewBuilder
    private var calendarStripHeader: some View {
        CalendarStripView(
            selectedDate: selectedDate,
            weekNavigationEnabled: viewModel.weekNavigationAvailable,
            datesWithEvents: datesWithEvents,
            onDateSelected: { date in
                selectDate(date, animated: true)
                Task { await viewModel.select(date: date) }
            },
            onWeekChanged: { date in
                selectDate(date, animated: false)
                Task { await viewModel.select(date: date) }
            }
        )
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            weekNumberBadge
                .alignmentGuide(.top) { $0[VerticalAlignment.center] }
        }
    }

    @ViewBuilder
    private var dayPager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<Self.dayPageCount, id: \.self) { page in
                    let date = dateForPage(page)
                    ScheduleDayPage(
                        date: date,
                        timed: viewModel.timedEvents(on: date),
                        allDay: viewModel.allDayEvents(on: date),
                        gridStartHour: viewModel.gridStartHour(for: date),
                        gridEndHour: viewModel.gridEndHour(for: date),
                        style: settingsStore.calendarStyle,
                        now: W4Dates.isSameDay(date, currentTime) ? currentTime : nil,
                        isLoaded: viewModel.hasLoadedWeek(containing: date),
                        isLoading: !viewModel.hasLoadedWeek(containing: date)
                            && (viewModel.isLoading || viewModel.isRefreshing),
                        onEventTapped: { selectedEvent = $0 },
                        onAddAt: { customEventEditor = .at($0) },
                        onRefresh: { await viewModel.refresh() }
                    )
                    .equatable()
                    .containerRelativeFrame(.horizontal)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(
            get: { currentPage },
            set: { newValue in
                guard pagerAcceptsScroll, let newValue else { return }
                currentPage = newValue
            }
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: currentPage) { _, newPage in
            guard !ignorePagerSync else { return }
            guard newPage >= 0, newPage < Self.dayPageCount else { return }
            Task { await viewModel.select(date: dateForPage(newPage)) }
        }
    }

    // MARK: - Banners

    private var schoolCalendarToolbarButton: some View {
        Button {
            settingsStore.saveShowSchoolCalendar(!settingsStore.showSchoolCalendar)
        } label: {
            Image(systemName: settingsStore.showSchoolCalendar ? "calendar.circle.fill" : "calendar")
                .imageScale(.large)
                .foregroundStyle(settingsStore.showSchoolCalendar ? Color.accentColor : Color.secondary)
        }
        .accessibilityLabel(
            settingsStore.showSchoolCalendar ? "Hide school calendar" : "Show school calendar"
        )
        .accessibilityAddTraits(settingsStore.showSchoolCalendar ? [.isSelected] : [])
    }

    @ViewBuilder
    private var freshnessBanner: some View {
        if viewModel.isShowingDemoData {
            bannerRow(icon: "wand.and.stars", text: "Demo data", tint: .purple)
        } else if viewModel.isShowingCachedCopy, let text = viewModel.lastUpdatedText {
            bannerRow(
                icon: viewModel.isShowingStaleCopy ? "wifi.slash" : "clock.arrow.circlepath",
                text: text,
                tint: viewModel.isShowingStaleCopy ? .orange : .secondary
            )
        } else if !viewModel.weekNavigationAvailable {
            bannerRow(icon: "calendar.badge.exclamationmark", text: "W4 only shows the current week", tint: .secondary)
        }
    }

    private func bannerRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
            Spacer(minLength: 0)
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Could not reach W4")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.errorMessage = nil
                Task { await viewModel.refresh() }
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        )
    }

    @ViewBuilder
    private var weekNumberBadge: some View {
        Text("Week \(W4Dates.isoWeek(of: selectedDate).week)")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
            )
            .allowsHitTesting(false)
    }
}

// MARK: - One day

/// One page of the day pager. `Equatable` so a week swipe that only changes `selectedDate`
/// does not rebuild off-screen days.
private struct ScheduleDayPage: View, Equatable {
    let date: Date
    let timed: [TimetableEvent]
    let allDay: [TimetableEvent]
    let gridStartHour: Int
    let gridEndHour: Int
    let style: CalendarStyle
    let now: Date?
    let isLoaded: Bool
    let isLoading: Bool
    let onEventTapped: (TimetableEvent) -> Void
    var onAddAt: ((Date) -> Void)? = nil
    let onRefresh: () async -> Void

    static func == (lhs: ScheduleDayPage, rhs: ScheduleDayPage) -> Bool {
        lhs.date == rhs.date
            && lhs.timed == rhs.timed
            && lhs.allDay == rhs.allDay
            && lhs.gridStartHour == rhs.gridStartHour
            && lhs.gridEndHour == rhs.gridEndHour
            && lhs.style == rhs.style
            && lhs.now == rhs.now
            && lhs.isLoaded == rhs.isLoaded
            && lhs.isLoading == rhs.isLoading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AllDayEventsView(events: allDay) { event in
                    onEventTapped(event)
                }

                if !isLoaded {
                    loadingPlaceholder
                } else if style == .professional {
                    ModernTimelineListView(
                        displayDate: date,
                        events: timed,
                        gridStartHour: gridStartHour,
                        gridEndHour: gridEndHour,
                        now: now,
                        onEventTapped: onEventTapped,
                        onAddAt: onAddAt
                    )
                    .padding(.trailing, 16)
                } else {
                    TimelineListView(
                        displayDate: date,
                        events: timed,
                        gridStartHour: gridStartHour,
                        now: now,
                        onEventTapped: onEventTapped,
                        onAddAt: onAddAt
                    )
                    .padding(.trailing, 16)
                    .padding(.leading, 4)
                }

                Color.clear.frame(height: 80)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await onRefresh() }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        if isLoading {
            ScheduleDaySkeleton()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Pull to load this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
        }
    }
}

// MARK: - Lesson detail

/// What W4 knows about one block.
///
/// No real `.period` element has ever been captured, so this sheet is built to look right with a
/// title and nothing else: every other row disappears when its field is `nil` rather than
/// rendering a placeholder.
struct LessonDetailSheet: View {
    let event: TimetableEvent
    var onEditCustom: ((TimetableEvent) -> Void)? = nil
    var onDeleteCustom: ((TimetableEvent) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settingsStore = SettingsStore.shared
    @StateObject private var directory = DirectoryViewModel()
    @State private var people: [DirectoryPerson] = []
    @State private var peopleLoading = false
    @State private var confirmDelete = false

    private var isCustomEvent: Bool { CustomEvents.isCustomEvent(event) }

    private var themeColor: Color {
        event.accentColor(useSubjectColors: settingsStore.useSubjectColors)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    infoSection

                    if let detail = event.detailText, !isCustomEvent {
                        Divider()
                        noteSection(title: "Details from W4", text: detail)
                    }

                    if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !notes.isEmpty {
                        Divider()
                        noteSection(title: "Note", text: notes)
                    }

                    if !people.isEmpty || peopleLoading {
                        Divider()
                        peopleSection
                    }

                    if let classId = ClassRoster.classId(from: event.href), !isCustomEvent {
                        Divider()
                        NavigationLink {
                            MyClassDetailView(
                                classId: classId,
                                seed: MyClass(
                                    id: classId,
                                    subject: event.displayTitle,
                                    room: event.room.flatMap { $0.nilIfEmpty }.map { ClassRoom(name: $0) }
                                ),
                                directory: directory,
                                selfUwcId: W4RequestContext.current()?.rosterUwcId
                            )
                        } label: {
                            Label("View class", systemImage: "books.vertical")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if let href = event.href, let url = openInW4URL(href), !isCustomEvent {
                        Divider()
                        NavigationLink {
                            LessonW4PageView(url: url, title: event.displayTitle)
                        } label: {
                            Label("Open in W4", systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
                        }
                    }

                    if isCustomEvent {
                        Divider()
                        VStack(spacing: 8) {
                            Button {
                                let editing = event
                                dismiss()
                                DispatchQueue.main.async {
                                    onEditCustom?(editing)
                                }
                            } label: {
                                Label("Edit event", systemImage: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label("Delete event", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15, weight: .heavy))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete event", role: .destructive) {
                let deleting = event
                dismiss()
                onDeleteCustom?(deleting)
            }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: event.id) {
            guard !isCustomEvent else { return }
            await loadPeople()
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: event.iconName)
                .font(.title2)
                .foregroundColor(themeColor.readableAccent(colorScheme: colorScheme))
                .frame(width: 44, height: 44)
                .background(themeColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.displayTitle)
                        .font(.title3)
                        .fontWeight(.bold)

                    if let statusLabel = event.statusLabel {
                        Text(statusLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(event.status == .cancelled ? .red : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (event.status == .cancelled ? Color.red : Color.orange).opacity(0.1)
                            )
                            .clipShape(Capsule())
                    }
                }

                // Only worth repeating when the rename actually changed something.
                if event.title != event.displayTitle {
                    Text(event.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text(event.source.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(spacing: 10) {
            infoRow(icon: "calendar", text: W4Dates.format(event.date))

            if event.isAllDay || event.timeRangeText == nil {
                infoRow(icon: "clock", text: "All day")
            } else if let range = event.timeRangeText {
                infoRow(icon: "clock", text: range)
            }

            if let room = event.room, !room.isEmpty {
                infoRow(icon: "mappin.and.ellipse", text: room)
            }

            if let teacher = event.teacher, !teacher.isEmpty {
                if let uwcId = event.teacherUwcId, !uwcId.isEmpty {
                    NavigationLink {
                        StudentProfileView(uwcId: uwcId, directory: directory)
                    } label: {
                        infoRow(icon: "person", text: teacher)
                    }
                    .buttonStyle(.plain)
                } else {
                    infoRow(icon: "person", text: teacher)
                }
            }

            if let attendance = event.attendance {
                infoRow(icon: "checkmark.seal", text: attendance.displayName)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }

    private func noteSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "quote.opening")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: People

    private var staff: [DirectoryPerson] { people.filter { $0.kind == .staff } }
    private var students: [DirectoryPerson] { people.filter { $0.kind != .staff } }

    @ViewBuilder
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People")
                .font(.headline)

            if peopleLoading && people.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            if !staff.isEmpty {
                Text("Teachers")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                ForEach(staff) { person in
                    personRow(person)
                }
            }

            if !students.isEmpty {
                if !staff.isEmpty { Spacer().frame(height: 4) }
                Text("Students")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                ForEach(students) { person in
                    personRow(person)
                }
            }
        }
    }

    private func personRow(_ person: DirectoryPerson) -> some View {
        NavigationLink {
            StudentProfileView(person: person, directory: directory)
        } label: {
            HStack(spacing: 12) {
                W4AvatarView(
                    url: person.photoURL ?? W4PeopleParser.photoURL(forUWCId: person.uwcId),
                    name: person.displayName,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    if let subtitle = person.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadPeople() async {
        peopleLoading = true
        defer { peopleLoading = false }
        do {
            let loaded = try await ClassRosterRepository.shared.people(for: event)
            people = loaded.value
        } catch {
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
        }
    }

    /// W4 hrefs are relative Yii routes; anything that is not a W4 URL is refused rather than
    /// opened with a session cookie attached.
    private func openInW4URL(_ href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = W4Routes.resolve(trimmed)
        guard W4Routes.isW4Host(url.host) else { return nil }
        return url
    }
}

/// One W4 page, rendered in-app with the signed-in session.
private struct LessonW4PageView: View {
    let url: URL
    let title: String

    @State private var isLoading = true

    private var credentials: W4Credentials {
        W4RequestContext.current()?.credentials ?? .empty
    }

    var body: some View {
        ZStack {
            W4WebView(
                url: url,
                credentials: credentials,
                onLoadingChanged: { loading in isLoading = loading }
            )
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ScheduleView(student: .demo)
    }
}
