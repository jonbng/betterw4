//
//  NotificationPlannerTests.swift
//  BetterW4Tests
//
//  `NotificationPlanner` is the only part of the notification feature with rules worth asserting,
//  and it is pure by design so that it can be driven here without `UNUserNotificationCenter`, a
//  permission prompt or a clock. Every test passes `now` explicitly.
//
//  The rules under test are the ones that would embarrass the app on a student's lock screen:
//
//    * nothing is scheduled unless the student asked for it;
//    * a cancelled lesson never produces "starts in 10 min";
//    * an assessment already marked done never nags;
//    * nothing is ever scheduled in the past;
//    * the same lesson seen twice produces one reminder, not two;
//    * the plan is capped below iOS's 64-request limit, keeping the *soonest* reminders, because
//      past that limit the system silently discards whichever it likes.
//

import XCTest
@testable import BetterW4

final class NotificationPlannerTests: XCTestCase {

    // MARK: - Fixtures

    /// 10:00 Oslo on Monday 17 August 2026. Every date in this file is relative to it.
    private var now: Date {
        W4Dates.date(year: 2026, month: 8, day: 17, hour: 10, minute: 0)!
    }

    private func lesson(
        id: String = "ac-1",
        title: String = "Biology HL",
        start: Date?,
        status: EventStatus = .normal,
        room: String? = "B12",
        isAllDay: Bool = false
    ) -> TimetableEvent {
        TimetableEvent(
            id: id,
            title: title,
            source: .academics,
            start: start,
            end: start?.addingTimeInterval(3600),
            date: W4Dates.startOfDay(start ?? now),
            room: room,
            status: status,
            isAllDay: isAllDay
        )
    }

    private func assessment(
        id: String = "class:1",
        title: String = "Paper 2",
        dueDate: Date?,
        status: AssessmentStatus = .pending
    ) -> Assessment {
        Assessment(
            id: id,
            rawId: "1",
            kind: .classAssigned,
            rawKind: "class",
            title: title,
            classCode: "BIO HL",
            dueDate: dueDate,
            status: status,
            rawStatus: status.rawValue
        )
    }

    private func preferences(
        enabled: Bool = true,
        lessons: Bool = true,
        lead: Int = 10,
        assessments: Bool = true
    ) -> NotificationPreferences {
        NotificationPreferences(
            enabled: enabled,
            lessonReminders: lessons,
            lessonLeadMinutes: lead,
            assessmentReminders: assessments
        )
    }

    // MARK: - The master switch

    func testNothingIsScheduledWhileNotificationsAreOff() {
        let soon = now.addingTimeInterval(3600)
        let plan = NotificationPlanner.plan(
            lessons: [lesson(start: soon)],
            assessments: [assessment(dueDate: W4Dates.adding(days: 3, to: now))],
            preferences: preferences(enabled: false),
            now: now
        )
        XCTAssertTrue(plan.isEmpty, "the master switch must veto both categories")
    }

    func testEachCategoryIsIndependentlySwitchable() {
        let soon = now.addingTimeInterval(3600)
        let due = W4Dates.startOfDay(W4Dates.adding(days: 3, to: now))

        let lessonsOnly = NotificationPlanner.plan(
            lessons: [lesson(start: soon)],
            assessments: [assessment(dueDate: due)],
            preferences: preferences(lessons: true, assessments: false),
            now: now
        )
        XCTAssertEqual(lessonsOnly.count, 1)
        XCTAssertTrue(lessonsOnly[0].id.contains("lesson"))

        let assessmentsOnly = NotificationPlanner.plan(
            lessons: [lesson(start: soon)],
            assessments: [assessment(dueDate: due)],
            preferences: preferences(lessons: false, assessments: true),
            now: now
        )
        XCTAssertEqual(assessmentsOnly.count, 1)
        XCTAssertTrue(assessmentsOnly[0].id.contains("assessment"))
    }

    // MARK: - Lessons

    func testLessonReminderFiresTheConfiguredLeadBeforeTheStart() {
        let start = now.addingTimeInterval(3600)
        let plan = NotificationPlanner.plan(
            lessons: [lesson(start: start)],
            assessments: [],
            preferences: preferences(lead: 30),
            now: now
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate, start.addingTimeInterval(-1800))
        XCTAssertEqual(plan[0].title, "Biology HL")
        XCTAssertTrue(plan[0].body.contains("30 min"), plan[0].body)
        XCTAssertTrue(plan[0].body.contains("B12"), "the room is the single most useful thing to carry")
    }

    /// The whole point of the lead time is that it can push the fire date into the past. A lesson
    /// that starts in five minutes must not schedule a reminder for five minutes ago.
    func testALessonStartingSoonerThanTheLeadIsSkipped() {
        let plan = NotificationPlanner.plan(
            lessons: [lesson(start: now.addingTimeInterval(300))],
            assessments: [],
            preferences: preferences(lead: 10),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testLessonsAlreadyPastAreSkipped() {
        let plan = NotificationPlanner.plan(
            lessons: [lesson(start: now.addingTimeInterval(-3600))],
            assessments: [],
            preferences: preferences(),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    /// Reminding somebody to go to a lesson W4 has cancelled is worse than saying nothing at all.
    func testCancelledLessonsAreSkipped() {
        let plan = NotificationPlanner.plan(
            lessons: [lesson(start: now.addingTimeInterval(3600), status: .cancelled)],
            assessments: [],
            preferences: preferences(),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    /// An all-day banner has no start instant to count back from. The parser leaves `start` nil
    /// rather than inventing midnight, and the planner must not invent it either.
    func testAllDayAndUnplaceableLessonsAreSkipped() {
        let plan = NotificationPlanner.plan(
            lessons: [
                lesson(id: "ac-allday", start: now.addingTimeInterval(3600), isAllDay: true),
                lesson(id: "ac-nostart", start: nil)
            ],
            assessments: [],
            preferences: preferences(),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Assessments

    func testAssessmentReminderFiresTheEveningBeforeTheDueDay() {
        // Due Thursday 20 August; the reminder belongs at 18:00 on Wednesday the 19th.
        let due = W4Dates.date(year: 2026, month: 8, day: 20)!
        let plan = NotificationPlanner.plan(
            lessons: [],
            assessments: [assessment(dueDate: due)],
            preferences: preferences(),
            now: now
        )

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate, W4Dates.date(year: 2026, month: 8, day: 19, hour: 18, minute: 0)!)
        XCTAssertEqual(plan[0].title, "Paper 2")
        XCTAssertTrue(plan[0].body.contains("Due tomorrow"), plan[0].body)
        XCTAssertTrue(plan[0].body.contains("BIO HL"), plan[0].body)
    }

    func testAssessmentsAlreadyMarkedDoneAreSkipped() {
        let due = W4Dates.date(year: 2026, month: 8, day: 20)!
        let plan = NotificationPlanner.plan(
            lessons: [],
            assessments: [assessment(dueDate: due, status: .done)],
            preferences: preferences(),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testAssessmentsWithNoDueDateAreSkipped() {
        let plan = NotificationPlanner.plan(
            lessons: [],
            assessments: [assessment(dueDate: nil)],
            preferences: preferences(),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }

    /// Due tomorrow, but 18:00 yesterday has already gone. There is no second chance on purpose:
    /// firing "due tomorrow" late would be wrong, and firing it immediately would turn every
    /// refresh into a burst of notifications about work the student already knows about.
    func testAnAssessmentWhoseEveningHasPassedIsSkipped() {
        let due = W4Dates.date(year: 2026, month: 8, day: 18)!   // tomorrow; 18:00 on the 17th…
        let evening = W4Dates.date(year: 2026, month: 8, day: 17, hour: 19, minute: 0)!  // …is past
        let plan = NotificationPlanner.plan(
            lessons: [],
            assessments: [assessment(dueDate: due)],
            preferences: preferences(),
            now: evening
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Shape of the plan

    /// The same lesson can arrive from both the Academics and the Extra Academics grid, and the
    /// same week can be loaded under two keys. One reminder, not two.
    func testDuplicateIdsCollapseToOneReminder() {
        let start = now.addingTimeInterval(3600)
        let plan = NotificationPlanner.plan(
            lessons: [lesson(id: "ac-7", start: start), lesson(id: "ac-7", start: start)],
            assessments: [],
            preferences: preferences(),
            now: now
        )
        XCTAssertEqual(plan.count, 1)
    }

    func testIdentifiersAreStableAcrossReplansAndCarryTheOwnershipPrefix() {
        let start = now.addingTimeInterval(3600)
        let first = NotificationPlanner.plan(
            lessons: [lesson(id: "ac-7", start: start)],
            assessments: [],
            preferences: preferences(),
            now: now
        )
        let second = NotificationPlanner.plan(
            lessons: [lesson(id: "ac-7", start: start)],
            assessments: [],
            preferences: preferences(),
            now: now
        )

        XCTAssertEqual(first.map(\.id), second.map(\.id), "an unchanged week must not churn identifiers")
        XCTAssertTrue(
            first[0].id.hasPrefix(NotificationPlanner.identifierPrefix),
            "the scheduler clears by prefix; an id without it would never be cleaned up"
        )
    }

    /// iOS keeps only the 64 soonest pending requests and drops the rest without telling anyone.
    /// The planner truncates first so the ones that survive are the ones that matter.
    func testThePlanIsCappedAndKeepsTheSoonestReminders() {
        let lessons = (0..<200).map { index in
            lesson(id: "ac-\(index)", start: now.addingTimeInterval(Double(3600 + index * 600)))
        }
        let plan = NotificationPlanner.plan(
            lessons: lessons,
            assessments: [],
            preferences: preferences(),
            now: now
        )

        XCTAssertEqual(plan.count, NotificationPlanner.maximumScheduled)
        XCTAssertEqual(plan.first?.id, NotificationPlanner.identifierPrefix + "lesson.ac-0")
        XCTAssertEqual(
            plan.last?.id,
            NotificationPlanner.identifierPrefix + "lesson.ac-\(NotificationPlanner.maximumScheduled - 1)"
        )
        XCTAssertLessThan(NotificationPlanner.maximumScheduled, 64, "iOS's own limit, with headroom")
    }

    func testThePlanIsOrderedByFireDate() {
        let plan = NotificationPlanner.plan(
            lessons: [
                lesson(id: "ac-late", start: now.addingTimeInterval(7200)),
                lesson(id: "ac-soon", start: now.addingTimeInterval(3600))
            ],
            assessments: [assessment(dueDate: W4Dates.date(year: 2026, month: 8, day: 25)!)],
            preferences: preferences(),
            now: now
        )

        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
        XCTAssertEqual(plan.first?.id, NotificationPlanner.identifierPrefix + "lesson.ac-soon")
    }

    func testAnEmptyDayPlansNothing() {
        let plan = NotificationPlanner.plan(
            lessons: [],
            assessments: [],
            preferences: preferences(),
            now: now
        )
        XCTAssertTrue(plan.isEmpty)
    }
}
