//
//  NotificationRefresh.swift
//  BetterW4
//
//  Fetches timetable / assessments / trips, diffs against the last snapshot,
//  and posts local notifications. First run only seeds the snapshot.
//

import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

enum NotificationRefresh {

    private static let snapshotPrefix = "w4.notify.snapshot."
    private static let seededPrefix = "w4.notify.seeded."

    #if os(iOS)
    static func handle(_ task: BGAppRefreshTask) {
        NotificationBackgroundRefresh.schedule()
        let work = Task {
            await run()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
    #endif

    @MainActor
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            SettingsStore.shared.saveNotificationsEnabled(granted)
            if granted {
                NotificationBackgroundRefresh.schedule()
            }
        case .authorized, .provisional, .ephemeral:
            if SettingsStore.shared.notificationsEnabled {
                NotificationBackgroundRefresh.schedule()
            }
        default:
            break
        }
    }

    @MainActor
    static func run() async {
        let settings = SettingsStore.shared
        guard settings.notificationsEnabled else { return }
        let watchTimetable = settings.notifyTimetableChanges
        let watchAssessments = settings.notifyAssessments
        let watchTrips = settings.notifyTrips
        guard watchTimetable || watchAssessments || watchTrips else { return }

        guard let context = W4RequestContext.current(), !context.isDemo else { return }

        let defaults = UserDefaults.standard
        let snapKey = snapshotPrefix + context.uwcId
        let previous = NotificationDiff.decode(defaults.stringArray(forKey: snapKey) ?? [])
        let primedLessons = defaults.bool(forKey: seededPrefix + "tt." + context.uwcId)
        let primedAssessments = defaults.bool(forKey: seededPrefix + "asg." + context.uwcId)
        let primedTrips = defaults.bool(forKey: seededPrefix + "trip." + context.uwcId)
        let now = TimeProvider.now

        var nextLessons = previous.lessons
        var nextAssessments = previous.assessments
        var nextTrips = previous.trips
        var fetchedLessons = false
        var fetchedAssessments = false
        var fetchedTrips = false

        if watchTimetable {
            do {
                var events: [TimetableEvent] = []
                let week = try await TimetableRepository.shared.week(
                    containing: now,
                    policy: .alwaysRefresh
                )
                events += week.value.days.flatMap(\.events)
                if needsNextWeek(now: now) {
                    let later = W4Dates.adding(days: 7, to: now)
                    let nextWeek = try await TimetableRepository.shared.week(
                        containing: later,
                        policy: .alwaysRefresh
                    )
                    events += nextWeek.value.days.flatMap(\.events)
                }
                nextLessons = NotificationDiff.watchLessons(events, now: now)
                fetchedLessons = true
            } catch {
                if isSessionExpired(error) { return }
            }
        }

        if watchAssessments {
            do {
                let loaded = try await AssessmentRepository.shared.assessments(
                    for: .current(now),
                    forceRefresh: true,
                    priority: .opportunistic
                )
                nextAssessments = NotificationDiff.watchAssessments(loaded.value)
                fetchedAssessments = true
            } catch {
                if isSessionExpired(error) { return }
            }
        }

        if watchTrips {
            do {
                let loaded = try await TripRepository().loadTrips(
                    forceRefresh: true,
                    priority: .opportunistic
                )
                nextTrips = NotificationDiff.watchTrips(loaded.value.trips)
                fetchedTrips = true
            } catch {
                if isSessionExpired(error) { return }
            }
        }

        let next = NotificationDiff.Snapshot(
            lessons: nextLessons,
            assessments: nextAssessments,
            trips: nextTrips
        )
        defaults.set(NotificationDiff.encode(next), forKey: snapKey)
        if fetchedLessons { defaults.set(true, forKey: seededPrefix + "tt." + context.uwcId) }
        if fetchedAssessments { defaults.set(true, forKey: seededPrefix + "asg." + context.uwcId) }
        if fetchedTrips { defaults.set(true, forKey: seededPrefix + "trip." + context.uwcId) }

        if watchTimetable && primedLessons {
            for change in NotificationDiff.diffLessons(previous: previous.lessons, current: nextLessons, now: now) {
                let title: String
                switch change.kind {
                case .cancelled: title = "Lesson cancelled"
                case .moved: title = "Lesson moved"
                case .room: title = "Room changed"
                case .changed: title = "Timetable changed"
                }
                let body = [change.title, change.timeLabel, change.detail]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                await post(id: "tt-\(change.identity)", title: title, body: body, thread: "timetable")
            }
        }
        if watchAssessments && primedAssessments {
            for change in NotificationDiff.diffAssessments(previous: previous.assessments, current: nextAssessments) {
                let title = change.kind == .new ? "New assessment" : "Assessment overdue"
                let body = [change.title, change.subtitle]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                await post(id: "asg-\(change.id)", title: title, body: body, thread: "assessments")
            }
        }
        if watchTrips && primedTrips {
            for change in NotificationDiff.diffTrips(previous: previous.trips, current: nextTrips) {
                let title: String
                switch change.kind {
                case .new:
                    title = "New trip"
                case .status:
                    title = "Trip \(tripStatusLabel(change.status))"
                }
                await post(id: "trip-\(change.id)", title: title, body: change.name, thread: "trips")
            }
        }
    }

    private static func needsNextWeek(now: Date) -> Bool {
        let weekday = W4Dates.calendar.component(.weekday, from: now)
        // Gregorian Sunday=1 … Saturday=7. Friday=6, Saturday=7, Sunday=1.
        if weekday == 1 || weekday >= 6 { return true }
        let weekEnd = W4Dates.adding(days: 8 - ((weekday + 5) % 7), to: W4Dates.startOfDay(now))
        return now.addingTimeInterval(horizonSeconds) >= weekEnd
    }

    private static var horizonSeconds: TimeInterval { NotificationDiff.horizonHours * 3600 }

    private static func isSessionExpired(_ error: Error) -> Bool {
        if case .sessionExpired = error as? W4Error { return true }
        return false
    }

    private static func tripStatusLabel(_ status: String) -> String {
        switch status {
        case "pendingConfirmation", "pending": return "pending confirmation"
        case "approved": return "approved"
        case "cancelled": return "cancelled"
        case "planning": return "planning"
        default: return status
        }
    }

    private static func post(id: String, title: String, body: String, thread: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
