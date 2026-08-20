//
//  NotificationScheduler.swift
//  BetterW4
//
//  Local notifications for lessons and assessments. Everything here is scheduled *ahead of time*
//  from data the app has already fetched and cached — `UNCalendarNotificationTrigger` fires while
//  the app is not running, so there is no polling, no `BGTaskScheduler`, and no `UIBackgroundModes`
//  entitlement behind any of it.
//
//  That constraint is the design, not a shortcut. It is also why only two of the four toggles this
//  screen used to offer survive:
//
//    * **Lesson reminder** and **Assessments due** are derivable from a timetable week and an
//      assessments month the student has already loaded. The app knows the fire dates the moment
//      it parses the page, so it can hand iOS a list and stop thinking about it.
//    * **New mail** and **Timetable changes** are *not*. Answering "is there new mail?" means
//      fetching W4 on a schedule and diffing, which needs background refresh the app does not
//      implement. Those toggles were removed rather than left switched on over nothing — the
//      Settings footer used to promise "BetterW4 checks W4 in the background", which was false.
//
//  The pure part (`NotificationPlanner`) takes values and a clock and returns what *should* be
//  scheduled. It touches no framework, reads no singleton and is what the tests drive. The
//  stateful part (`NotificationScheduler`) is the thin adapter that talks to
//  `UNUserNotificationCenter`.
//

import Foundation
import UserNotifications

// MARK: - Preferences

/// The subset of `SettingsStore` the planner needs, lifted into a value so the planner can be
/// tested without a singleton or a `UserDefaults` suite.
struct NotificationPreferences: Equatable, Sendable {
    /// The master switch. When off, nothing is scheduled regardless of the flags below.
    var enabled: Bool
    var lessonReminders: Bool
    /// How far ahead of the lesson's start the reminder fires.
    var lessonLeadMinutes: Int
    var assessmentReminders: Bool

    init(
        enabled: Bool,
        lessonReminders: Bool,
        lessonLeadMinutes: Int,
        assessmentReminders: Bool
    ) {
        self.enabled = enabled
        self.lessonReminders = lessonReminders
        self.lessonLeadMinutes = lessonLeadMinutes
        self.assessmentReminders = assessmentReminders
    }

    /// Everything off — the state the app is in before the student opts in, and the state the
    /// planner is given when notification permission has not been granted.
    static let off = NotificationPreferences(
        enabled: false,
        lessonReminders: false,
        lessonLeadMinutes: 10,
        assessmentReminders: false
    )
}

// MARK: - Planned notification

/// One notification the planner decided to schedule.
///
/// `id` is stable across replans: the same lesson always produces the same identifier, so
/// re-scheduling an unchanged week overwrites its own requests instead of duplicating them.
struct PlannedNotification: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

// MARK: - Planner

/// Turns loaded timetable and assessment data into the list of notifications that should exist.
///
/// Pure: no clock of its own, no framework, no I/O. `now` is always passed in.
enum NotificationPlanner {
    /// Every identifier this app schedules starts with this, so the scheduler can clear its own
    /// requests without touching anything else that might one day live in the same namespace.
    static let identifierPrefix = "w4.reminder."

    /// iOS keeps only the **64 soonest** pending local notifications per app and silently drops
    /// the rest, so the plan is sorted by fire date and truncated here rather than letting the
    /// system choose which reminders to lose. The headroom below 64 is deliberate.
    static let maximumScheduled = 60

    /// Assessment reminders fire the evening before the due day, at this Oslo hour.
    ///
    /// `Assessment.dueDate` is midnight on the due day, which is useless as a fire time — a
    /// notification at 00:00 is a notification nobody reads. The evening before is when a student
    /// can still act on it.
    static let assessmentReminderHour = 18

    static func plan(
        lessons: [TimetableEvent],
        assessments: [Assessment],
        preferences: NotificationPreferences,
        now: Date
    ) -> [PlannedNotification] {
        guard preferences.enabled else { return [] }

        var planned: [PlannedNotification] = []
        if preferences.lessonReminders {
            planned += lessonReminders(for: lessons, lead: preferences.lessonLeadMinutes, now: now)
        }
        if preferences.assessmentReminders {
            planned += assessmentReminders(for: assessments, now: now)
        }

        // A lesson can arrive from both the Academics and the Extra Academics grid, and the same
        // week can be loaded under two keys. Keep the first of each id, then order by when it
        // fires so the truncation below keeps the *soonest* reminders.
        var seen = Set<String>()
        return planned
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
            .prefix(maximumScheduled)
            .map { $0 }
    }

    // MARK: Lessons

    private static func lessonReminders(
        for lessons: [TimetableEvent],
        lead: Int,
        now: Date
    ) -> [PlannedNotification] {
        lessons.compactMap { lesson -> PlannedNotification? in
            // An all-day banner has no start to count back from, and an unplaceable block has no
            // `start` at all — the parser leaves it nil rather than inventing one.
            guard !lesson.isAllDay, let start = lesson.start else { return nil }

            // Reminding somebody to attend a lesson W4 has cancelled is worse than saying nothing.
            guard lesson.status != .cancelled else { return nil }

            let fireDate = start.addingTimeInterval(-Double(lead) * 60)
            guard fireDate > now else { return nil }

            return PlannedNotification(
                id: identifierPrefix + "lesson." + lesson.id,
                title: lesson.title,
                body: lessonBody(for: lesson, start: start, lead: lead),
                fireDate: fireDate
            )
        }
    }

    private static func lessonBody(for lesson: TimetableEvent, start: Date, lead: Int) -> String {
        var parts = ["Starts in \(lead) min (\(W4Dates.formatTime(start)))"]
        if let room = lesson.room?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty {
            parts.append("Room \(room)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Assessments

    private static func assessmentReminders(
        for assessments: [Assessment],
        now: Date
    ) -> [PlannedNotification] {
        assessments.compactMap { assessment -> PlannedNotification? in
            guard let dueDate = assessment.dueDate else { return nil }

            // Work the student has already marked done is not work to remind them about.
            guard !assessment.isDone else { return nil }

            // The evening before. If that moment has already passed there is no second chance —
            // firing "due tomorrow" on the due day itself would be a lie, and firing immediately
            // would turn every refresh into a burst of notifications about old work.
            let eveningBefore = W4Dates.date(
                onDayOf: W4Dates.adding(days: -1, to: dueDate),
                minutesFromMidnight: assessmentReminderHour * 60
            )
            guard eveningBefore > now else { return nil }

            return PlannedNotification(
                id: identifierPrefix + "assessment." + assessment.id,
                title: assessment.title,
                body: assessmentBody(for: assessment),
                fireDate: eveningBefore
            )
        }
    }

    private static func assessmentBody(for assessment: Assessment) -> String {
        var parts = ["Due tomorrow"]
        let subject = assessment.classCode ?? assessment.subject
        if let subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            parts.append(subject)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Scheduler

/// Keeps `UNUserNotificationCenter`'s pending requests in step with the latest plan.
///
/// The two `update…` entry points exist because lessons and assessments arrive from different
/// screens at different times. Each stores its half of the input and replans from both, so the
/// Timetable tab loading a week cannot wipe the Assessments tab's reminders.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center: UNUserNotificationCenter?
    private let now: () -> Date

    /// The most recent snapshot of each input. Replaced wholesale, never merged: a week the
    /// student navigated away from should stop producing reminders.
    private var lessons: [TimetableEvent] = []
    private var assessments: [Assessment] = []

    /// Demo mode must not schedule anything. A reviewer exploring the demo should not find their
    /// lock screen filling with reminders about a student who does not exist.
    private var isDemo = false

    init(center: UNUserNotificationCenter? = .current(), now: @escaping () -> Date = Date.init) {
        self.center = center
        self.now = now
    }

    // MARK: Inputs

    func updateLessons(_ lessons: [TimetableEvent], isDemo: Bool) async {
        self.isDemo = isDemo
        self.lessons = isDemo ? [] : lessons
        await reschedule()
    }

    func updateAssessments(_ assessments: [Assessment], isDemo: Bool) async {
        self.isDemo = isDemo
        self.assessments = isDemo ? [] : assessments
        await reschedule()
    }

    /// Called when a notification preference changes, so turning a toggle off clears its
    /// notifications immediately rather than at the next timetable load.
    func preferencesChanged() async {
        await reschedule()
    }

    /// Drops every scheduled reminder. Called on sign-out: the next person to hold the phone must
    /// not get notifications about the previous student's lessons.
    func clearAll() async {
        lessons = []
        assessments = []
        guard let center else { return }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers(in: pending))
    }

    // MARK: Scheduling

    private func reschedule() async {
        guard let center else { return }

        let preferences = await effectivePreferences()
        let plan = NotificationPlanner.plan(
            lessons: lessons,
            assessments: assessments,
            preferences: preferences,
            now: now()
        )

        // Clear ours first. `plan` is the complete desired state, so anything pending that is not
        // in it — a lesson that moved, an assessment just marked done — has to go.
        let pending = await center.pendingNotificationRequests()
        let obsolete = ownedIdentifiers(in: pending)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }

        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            let components = W4Dates.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// The student's preferences, forced to `.off` unless the system has actually granted
    /// permission. Without this the app would happily "schedule" reminders that iOS discards,
    /// and Settings would claim reminders are on while none could ever appear.
    private func effectivePreferences() async -> NotificationPreferences {
        guard !isDemo, let center else { return .off }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return .off }

        let store = SettingsStore.shared
        return NotificationPreferences(
            enabled: store.notificationsEnabled,
            lessonReminders: store.notifyLessonReminder,
            lessonLeadMinutes: store.lessonReminderMinutes.rawValue,
            assessmentReminders: store.notifyAssessments
        )
    }

    private func ownedIdentifiers(in requests: [UNNotificationRequest]) -> [String] {
        requests
            .map(\.identifier)
            .filter { $0.hasPrefix(NotificationPlanner.identifierPrefix) }
    }
}
