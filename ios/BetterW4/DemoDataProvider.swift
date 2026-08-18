//
//  DemoDataProvider.swift
//  BetterW4
//
//  The offline demo catalogue: one believable day at UWC Red Cross Nordic, for the App Review
//  account (features.md §4).
//
//  Two invariants, both easy to break and both load-bearing:
//
//    1. **Zero network.** Nothing here fetches, and nothing here hands out a remote URL that a
//       screen would fetch. Portraits are drawn locally from initials — never a remote avatar,
//       never a gravatar URL. A reviewer in Airplane Mode sees a complete app.
//    2. **Zero persistence.** Every factory is built from `TimeProvider.now`, so the demo always
//       looks like today, and nothing is written to a store.
//
//  Everything here is invented. The ids are `nc00…`, which cannot collide with a real UWC id
//  (reviewer-notes.md §8); the names belong to nobody; the only school-specific facts are public
//  ones (IB subject names, the campus-status option list, the `@uwcrcn.no` mail convention).
//
//  Every repository already carries its own `isDemo` branch, so a demo session cannot reach the
//  network even if a screen forgets to check. This file is the shared catalogue the shell and
//  those branches agree on — same student, same subjects, same teachers — and the identity is
//  delegated to `DirectoryRepository.demoPeople` so there is exactly one demo person.
//

import Foundation

enum DemoDataProvider {

    // MARK: - Reviewer-facing copy

    /// Shown wherever the app has to say plainly what the reviewer is looking at.
    static let bannerText = "Demo data. Not connected to W4."

    // MARK: - Identity

    /// The demo student's UWC id — the same one `ProfileRepository` serves in demo mode.
    static let uwcId = ProfileRepository.demoOwnUwcId

    /// The demo student as a directory person, taken from the one demo roster in the app.
    static var person: DirectoryPerson {
        DirectoryRepository.demoPeople.first { $0.uwcId == uwcId }
            ?? DirectoryPerson(uwcId: uwcId, name: "Demo Student", kind: .student)
    }

    /// What the More header and the ID card show.
    static var profile: DirectoryPersonProfile {
        ProfileRepository.demoProfile(uwcId: uwcId)
            ?? DirectoryPersonProfile(person: person)
    }

    static var displayName: String { person.displayName }
    static var email: String { person.email }

    // MARK: - The teaching week

    /// One block in the demo day. `isExtraAcademic` marks the single EA activity.
    struct DemoLesson: Sendable, Hashable {
        let title: String
        let subject: String
        let teacher: String
        let room: String
        /// `HH:mm`, Europe/Oslo, inside W4's captured grid (`tt_start_hour = 7`, `tt_end_hour = 22`).
        let start: String
        let end: String
        let isExtraAcademic: Bool
    }

    /// A UWC RCN IB day: four academic blocks and one Extra Academics activity.
    static let lessons: [DemoLesson] = [
        DemoLesson(
            title: "Biology HL",
            subject: "Biology",
            teacher: "A. Nordby",
            room: "Lab 2",
            start: "08:30",
            end: "09:50",
            isExtraAcademic: false
        ),
        DemoLesson(
            title: "Mathematics AA SL",
            subject: "Mathematics",
            teacher: "P. Haugen",
            room: "R14",
            start: "10:10",
            end: "11:30",
            isExtraAcademic: false
        ),
        DemoLesson(
            title: "English A HL",
            subject: "English",
            teacher: "S. Duncan",
            room: "R7",
            start: "11:40",
            end: "13:00",
            isExtraAcademic: false
        ),
        DemoLesson(
            title: "Theory of Knowledge",
            subject: "TOK",
            teacher: "M. Iversen",
            room: "R2",
            start: "14:00",
            end: "15:20",
            isExtraAcademic: false
        ),
        DemoLesson(
            title: "Sea Kayaking",
            subject: "Sea Kayaking",
            teacher: "T. Lie",
            room: "Boathouse",
            start: "16:00",
            end: "17:30",
            isExtraAcademic: true
        )
    ]

    /// The one Extra Academics activity a reviewer sees.
    static var extraAcademicActivity: DemoLesson {
        lessons.first { $0.isExtraAcademic } ?? lessons[0]
    }

    /// Two weeks × Monday–Friday of `lessons`, so paging a week forward or back still looks alive.
    /// One block is cancelled and one is changed, because both have their own rendering and a
    /// reviewer should see them. The weekend is deliberately empty — on W4 that is routine.
    ///
    /// Built from the clock, so the demo is always "this week".
    static func scheduleEvents(weekOf date: Date = TimeProvider.now) -> [ScheduleEvent] {
        let monday = W4Dates.startOfDay(W4Dates.startOfWeek(containing: date))
        var events: [ScheduleEvent] = []

        for weekOffset in 0..<2 {
            for dayOffset in 0..<5 {
                let day = W4Dates.startOfDay(
                    W4Dates.adding(days: weekOffset * 7 + dayOffset, to: monday)
                )
                for (slot, lesson) in lessons.enumerated() {
                    let status: EventStatus
                    if weekOffset == 0 && dayOffset == 2 && slot == 1 {
                        status = .cancelled
                    } else if weekOffset == 0 && dayOffset == 3 && slot == 3 {
                        status = .changed
                    } else {
                        status = .normal
                    }

                    events.append(
                        ScheduleEvent(
                            id: "demo-lesson-\(weekOffset)-\(dayOffset)-\(slot)",
                            title: lesson.title,
                            subtitle: lesson.isExtraAcademic ? "Extra Academics" : lesson.subject,
                            startTime: lesson.start,
                            endTime: lesson.end,
                            teacher: lesson.teacher,
                            teacherId: nil,
                            room: lesson.room,
                            status: status,
                            date: day,
                            notes: status == .changed ? "Moved to \(lesson.room)" : nil,
                            homework: preparationNote(for: lesson)
                        )
                    )
                }
            }
        }

        return events
    }

    /// What the lesson sheet shows when a reviewer taps a block.
    static func lessonContent(for event: ScheduleEvent) -> LessonContent {
        let preparation = event.homework ?? "Nothing to prepare for this lesson."
        return LessonContent(
            teacherNote: bannerText,
            items: [
                LessonContentItem(
                    id: "demo-lesson-item-\(event.id)-prep",
                    title: "Preparation",
                    note: nil,
                    blocks: [.paragraph(inlines: [.text(preparation)])],
                    links: [],
                    isHomework: true
                ),
                LessonContentItem(
                    id: "demo-lesson-item-\(event.id)-note",
                    title: "Notes",
                    note: nil,
                    blocks: [.paragraph(inlines: [.text("Sample teacher notes for \(event.title).")])],
                    links: [],
                    isHomework: false
                )
            ]
        )
    }

    private static func preparationNote(for lesson: DemoLesson) -> String? {
        switch lesson.subject {
        case "Biology": return "Read the enzymes handout before the lab."
        case "Mathematics": return "Exercise set 4.2, questions 1–8."
        case "English": return "Finish the close reading of chapter 6."
        default: return nil
        }
    }

    // MARK: - Assessments

    /// Items around today: one done, one overdue, one due tomorrow, one further out, and one the
    /// student created themselves — enough for every row style on the Assessments screen.
    static func assessments(relativeTo now: Date = TimeProvider.now) -> [Assessment] {
        let today = W4Dates.startOfDay(now)

        func due(_ days: Int) -> Date {
            W4Dates.startOfDay(W4Dates.adding(days: days, to: today))
        }

        return [
            Assessment(
                id: "class:demo-1",
                rawId: "demo-1",
                kind: .classAssigned,
                rawKind: "class",
                title: "Enzymes lab report",
                subject: "Biology",
                classCode: "BIO HL",
                teacher: "A. Nordby",
                unit: "Unit 2 · Molecular biology",
                dueDate: due(-3),
                daysLeft: -3,
                status: .done,
                rawStatus: "done"
            ),
            Assessment(
                id: "class:demo-2",
                rawId: "demo-2",
                kind: .classAssigned,
                rawKind: "class",
                title: "Paper 1 practice",
                subject: "Mathematics",
                classCode: "MAA SL",
                teacher: "P. Haugen",
                unit: "Unit 5 · Calculus",
                dueDate: due(-1),
                daysLeft: -1,
                status: .pending,
                rawStatus: "pending",
                isOverdue: true
            ),
            Assessment(
                id: "class:demo-3",
                rawId: "demo-3",
                kind: .classAssigned,
                rawKind: "class",
                title: "Comparative essay",
                subject: "English",
                classCode: "ENG A HL",
                teacher: "S. Duncan",
                unit: "Unit 3 · Readers, writers and texts",
                dueDate: due(1),
                daysLeft: 1,
                status: .pending,
                rawStatus: "pending"
            ),
            Assessment(
                id: "class:demo-4",
                rawId: "demo-4",
                kind: .classAssigned,
                rawKind: "class",
                title: "TOK exhibition draft",
                subject: "TOK",
                classCode: "TOK",
                teacher: "M. Iversen",
                unit: "Exhibition",
                dueDate: due(6),
                daysLeft: 6,
                status: .pending,
                rawStatus: "pending"
            ),
            Assessment(
                id: "student:demo-5",
                rawId: "demo-5",
                kind: .studentCreated,
                rawKind: "student",
                title: "Revise kayak rescue drills",
                dueDate: due(4),
                daysLeft: 4,
                status: .pending,
                rawStatus: "pending",
                isEditable: true
            )
        ]
    }

    // MARK: - Mail

    static var mailFolders: [MailFolder] { MailFolder.all }

    /// Three inbox messages (two unread, one with an attachment) and one sent message.
    static func mailMessages(
        folder: MailFolder,
        relativeTo now: Date = TimeProvider.now
    ) -> [MailMessage] {
        if folder.id == MailFolder.archive.id {
            return [
                MailMessage(
                    id: "demo-mail-sent-1",
                    folderID: folder.id,
                    subject: "Re: Kayak trip permission",
                    receivedAt: now.addingTimeInterval(-60 * 60 * 26)
                )
            ]
        }

        return [
            MailMessage(
                id: "demo-mail-1",
                folderID: folder.id,
                subject: "Welcome back to term 2",
                from: "House Leader",
                receivedAt: now.addingTimeInterval(-60 * 40),
                isUnread: true,
                hasAttachment: true
            ),
            MailMessage(
                id: "demo-mail-2",
                folderID: folder.id,
                subject: "Biology lab groups for Thursday",
                from: "A. Nordby",
                receivedAt: now.addingTimeInterval(-60 * 60 * 5),
                isUnread: true
            ),
            MailMessage(
                id: "demo-mail-3",
                folderID: folder.id,
                subject: "Sea Kayaking — meet at the boathouse",
                from: "T. Lie",
                receivedAt: now.addingTimeInterval(-60 * 60 * 30)
            )
        ]
    }

    static func mailListPage(
        folder: MailFolder,
        relativeTo now: Date = TimeProvider.now
    ) -> MailListPage {
        let isArchive = folder.id == MailFolder.archive.id
        return MailListPage(
            folder: folder,
            messages: mailMessages(folder: folder, relativeTo: now),
            pagination: nil,
            outcome: .parsed,
            columns: isArchive
                ? MailColumnLayout(headers: ["send date", "subject"], received: 0, subject: 1)
                : MailColumnLayout(headers: ["received", "from", "subject"], received: 0, from: 1, subject: 2)
        )
    }

    /// The body a reviewer sees on opening a demo message. Plain, safe HTML with no remote assets.
    static func mailMessage(id: String, relativeTo now: Date = TimeProvider.now) -> MailMessageDetail {
        let known = (mailMessages(folder: .inbox, relativeTo: now)
            + mailMessages(folder: .archive, relativeTo: now))
            .first { $0.id == id }

        return MailMessageDetail(
            id: id,
            subject: known?.subject ?? "Demo message",
            from: known?.from ?? displayName,
            recipients: [displayName],
            sentAt: known?.receivedAt ?? now,
            bodyHTML: """
            <p>Hi \(displayName),</p>
            <p>\(bannerText) Nothing on this screen came from a server, and the demo account \
            never makes a request.</p>
            <p>— UWC Red Cross Nordic</p>
            """,
            attachments: known?.hasAttachment == true ? [mailAttachment] : []
        )
    }

    /// Deliberately a plain `.txt` so a preview shows real text rather than a corrupt PDF.
    static let mailAttachment = MailAttachment(
        id: "demo-attachment-1",
        name: "term-2-notes.txt",
        url: "demo://attachment/1"
    )

    static let mailAttachmentBody = Data(
        "This is a demo attachment. The demo account never downloads anything.\n".utf8
    )

    // MARK: - Attendance

    /// A clean record: zero absences and zero latenesses on both meters.
    static func attendanceOverview(relativeTo now: Date = TimeProvider.now) -> AttendanceOverview {
        AttendanceOverview(academic: .zero, extraAcademic: .zero, records: [], fetchedAt: now)
    }

    static func attendanceList(source: AttendanceSource) -> AttendanceList {
        AttendanceList(
            source: source,
            meter: .zero,
            records: [],
            hasMorePages: false,
            emptyMessage: "No absences recorded."
        )
    }

    // MARK: - Campus status

    /// The demo starts on campus, with all eleven captured options selectable.
    static let campusStatus = CampusStatus.onCampus
}
