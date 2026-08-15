//
//  LiveActivityManager.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 27/02/2026.
//

import ActivityKit
import Foundation
import WidgetKit
#if os(iOS)
import BackgroundTasks
#endif

@MainActor
class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// APNs broadcast channel id. Server publishes here to nudge every subscribed
    /// activity (across all devices) to re-render — even when the app is suspended.
    private static let broadcastChannelID = "xdla10IQEfEAAC55miAfqQ=="

    /// Serializes every create/update/end so async ends can't race sync `Activity.request`.
    private var pendingTask: Task<Void, Never>?
    private var didRestore = false
    /// Monotonic `ContentState.version` so `Activity.update` always changes state.
    /// Timeline-driven Live Activity UI is unreliable (iOS 18+); we refresh on this tick instead.
    private var contentStateSerial = 0

    /// Most recent events we pushed, so boundary fires and BG tasks can re-run the update
    /// without the ScheduleView having to hand them back.
    private var lastEvents: [ScheduleEvent] = []

    private init() {}

    // MARK: - Public API

    /// Called every ~60 seconds from ScheduleView's timer, and on schedule load.
    /// Starts the live activity with today's full lesson list if not already running,
    /// or restarts it if the lesson list has changed (e.g. cancellation).
    func updateLiveActivity(events: [ScheduleEvent], currentTime: Date) {
        enqueue { [weak self] in
            await self?.performUpdate(events: events, currentTime: currentTime)
        }
    }

    func endActivity() {
        enqueue { [weak self] in
            await self?.endAllActivities()
            LiveActivityBoundaryScheduler.shared.cancel()
            #if os(iOS)
            LiveActivityBackgroundRefresh.cancel()
            #endif
            self?.lastEvents = []
        }
    }

    #if os(iOS)
    /// Handles a BGAppRefreshTask fire. Bumps the active activity's state so the widget
    /// re-renders with the now-current lesson, then re-submits the next BG refresh request.
    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        enqueue { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }

            await self.bumpActiveActivities()
            self.submitNextBackgroundRefresh()

            task.setTaskCompleted(success: true)
        }
    }
    #endif

    // MARK: - Serialization

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingTask
        pendingTask = Task { @MainActor in
            _ = await previous?.value
            await work()
        }
    }

    // MARK: - Work items

    private func performUpdate(events: [ScheduleEvent], currentTime: Date) async {
        await restoreIfNeeded()

        let calendar = Calendar.current
        let todaysEvents = events.filter {
            calendar.isDate($0.date, inSameDayAs: currentTime)
                && $0.status != .cancelled
                && !$0.isAllDay
        }
        let lessons = todaysEvents.map { embeddedLesson(from: $0) }
        let variant = LiveActivityVariant.current.rawValue

        let tempAttrs = LectioActivityAttributes(todaysLessons: lessons, variant: variant)
        guard tempAttrs.currentOrUpcomingLesson(at: currentTime) != nil else {
            await endAllActivities()
            LiveActivityBoundaryScheduler.shared.cancel()
            #if os(iOS)
            LiveActivityBackgroundRefresh.cancel()
            #endif
            lastEvents = events
            persistScheduleForWidget(todaysEvents: todaysEvents)
            return
        }

        lastEvents = events

        let newIds = Set(lessons.map(\.id))
        let systemActivities = Activity<LectioActivityAttributes>.activities

        // Reuse an existing activity if exactly one matches the desired session.
        let matching = systemActivities.filter {
            $0.activityState == .active
                && $0.attributes.variant == variant
                && Set($0.attributes.todaysLessons.map(\.id)) == newIds
        }

        if let reusable = matching.first {
            // End any extras (including any non-matching orphans).
            for a in systemActivities where a.id != reusable.id {
                await endQuietly(a)
            }
            let newState = makeNextContentState()
            await reusable.update(
                ActivityContent(
                    state: newState,
                    staleDate: nil
                )
            )
        } else {
            // Nothing matches — end every orphan, then start fresh.
            await endAllActivities()
            startFreshActivity(lessons: lessons, variant: variant)
        }

        persistScheduleForWidget(todaysEvents: todaysEvents)
        rescheduleBoundaryAndBackgroundFires(lessons: lessons)
    }

    // MARK: - Primitives

    private func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true

        let activities = Activity<LectioActivityAttributes>.activities
            .filter { $0.activityState == .active }

        // If we come back to multiple orphans after a termination we can't tell which
        // is authoritative — end all; the next updateLiveActivity tick will create one.
        if activities.count > 1 {
            for a in activities {
                await endQuietly(a)
            }
        }
        // If count == 1 we simply adopt it implicitly: later reconciliation will either
        // reuse it (same lessons+variant) or replace it.
    }

    private func endAllActivities() async {
        for a in Activity<LectioActivityAttributes>.activities {
            await endQuietly(a)
        }
    }

    private func makeNextContentState() -> LectioActivityAttributes.ContentState {
        contentStateSerial += 1
        return LectioActivityAttributes.ContentState(version: contentStateSerial)
    }

    private func endQuietly(_ activity: Activity<LectioActivityAttributes>) async {
        await activity.end(
            ActivityContent(
                state: LectioActivityAttributes.ContentState(version: 0),
                staleDate: nil
            ),
            dismissalPolicy: .immediate
        )
    }

    /// Requests a new activity, with a last-chance reuse check in case something
    /// slipped past the queue (defense in depth).
    private func startFreshActivity(lessons: [LectioActivityAttributes.EmbeddedLesson], variant: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let ids = Set(lessons.map(\.id))
        if Activity<LectioActivityAttributes>.activities.contains(where: {
            $0.activityState == .active
                && $0.attributes.variant == variant
                && Set($0.attributes.todaysLessons.map(\.id)) == ids
        }) {
            return
        }

        let attributes = LectioActivityAttributes(todaysLessons: lessons, variant: variant)
        let state = makeNextContentState()

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: .channel(Self.broadcastChannelID)
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    private func embeddedLesson(from event: ScheduleEvent) -> LectioActivityAttributes.EmbeddedLesson {
        LectioActivityAttributes.EmbeddedLesson(
            id: event.id,
            subjectName: SubjectMapper.displayName(for: event.title),
            subjectIconName: SubjectMapper.iconName(for: event.title),
            subjectColorHue: SubjectMapper.colorHue(for: event.title),
            room: event.room,
            teacher: event.teacher,
            startTime: event.startTime,
            endTime: event.endTime,
            date: event.date
        )
    }

    private func persistScheduleForWidget(todaysEvents: [ScheduleEvent]) {
        let shared = todaysEvents.map { e in
            SharedLesson(
                id: e.id,
                title: e.title,
                displayName: SubjectMapper.displayName(for: e.title),
                iconName: SubjectMapper.iconName(for: e.title),
                colorHue: SubjectMapper.colorHue(for: e.title),
                room: e.room,
                teacher: e.teacher,
                startTime: e.startTime,
                endTime: e.endTime,
                status: e.status.rawValue,
                date: e.date
            )
        }
        if SharedScheduleData.save(lessons: shared) {
            WidgetCenter.shared.reloadTimelines(ofKind: "LessonTimelineWidget")
        }
    }

    // MARK: - Boundary + background scheduling

    /// Schedules a precise in-process fire at every remaining lesson start/end for today,
    /// plus a BGAppRefreshTask request for the earliest boundary (as a backup for when
    /// the app is suspended).
    private func rescheduleBoundaryAndBackgroundFires(lessons: [LectioActivityAttributes.EmbeddedLesson]) {
        let now = Date()
        let boundaries = lessons.flatMap { lesson in
            [
                LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date),
                LectioActivityAttributes.dateFromTimeString(lesson.endTime, on: lesson.date)
            ]
        }

        LiveActivityBoundaryScheduler.shared.reschedule(boundaries: boundaries) { [weak self] in
            guard let self else { return }
            self.updateLiveActivity(events: self.lastEvents, currentTime: Date())
        }

        #if os(iOS)
        if let nextBoundary = boundaries.filter({ $0 > now }).min() {
            // Request the system to wake us up ~30 seconds before the next boundary. The
            // actual wake-up time is up to iOS; this is a best-effort hint.
            let hint = nextBoundary.addingTimeInterval(-30)
            let earliest = hint > now ? hint : now.addingTimeInterval(60)
            LiveActivityBackgroundRefresh.schedule(earliestAt: earliest)
        } else {
            LiveActivityBackgroundRefresh.cancel()
        }
        #endif
    }

    /// Called from a BGAppRefreshTask. Bumps every active activity so the widget
    /// re-evaluates `currentOrUpcomingLesson(at: Date())`, flipping to the right lesson.
    private func bumpActiveActivities() async {
        for activity in Activity<LectioActivityAttributes>.activities where activity.activityState == .active {
            let newState = makeNextContentState()
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    // MARK: - Push observation (debug)

    /// Spawns observers that print whenever an activity's content state changes,
    /// including OS-applied updates from the APNs broadcast channel push. Call once
    /// at app launch.
    func startObservingContentUpdates() {
        Task { @MainActor in
            for activity in Activity<LectioActivityAttributes>.activities {
                self.observeContentUpdates(activity)
            }
            for await activity in Activity<LectioActivityAttributes>.activityUpdates {
                self.observeContentUpdates(activity)
            }
        }
    }

    private func observeContentUpdates(_ activity: Activity<LectioActivityAttributes>) {
        let id = activity.id
        print("📡 [LiveActivity] observing content updates for activity \(id)")
        Task { @MainActor in
            for await content in activity.contentUpdates {
                let info = Self.describe(state: content.state)
                let stale = content.staleDate.map { "\($0)" } ?? "nil"
                print("📡 [LiveActivity] received push notif with info: \(info) staleDate=\(stale) activity=\(id)")
            }
            print("📡 [LiveActivity] content stream ended for \(id)")
        }
        Task { @MainActor in
            for await state in activity.activityStateUpdates {
                print("📡 [LiveActivity] activity \(id) state changed → \(state)")
            }
        }
    }

    private static func describe(state: LectioActivityAttributes.ContentState) -> String {
        if let data = try? JSONEncoder().encode(state),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "version=\(state.version)"
    }

    /// Re-arm the next BGAppRefreshTask using the boundaries of any currently active
    /// activity. Called after handling a BG task fire so we keep getting woken up.
    private func submitNextBackgroundRefresh() {
        #if os(iOS)
        let now = Date()
        let boundaries = Activity<LectioActivityAttributes>.activities
            .filter { $0.activityState == .active }
            .flatMap { $0.attributes.lessonTransitionDates }

        if let nextBoundary = boundaries.filter({ $0 > now }).min() {
            let hint = nextBoundary.addingTimeInterval(-30)
            let earliest = hint > now ? hint : now.addingTimeInterval(60)
            LiveActivityBackgroundRefresh.schedule(earliestAt: earliest)
        }
        #endif
    }
}
