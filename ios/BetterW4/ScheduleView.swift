//
//  ScheduleView.swift
//  BetterW4
//
//  The Timetable tab — the screen the app opens on.
//
//  It renders one W4 week at a time (`ScheduleWeek` → `ScheduleDay` → `TimetableEvent`, merged
//  from Academics and Extra Academics by `TimetableRepository`) through a horizontal day pager, a
//  week strip and one of two timeline styles.
//
//  The parts that are load-bearing rather than decorative:
//
//    * the pager swipes day by day and grows its range at the edges, so crossing a week boundary
//      loads the neighbouring week instead of stopping;
//    * cached data paints first and a refresh happens behind it — the spinner only appears when
//      there is genuinely nothing to show, and a failure leaves the week on screen with a banner;
//    * the "last updated" line is driven by `W4Loaded.freshness`, so an offline launch says how
//      old the grid is rather than pretending it is live;
//    * the now-line is computed from `TimeProvider.now` in Europe/Oslo against the week's own
//      `tt_start_hour`, never from W4's baked-in `#current_time` (plan D-10).
//

import Combine
import SwiftUI
import UIKit

struct ScheduleView: View {

    let student: Student

    @StateObject private var viewModel = ScheduleViewModel()
    @StateObject private var settingsStore = SettingsStore.shared

    @State private var dateRange: [Date] = []
    @State private var currentPage: Int = 0
    @State private var selectedEvent: TimetableEvent?
    @State private var currentTime = TimeProvider.now
    @State private var stripTopY: CGFloat = 0
    @State private var pagerHeight: CGFloat = 700
    @Environment(\.scenePhase) private var scenePhase

    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// W4 is one student's own timetable; there is no "someone else's schedule" surface to target.
    /// `authViewModel` is accepted and ignored so the tab shell can keep passing it.
    init(student: Student, authViewModel: AuthenticationViewModel? = nil) {
        self.student = student
    }

    // MARK: - Date range

    private func buildDateRange(around date: Date) -> [Date] {
        let monday = W4Dates.startOfWeek(containing: date)
        let start = W4Dates.adding(days: -14, to: monday)
        return (0..<28).map { W4Dates.startOfDay(W4Dates.adding(days: $0, to: start)) }
    }

    /// Grows the pager's range so the student can keep swiping past either end.
    private func extendRangeIfNeeded(around index: Int) {
        guard !dateRange.isEmpty else { return }

        if index <= 1, let first = dateRange.first {
            let newStart = W4Dates.adding(days: -7, to: first)
            let prepended = (0..<7).map { W4Dates.startOfDay(W4Dates.adding(days: $0, to: newStart)) }
            dateRange.insert(contentsOf: prepended, at: 0)
            currentPage += prepended.count
        } else if index >= dateRange.count - 2, let last = dateRange.last {
            let newStart = W4Dates.adding(days: 1, to: last)
            let appended = (0..<7).map { W4Dates.startOfDay(W4Dates.adding(days: $0, to: newStart)) }
            dateRange.append(contentsOf: appended)
        }
    }

    /// Makes sure `date` is inside `dateRange`, extending week by week until it is.
    private func ensureDateInRange(_ date: Date) {
        let target = W4Dates.startOfDay(date)

        if dateRange.isEmpty {
            dateRange = buildDateRange(around: target)
            return
        }

        var prepended = 0
        while let first = dateRange.first, target < first {
            let newStart = W4Dates.adding(days: -7, to: first)
            let week = (0..<7).map { W4Dates.startOfDay(W4Dates.adding(days: $0, to: newStart)) }
            dateRange.insert(contentsOf: week, at: 0)
            prepended += week.count
        }
        if prepended > 0 { currentPage += prepended }

        while let last = dateRange.last, target > last {
            let newStart = W4Dates.adding(days: 1, to: last)
            let week = (0..<7).map { W4Dates.startOfDay(W4Dates.adding(days: $0, to: newStart)) }
            dateRange.append(contentsOf: week)
        }
    }

    private func selectDate(_ date: Date, animated: Bool) {
        ensureDateInRange(date)
        guard let index = dateRange.firstIndex(where: { W4Dates.isSameDay($0, date) }) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { currentPage = index }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) { currentPage = index }
        }
    }

    private var selectedDate: Date {
        guard currentPage >= 0, currentPage < dateRange.count else { return viewModel.selectedDate }
        return dateRange[currentPage]
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

    private var preHeaderRevealHeight: CGFloat {
        headerLesson == nil ? 0 : 80
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

            headerLayer

            mainScrollLayer

            weekNumberBadge
                .zIndex(2)
        }
        .coordinateSpace(name: "scheduleView")
        .onPreferenceChange(StripTopPositionKey.self) { stripTopY = $0 }
        .navigationBarBackButtonHidden(true)
        .task {
            if dateRange.isEmpty {
                dateRange = buildDateRange(around: viewModel.today)
            }
            ensureDateInRange(viewModel.today)
            if let todayIndex = dateRange.firstIndex(where: { W4Dates.isSameDay($0, viewModel.today) }) {
                currentPage = todayIndex
            }

            await viewModel.onAppear()
            pagerHeight = computePagerHeight()

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
        .onReceive(minuteTimer) { _ in
            currentTime = TimeProvider.now
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            currentTime = TimeProvider.now
            Task { await viewModel.load(weekContaining: selectedDate) }
        }
        .onChange(of: viewModel.weeks) { _, _ in pagerHeight = computePagerHeight() }
        .onChange(of: dateRange) { _, _ in pagerHeight = computePagerHeight() }
        .onChange(of: settingsStore.calendarStyle) { _, _ in pagerHeight = computePagerHeight() }
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
            LessonDetailSheet(event: event)
        }
    }

    // MARK: - Scroll layer

    @ViewBuilder
    private var mainScrollLayer: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Color.clear.frame(height: preHeaderRevealHeight)

                Section {
                    timelineSectionContent
                } header: {
                    calendarStripHeader
                }
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refresh()
        }
        .mask {
            Rectangle()
                .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
                .ignoresSafeArea(edges: .bottom)
        }
        .zIndex(1)
    }

    @ViewBuilder
    private var calendarStripHeader: some View {
        CalendarStripView(
            selectedDate: selectedDate,
            weekNavigationEnabled: viewModel.weekNavigationAvailable,
            hasEvents: { date in !viewModel.events(on: date).isEmpty },
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
    private var timelineSectionContent: some View {
        VStack(spacing: 0) {
            Divider()

            freshnessBanner

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
                set: { if let newValue = $0 { currentPage = newValue } }
            ))
            .frame(height: pagerHeight)
            .onChange(of: currentPage) { _, newPage in
                guard newPage >= 0, newPage < dateRange.count else { return }
                let date = dateRange[newPage]
                extendRangeIfNeeded(around: newPage)
                Task { await viewModel.select(date: date) }
            }

            Color.clear.frame(height: 100)
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - One day

    @ViewBuilder
    private func daySchedulePage(for date: Date) -> some View {
        VStack(spacing: 0) {
            dayContextRow(for: date)

            AllDayEventsView(events: viewModel.allDayEvents(on: date)) { event in
                selectedEvent = event
            }

            if !viewModel.hasLoadedWeek(containing: date) {
                loadingDayPlaceholder
            } else if settingsStore.calendarStyle == .professional {
                ModernTimelineListView(
                    displayDate: date,
                    events: viewModel.timedEvents(on: date),
                    gridStartHour: viewModel.gridStartHour(for: date),
                    gridEndHour: viewModel.gridEndHour(for: date),
                    onEventTapped: { selectedEvent = $0 }
                )
                .padding(.trailing, 16)
            } else {
                TimelineListView(
                    displayDate: date,
                    events: viewModel.timedEvents(on: date),
                    gridStartHour: viewModel.gridStartHour(for: date),
                    onEventTapped: { selectedEvent = $0 }
                )
                .padding(.trailing, 16)
                .padding(.leading, 4)
            }

            Spacer(minLength: 0)
        }
    }

    /// W4's own day header: the rotation day, whether it is a no-classes day, and the Extra
    /// Academics line. All three are optional — an unloaded or bare day shows nothing.
    @ViewBuilder
    private func dayContextRow(for date: Date) -> some View {
        let rotation = viewModel.rotationDay(on: date)
        let eaNote = viewModel.extraAcademicsNote(on: date)
        let noClasses = viewModel.isNoClassesDay(date)

        if rotation != nil || eaNote != nil || noClasses {
            HStack(spacing: 8) {
                if let rotation {
                    Text(rotation)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                }

                if noClasses {
                    Text("No classes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if let eaNote {
                    Label(eaNote, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
    }

    /// The only spinner on this screen: a week with nothing cached behind it.
    @ViewBuilder
    private var loadingDayPlaceholder: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView()
                Text("Loading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Pull to load this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Banners

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
            .frame(maxWidth: .infinity)
            .alignmentGuide(.top) { $0[VerticalAlignment.center] }
            .offset(y: stripTopY)
            .allowsHitTesting(false)
    }

    // MARK: - Pager height

    /// The pager lives inside a vertical `ScrollView`, so it needs a fixed height that fits the
    /// longest day currently in range — otherwise a late lesson is clipped.
    private func computePagerHeight() -> CGFloat {
        let minHeight: CGFloat = 640
        let allDayStripHeight: CGFloat = 64
        let contextRowHeight: CGFloat = 40
        let footerHeight: CGFloat = 100

        var maxHeight = minHeight
        for date in dateRange {
            let layouts = calculateEventOverlapLayouts(for: viewModel.timedEvents(on: date))
            guard !layouts.isEmpty || !viewModel.allDayEvents(on: date).isEmpty else { continue }

            let origin = ScheduleTimelineGeometry.originMinutes(
                startHour: viewModel.gridStartHour(for: date),
                layouts: layouts
            )
            var height = ScheduleTimelineGeometry.contentHeight(layouts: layouts, originMinutes: origin)
            if !viewModel.allDayEvents(on: date).isEmpty { height += allDayStripHeight }
            height += contextRowHeight + footerHeight
            maxHeight = max(maxHeight, height)
        }
        return maxHeight
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

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color {
        event.accentColor(useSubjectColors: settingsStore.useSubjectColors)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    infoSection

                    if let detail = event.detailText {
                        Divider()
                        noteSection(title: "Details from W4", text: detail)
                    }

                    if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !notes.isEmpty {
                        Divider()
                        noteSection(title: "Note", text: notes)
                    }

                    if let href = event.href, let url = openInW4URL(href) {
                        Divider()
                        NavigationLink {
                            LessonW4PageView(url: url, title: event.displayTitle)
                        } label: {
                            Label("Open in W4", systemImage: "safari")
                                .font(.subheadline.weight(.semibold))
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
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: event.iconName)
                .font(.title2)
                .foregroundColor(themeColor)
                .frame(width: 44, height: 44)
                .background(themeColor.opacity(0.12))
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
                infoRow(icon: "person", text: teacher)
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

// MARK: - Chrome

/// Reports the calendar strip's top Y (in the "scheduleView" space) so the floating week badge
/// can track it.
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
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    NavigationStack {
        ScheduleView(student: .demo)
    }
}
