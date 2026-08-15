
import SwiftUI
import Combine
import UIKit

struct ScheduleView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    let scheduleTarget: SchedulableTarget
    var targetImageURL: URL? = nil
    var targetPublicImageURL: URL? = nil
    let hidesNavigationBackButton: Bool
    @StateObject private var viewModel = ScheduleViewModel()
    @StateObject private var settingsStore = SettingsStore.shared
    @State private var dateRange: [Date] = []
    @State private var currentPage: Int = 0
    @State private var selectedEvent: ScheduleEvent?
    @State private var scrollSafeAreaInsets: (top: CGFloat, bottom: CGFloat) = (0, 0)
    @State private var currentTime = TimeProvider.now
    @State private var showingAddEvent = false
    @State private var stripTopY: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let calendar = Calendar.current
    // Dynamically sized to fit the longest day in the loaded date range,
    // so very late lessons don't get vertically centered/clipped by the TabView.
    // Cached height for the paged calendar, sized to fit the longest day in the loaded
    // date range so very late lessons don't get clipped. Recomputed only when the events,
    // date range, or calendar style change — never on every body render (see recomputeTabViewHeight()).
    @State private var tabViewHeight: CGFloat = 720

    /// Pure computation of the tab height from the cached, pre-split day events.
    private func computeTabViewHeight() -> CGFloat {
        let isProfessional = settingsStore.calendarStyle == .professional
        let referenceMinutes = isProfessional ? 8 * 60 : (8 * 60 + 10)
        // Trailing breathing room baked into each timeline view (calculateTotalHeight padding +
        // the 80pt Color.clear footer; modern adds 8pt vertical padding × 2 + larger end pad).
        let trailingPadding: CGFloat = isProfessional ? 140 : 100
        let allDayStripHeight: CGFloat = 56
        let minHeight: CGFloat = 720

        var maxHeight: CGFloat = minHeight
        for date in dateRange {
            let pageEvents = viewModel.dayEvents(for: date)
            var pageHeight: CGFloat = 0
            if !pageEvents.allDay.isEmpty { pageHeight += allDayStripHeight }
            if let latestEnd = pageEvents.maxEndMinutes {
                pageHeight += max(0, CGFloat(latestEnd - referenceMinutes)) + trailingPadding
            }
            maxHeight = max(maxHeight, pageHeight)
        }
        return maxHeight
    }

    init(student: Student, authViewModel: AuthenticationViewModel, studentImageURL: URL? = nil) {
        self.student = student
        self.authViewModel = authViewModel
        self.scheduleTarget = SchedulableTarget(
            kind: .student,
            id: student.studentId,
            displayName: student.name ?? "Elev",
            gymId: student.gymId
        )
        self.targetImageURL = studentImageURL
        self.targetPublicImageURL = nil
        self.hidesNavigationBackButton = true
    }

    init(
        authenticatedStudent: Student,
        authViewModel: AuthenticationViewModel,
        target: SchedulableTarget,
        targetImageURL: URL? = nil,
        targetPublicImageURL: URL? = nil
    ) {
        self.student = authenticatedStudent
        self.authViewModel = authViewModel
        self.scheduleTarget = target
        self.targetImageURL = targetImageURL
        self.targetPublicImageURL = targetPublicImageURL
        self.hidesNavigationBackButton = false
    }

    /// The logged-in user's student ID, used for credential lookups.
    private var authenticatedStudentId: String {
        authViewModel.authState.student?.studentId ?? student.studentId
    }

    /// Whether we're viewing a target other than the logged-in student's own schedule.
    private var isViewingOtherTarget: Bool {
        scheduleTarget.kind != .student || scheduleTarget.id != authenticatedStudentId
    }

    private func startOfWeek(for date: Date) -> Date {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    private func buildDateRange(around date: Date) -> [Date] {
        let monday = startOfWeek(for: date)
        guard let start = calendar.date(byAdding: .day, value: -14, to: monday) else { return [] }
        return (0..<28).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    private func setCurrentPage(_ index: Int, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentPage = index
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                currentPage = index
            }
        }
    }

    private func ensureDateInRange(_ date: Date) {
        let target = calendar.startOfDay(for: date)

        if dateRange.isEmpty {
            dateRange = buildDateRange(around: target)
            return
        }

        var prependedCount = 0
        while let first = dateRange.first, target < first {
            guard let newWeekStart = calendar.date(byAdding: .day, value: -7, to: first) else { break }
            let newWeekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: newWeekStart) }
            dateRange.insert(contentsOf: newWeekDates, at: 0)
            prependedCount += newWeekDates.count
        }

        if prependedCount > 0 {
            currentPage += prependedCount
        }

        while let last = dateRange.last, target > last {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: last) else { break }
            let newWeekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: nextDay) }
            dateRange.append(contentsOf: newWeekDates)
        }
    }

    private func selectDate(_ date: Date, animated: Bool) {
        ensureDateInRange(date)
        if let index = dateRange.firstIndex(where: { calendar.isDate($0, inSameDayAs: date) }) {
            setCurrentPage(index, animated: animated)
        }
    }

    private func captureSafeArea(_ geo: GeometryProxy) {
        scrollSafeAreaInsets = (geo.safeAreaInsets.top, geo.safeAreaInsets.bottom)
    }

    // Selected date from the current page
    private var selectedDate: Date {
        guard currentPage >= 0, currentPage < dateRange.count else { return TimeProvider.now }
        return dateRange[currentPage]
    }

    private var selectedWeekNumber: Int {
        calendar.component(.weekOfYear, from: selectedDate)
    }

    // Filter events for the selected date
    private var eventsForSelectedDate: [ScheduleEvent] {
        viewModel.events(for: selectedDate)
    }


    // MARK: - Current Lesson Helpers

    /// Finds the current active lesson based on the current time
    private var currentLesson: ScheduleEvent? {
        let now = currentTime
        let calendar = Calendar.current
        let todaysEvents = viewModel.events(for: now).timed

        // Get current time in minutes since midnight
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeMinutes = currentHour * 60 + currentMinute

        // Find lesson that's currently active (all-day events handled separately)
        return todaysEvents.first { event in
            let startMinutes = event.timeToMinutes(event.startTime)
            let endMinutes = event.timeToMinutes(event.endTime)
            return currentTimeMinutes >= startMinutes && currentTimeMinutes < endMinutes
        }
    }

    /// Finds the next lesson starting within 60 minutes (when no lesson is currently active)
    private var nextLessonWithin60Min: ScheduleEvent? {
        guard currentLesson == nil else { return nil }
        let now = currentTime
        let calendar = Calendar.current
        let todaysEvents = viewModel.events(for: now).timed

        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeMinutes = currentHour * 60 + currentMinute

        return todaysEvents
            .filter { event in
                let startMinutes = event.timeToMinutes(event.startTime)
                let minutesUntilStart = startMinutes - currentTimeMinutes
                return minutesUntilStart > 0 && minutesUntilStart <= 60
            }
            .min(by: { $0.timeToMinutes($0.startTime) < $1.timeToMinutes($1.startTime) })
    }

    /// Minutes until the next lesson starts (for nextLessonWithin60Min)
    private func minutesUntilStart(for event: ScheduleEvent) -> Int {
        event.minutesUntilStart(relativeTo: currentTime)
    }

    /// Calculates minutes remaining in the current lesson
    private func minutesRemaining(for event: ScheduleEvent) -> Int {
        event.minutesRemaining(relativeTo: currentTime)
    }

    /// Calculates progress percentage (0.0 to 1.0) through the current lesson
    private func lessonProgress(for event: ScheduleEvent) -> Double {
        event.progress(relativeTo: currentTime)
    }

    /// The lesson to show in the header: current if active, otherwise next within 60 min
    private var headerLesson: ScheduleEvent? {
        currentLesson ?? nextLessonWithin60Min
    }

    private var preHeaderRevealHeight: CGFloat {
        var height: CGFloat = 0
        if isViewingOtherTarget { height += 42 }
        if headerLesson != nil { height += isViewingOtherTarget ? 56 : 80 }
        return height
    }

    private var scheduleHeaderParams: (subjectName: String?, room: String?, minutesValue: Int?, progress: Double?, isUpcoming: Bool) {
        (
            headerLesson.map { SubjectMapper.displayName(for: $0.title) },
            headerLesson?.room,
            headerLesson.map { lesson in
                currentLesson?.id == lesson.id
                    ? minutesRemaining(for: lesson)
                    : minutesUntilStart(for: lesson)
            },
            currentLesson.map { lessonProgress(for: $0) },
            nextLessonWithin60Min != nil && currentLesson == nil
        )
    }

    @ViewBuilder
    private var headerLayer: some View {
        VStack(spacing: 0) {
            if isViewingOtherTarget {
                HStack(spacing: 10) {
                    if scheduleTarget.kind == .student || scheduleTarget.kind == .teacher {
                        if let targetPublicImageURL {
                            PublicProfileAvatarView(
                                url: targetPublicImageURL,
                                name: scheduleTarget.displayName,
                                size: 28,
                                lectioFallbackURL: targetImageURL
                            )
                        } else {
                            RateLimitedAvatarImage(url: targetImageURL, size: 28) {
                                Text(initials(scheduleTarget.displayName))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                        }
                    } else {
                        Image(systemName: scheduleTarget.kind.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Text(scheduleTarget.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            ScheduleHeaderView(
                subjectName: scheduleHeaderParams.subjectName,
                room: scheduleHeaderParams.room,
                minutesValue: scheduleHeaderParams.minutesValue,
                progress: isViewingOtherTarget ? nil : scheduleHeaderParams.progress,
                isUpcoming: scheduleHeaderParams.isUpcoming,
            )
        }
        .padding(.top, 0)
        .zIndex(0)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }


    @ViewBuilder
    private var mainScrollLayer: some View {
        ScrollView {
            mainScrollContent
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await Task {
                await viewModel.refreshSchedule(for: scheduleTarget, authenticatedStudent: student, weekOf: selectedDate, force: true)
            }.value
        }
        .mask {
            Rectangle()
                .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
                .ignoresSafeArea(edges: .bottom)
                
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { captureSafeArea(geo) }
                    .onChange(of: geo.safeAreaInsets) { _, _ in captureSafeArea(geo) }
            }
        )
        .zIndex(1)
    }

    @ViewBuilder
    private var mainScrollContent: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Color.clear
                .frame(height: preHeaderRevealHeight)

            Section {
                timelineSectionContent
            } header: {
                calendarStripHeader
            }
        }
    }

    /// A single day's page for the horizontal pager, built from the view-model's
    /// pre-split cached day events.
    @ViewBuilder
    private func daySchedulePage(for date: Date) -> some View {
        let pageEvents = viewModel.dayEvents(for: date)
        VStack(spacing: 0) {
            AllDayEventsView(events: pageEvents.allDay) { event in
                selectedEvent = event
            }
            if settingsStore.calendarStyle == .professional {
                ModernTimelineListView(
                    displayDate: date,
                    events: pageEvents.timed,
                    onEventTapped: { event in
                        selectedEvent = event
                    },
                    gymId: scheduleTarget.gymId
                )
                .padding(.trailing, 16)
                .padding(.leading, 0)
            } else {
                TimelineListView(
                    displayDate: date,
                    events: pageEvents.timed,
                    onEventTapped: { event in
                        selectedEvent = event
                    },
                    gymId: scheduleTarget.gymId
                )
                .padding(.trailing, 16)
                .padding(.leading, 4)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var timelineSectionContent: some View {
        
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 12)

            // Lazy horizontal pager: only the visible day (± neighbours) is built and
            // kept in memory, so scrolling many weeks back stays smooth regardless of
            // how large `dateRange` grows.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(dateRange.enumerated()), id: \.offset) { index, date in
                        daySchedulePage(for: date)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { currentPage },
                set: { newValue in if let newValue { currentPage = newValue } }
            ))
            .frame(height: tabViewHeight)
            .onChange(of: currentPage) { _, newPage in
                if newPage >= 0, newPage < dateRange.count {
                    let date = dateRange[newPage]
                    if newPage <= 1, let first = dateRange.first,
                       let dayBefore = calendar.date(byAdding: .day, value: -1, to: first) {
                        ensureDateInRange(dayBefore)
                    } else if newPage >= dateRange.count - 2, let last = dateRange.last,
                       let dayAfter = calendar.date(byAdding: .day, value: 1, to: last) {
                        ensureDateInRange(dayAfter)
                    }
                    Task {
                        await viewModel.ensureWeekLoadedIfNeeded(for: date, target: scheduleTarget, authenticatedStudent: student)
                    }
                }
            }

            Color.clear.frame(height: 100)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var calendarStripHeader: some View {
        CalendarStripView(
            selectedDate: selectedDate,
            onDateSelected: { date in
                selectDate(date, animated: true)
                Task {
                    await viewModel.ensureWeekLoadedIfNeeded(for: date, target: scheduleTarget, authenticatedStudent: student)
                }
            },
            onWeekChanged: { newDate in
                selectDate(newDate, animated: false)
                Task {
                    await viewModel.ensureWeekLoadedIfNeeded(for: newDate, target: scheduleTarget, authenticatedStudent: student)
                }
            }
        )
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: StripTopPositionKey.self,
                    value: geo.frame(in: .named("scheduleView")).minY
                )
            }
        )
    }

    @ViewBuilder
    private var authErrorBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Forbindelsen til Lectio fejlede")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Prøv igen. Din session er stadig gemt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.requiresReauthentication = false
                viewModel.errorMessage = nil
                Task {
                    await viewModel.refreshSchedule(for: scheduleTarget, authenticatedStudent: student)
                }
            } label: {
                Text("Prøv igen")
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
        .contextMenu {
            Button(role: .destructive) {
                Task { await authViewModel.logout() }
            } label: {
                Label("Log ud", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    @ViewBuilder
    private var weekNumberBadge: some View {
        Text("Uge \(selectedWeekNumber)")
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
            .frame(maxWidth: .infinity)
            .alignmentGuide(.top) { $0[VerticalAlignment.center] }
            .offset(y: stripTopY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var fabLayer: some View {
        if !isViewingOtherTarget {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showingAddEvent = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4, y: 4)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 32)
                }
            }
            .zIndex(2)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            headerLayer

            mainScrollLayer

            weekNumberBadge
                .zIndex(2)

            fabLayer
        }
        .coordinateSpace(name: "scheduleView")
        .onPreferenceChange(StripTopPositionKey.self) { y in
            stripTopY = y
        }
        .navigationBarBackButtonHidden(hidesNavigationBackButton)
        .task(id: scheduleTarget.storageKey) {
            if dateRange.isEmpty {
                dateRange = buildDateRange(around: TimeProvider.now)
            }

            let now = TimeProvider.now
            if let todayIndex = dateRange.firstIndex(where: { calendar.isDate($0, inSameDayAs: now) }) {
                currentPage = todayIndex
            } else {
                ensureDateInRange(now)
                currentPage = dateRange.firstIndex(where: { calendar.isDate($0, inSameDayAs: now) }) ?? 0
            }

            await viewModel.loadSchedule(for: scheduleTarget, authenticatedStudent: student)
            guard !Task.isCancelled else { return }
            if scheduleTarget.kind == .student && scheduleTarget.id == authenticatedStudentId {
                LiveActivityManager.shared.updateLiveActivity(
                    events: viewModel.events,
                    currentTime: TimeProvider.now
                )
                if viewModel.errorMessage == nil {
                    await ReferralCoordinator.shared.maybeShowNudge(for: student)
                    if !ReferralCoordinator.shared.nudgeVisible {
                        ReviewPromptCoordinator.shared.maybePromptScheduleLoaded()
                    }
                } else {
                    ReviewPromptCoordinator.shared.reportRecentError()
                }
            }
        }
        .onDisappear {
            viewModel.cancelBackgroundTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task {
                await viewModel.loadSchedule(for: scheduleTarget, authenticatedStudent: student)
                if scheduleTarget.kind == .student && scheduleTarget.id == authenticatedStudentId {
                    LiveActivityManager.shared.updateLiveActivity(
                        events: viewModel.events,
                        currentTime: TimeProvider.now
                    )
                }
            }
        }
        .onReceive(minuteTimer) { _ in
            currentTime = TimeProvider.now
            if scheduleTarget.kind == .student && scheduleTarget.id == authenticatedStudentId {
                LiveActivityManager.shared.updateLiveActivity(
                    events: viewModel.events,
                    currentTime: currentTime
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                currentTime = TimeProvider.now
                if scheduleTarget.kind == .student && scheduleTarget.id == authenticatedStudentId {
                    LiveActivityManager.shared.updateLiveActivity(
                        events: viewModel.events,
                        currentTime: currentTime
                    )
                }
            }
        }
        // Recompute the cached tab height only when its inputs actually change,
        // instead of on every body render during scrolling.
        .onChange(of: viewModel.events) { _, _ in
            tabViewHeight = computeTabViewHeight()
        }
        .onChange(of: dateRange) { _, _ in
            tabViewHeight = computeTabViewHeight()
        }
        .onChange(of: settingsStore.calendarStyle) { _, _ in
            tabViewHeight = computeTabViewHeight()
        }
        .overlay(alignment: .top) {
            if viewModel.requiresReauthentication {
                authErrorBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.requiresReauthentication)
        .sheet(item: $selectedEvent) { event in
            LessonDetailSheet(
                event: event,
                authenticatedStudent: student,
                target: scheduleTarget,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $showingAddEvent) {
            AddPrivateEventView(
                student: student,
                schoolId: scheduleTarget.gymId,
                initialDate: selectedDate,
                onCreated: {
                    ReviewPromptCoordinator.shared.maybePrompt(.privateEventCreated)
                    Task {
                        await viewModel.refreshSchedule(
                            for: scheduleTarget,
                            authenticatedStudent: student,
                            weekOf: selectedDate,
                            force: true
                        )
                    }
                }
            )
        }
    }
}

// MARK: - Lesson Detail Sheet

struct LessonDetailSheet: View {
    let event: ScheduleEvent
    let authenticatedStudent: Student
    let target: SchedulableTarget
    @ObservedObject var viewModel: ScheduleViewModel

    @State private var content: LessonContent?
    @State private var isLoadingContent = true
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color {
        settingsStore.accentColor(for: event)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    // Info row
                    infoSection

                    Divider()

                    // Content
                    if isLoadingContent {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    } else if let content, (!content.items.isEmpty || content.teacherNote != nil) {
                        // Teacher note
                        if let note = content.teacherNote {
                            teacherNoteSection(note)
                        }

                        // Homework
                        if !content.homework.isEmpty {
                            contentSection(title: "Lektier", items: content.homework)
                        }

                        // Other content
                        if !content.otherContent.isEmpty {
                            contentSection(title: "Øvrigt indhold", items: content.otherContent)
                        }
                    } else {
                        Text("Ingen indhold")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
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
        .task {
            // Show cached content immediately
            content = await viewModel.cachedContent(for: event, target: target)
            isLoadingContent = content == nil

            // Always refresh silently in the background
            if let fresh = await viewModel.refreshContent(for: event, target: target, authenticatedStudent: authenticatedStudent) {
                content = fresh
            }
            isLoadingContent = false
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: SubjectMapper.iconName(for: event.title))
                .font(.title2)
                .foregroundColor(themeColor)
                .frame(width: 44, height: 44)
                .background(themeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SubjectMapper.displayName(for: event.title))
                        .font(.title3)
                        .fontWeight(.bold)

                    if event.status == .cancelled {
                        Text("Aflyst")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    } else if event.status == .changed {
                        Text("Ændret")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text(event.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 10) {
            infoRow(
                icon: "clock",
                text: event.isAllDay
                    ? "Hele dagen"
                    : "\(formatTime(event.startTime)) - \(formatTime(event.endTime))"
            )

            if let teacher = event.teacher, !teacher.isEmpty {
                infoRow(icon: "person", text: teacher)
            }

            if let room = event.room, !room.isEmpty {
                infoRow(icon: "mappin.and.ellipse", text: room)
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

    // MARK: - Teacher Note

    private func teacherNoteSection(_ note: String) -> some View {
        let noteTitle = event.id.hasPrefix("AFT") ? "Din note" : "Note fra lærer"
        return VStack(alignment: .leading, spacing: 8) {
            Label(noteTitle, systemImage: "quote.opening")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(note)
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Content Section

    private func contentSection(title: String, items: [LessonContentItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(items) { item in
                LessonContentItemView(item: item)
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: String) -> String {
        time.replacingOccurrences(of: ":", with: ".")
    }
}

/// Reports the calendar strip's top Y position (in the "scheduleView" coordinate space)
/// so the floating week-number badge can track it.
private struct StripTopPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

#Preview {
    ScheduleView(
        student: Student(studentId: "12345", gymId: 504, name: "Test Student"),
        authViewModel: AuthenticationViewModel()
    )
}
