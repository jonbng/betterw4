//
//  DemoDataProvider.swift
//  BetterLectio
//
//  Provides hard-coded mock data for the Demo School flow used by Apple App
//  Review. No network I/O, no persistence side effects. Every factory returns
//  fresh values so the demo data looks current whenever reviewers open the app.
//

import Foundation

enum DemoDataProvider {

    // MARK: - Folders

    static let inboxFolder = MessageFolder(id: "inbox", displayName: "Indbakke")
    static let sentFolder = MessageFolder(id: "sent", displayName: "Sendt")
    static let defaultFolders: [MessageFolder] = [inboxFolder, sentFolder]

    // MARK: - Schedule

    /// Returns 3–5 events per weekday across the week containing `date` and the
    /// following week, so scrolling forward/backward a week still looks alive.
    static func scheduleEvents(weekOf date: Date = TimeProvider.now) -> [ScheduleEvent] {
        let calendar = Calendar(identifier: .iso8601)
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }

        let weekStart = weekInterval.start
        var events: [ScheduleEvent] = []

        let lessons: [(title: String, subtitle: String, teacher: String, teacherId: String, room: String, homework: String?)] = [
            ("1x MA", "Matematik A", "MH", "T_MH", "24", "Læs kapitel 5 s. 120-128"),
            ("1x DA", "Dansk A", "KA", "T_KA", "11", nil),
            ("1x EN", "Engelsk B", "SO", "T_SO", "17", "Essay draft due Friday"),
            ("1x FY", "Fysik B", "PE", "T_PE", "Lab 3", nil),
            ("1x SA", "Samfundsfag C", "AL", "T_AL", "22", "Forbered diskussion om valgret")
        ]

        // Danish gymnasium "modul" timing: ~90 min lessons, ~15 min breaks,
        // ~30 min lunch after 2nd modul.
        let timeSlots: [(start: String, end: String)] = [
            ("08:15", "09:45"),
            ("10:00", "11:30"),
            ("12:00", "13:30"),
            ("13:45", "15:15"),
            ("15:30", "17:00")
        ]

        // Indices into `lessons` per weekday — varied order and length so it
        // doesn't look like the same 5 classes every day.
        let weeklySchedule: [[Int]] = [
            [0, 1, 2, 3],       // Mon: MA, DA, EN, FY
            [1, 0, 4, 2, 3],    // Tue: full day
            [2, 0, 1],          // Wed: short day
            [3, 4, 2, 0],       // Thu
            [1, 2, 0, 4]        // Fri
        ]

        for weekOffset in 0..<2 {
            for dayOffset in 0..<5 { // Mon-Fri
                guard let day = calendar.date(byAdding: .day, value: weekOffset * 7 + dayOffset, to: weekStart) else { continue }
                let daySchedule = weeklySchedule[dayOffset]
                for (slotIndex, lessonIndex) in daySchedule.enumerated() {
                    let lesson = lessons[lessonIndex]
                    let slot = timeSlots[slotIndex]
                    let status: EventStatus
                    if weekOffset == 0 && dayOffset == 2 && slotIndex == 1 {
                        status = .cancelled
                    } else if weekOffset == 0 && dayOffset == 3 && slotIndex == 3 {
                        status = .changed
                    } else {
                        status = .normal
                    }
                    events.append(
                        ScheduleEvent(
                            id: "demo-sched-\(weekOffset)-\(dayOffset)-\(slotIndex)",
                            title: lesson.title,
                            subtitle: lesson.subtitle,
                            startTime: slot.start,
                            endTime: slot.end,
                            teacher: lesson.teacher,
                            teacherId: lesson.teacherId,
                            room: lesson.room,
                            status: status,
                            date: day,
                            notes: status == .changed ? "Flyttet til \(lesson.room)" : nil,
                            homework: lesson.homework
                        )
                    )
                }
            }
        }

        return events
    }

    static func lessonContent(for event: ScheduleEvent) -> LessonContent {
        let homeworkText = event.homework ?? "Ingen lektier denne time."
        return LessonContent(
            teacherNote: "Demo data: gennemgang af dagens emne.",
            items: [
                LessonContentItem(
                    id: "demo-item-\(event.id)-hw",
                    title: "Lektier",
                    note: nil,
                    blocks: [.paragraph(inlines: [.text(homeworkText)])],
                    links: [],
                    isHomework: true
                ),
                LessonContentItem(
                    id: "demo-item-\(event.id)-note",
                    title: "Noter",
                    note: nil,
                    blocks: [.paragraph(inlines: [.text("Demo underviser-noter for \(event.subtitle).")])],
                    links: [],
                    isHomework: false
                )
            ]
        )
    }

    // MARK: - Messages

    static func messageThreads(for folder: MessageFolder) -> [MessageThread] {
        let today = TimeProvider.now
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        let stamp = { (minutesAgo: Int) -> String in
            formatter.string(from: Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: today) ?? today)
        }

        if folder.id == sentFolder.id {
            return [
                thread(id: "demo-thread-sent-1", folderId: folder.id, title: "Tak for hjælpen", sender: "Demo Student",
                       date: stamp(60 * 24 * 2), read: true, flagged: false),
                thread(id: "demo-thread-sent-2", folderId: folder.id, title: "Spørgsmål til opgaven", sender: "Demo Student",
                       date: stamp(60 * 24 * 5), read: true, flagged: false)
            ]
        }

        return [
            thread(id: "demo-thread-1", folderId: folder.id, title: "Velkommen til BetterLectio",
                   sender: "MH (Lærer)", senderType: .teacher,
                   date: stamp(30), read: false, flagged: true, attachment: false),
            thread(id: "demo-thread-2", folderId: folder.id, title: "Prøveplan - december",
                   sender: "Kontoret", senderType: .unknown,
                   date: stamp(60 * 4), read: false, flagged: false, attachment: true),
            thread(id: "demo-thread-3", folderId: folder.id, title: "Husk aflevering fredag",
                   sender: "KA (Lærer)", senderType: .teacher,
                   date: stamp(60 * 12), read: true, flagged: false),
            thread(id: "demo-thread-4", folderId: folder.id, title: "Studietur - info-møde",
                   sender: "SO (Lærer)", senderType: .teacher,
                   date: stamp(60 * 24), read: true, flagged: false),
            thread(id: "demo-thread-5", folderId: folder.id, title: "Fællesbesked: fredagsbar",
                   sender: "Elevrådet", senderType: .student,
                   date: stamp(60 * 36), read: true, flagged: false),
            thread(id: "demo-thread-6", folderId: folder.id, title: "Fysik: ekstra øvelse",
                   sender: "PE (Lærer)", senderType: .teacher,
                   date: stamp(60 * 48), read: true, flagged: false)
        ]
    }

    static func messageThreadDetail(for thread: MessageThread) -> MessageThreadDetail {
        let baseDate = "13/3 14:22"
        let intro = Message(
            id: "\(thread.id)-m1",
            senderName: thread.senderName,
            date: baseDate,
            title: thread.title,
            content: demoMessageBody(for: thread.id),
            attachments: thread.hasAttachment ? [demoAttachment(for: thread.id)] : []
        )
        let followup = Message(
            id: "\(thread.id)-m2",
            senderName: "Demo Student",
            date: "13/3 15:01",
            title: thread.title,
            content: "Tak for beskeden! Jeg kigger på det med det samme.",
            attachments: []
        )
        return MessageThreadDetail(
            threadId: thread.id,
            title: thread.title,
            recipients: thread.senderType == .teacher ? "Demo Student, \(thread.senderName)" : thread.senderName,
            messages: [intro, followup],
            canReply: true
        )
    }

    static func synthesizedReply(for threadId: String, replyTitle: String, replyText: String) -> Message {
        let formatter = DateFormatter()
        formatter.dateFormat = "d/M HH:mm"
        return Message(
            id: "\(threadId)-reply-\(UUID().uuidString.prefix(6))",
            senderName: "Demo Student",
            date: formatter.string(from: TimeProvider.now),
            title: replyTitle,
            content: replyText,
            attachments: []
        )
    }

    // MARK: - Homework

    static func homeworkEntries() -> [HomeworkEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: TimeProvider.now)
        let fmt = DateFormatter()
        fmt.dateFormat = "EE d/M"
        fmt.locale = Locale(identifier: "da_DK")

        func entry(dayOffset: Int, hold: String, title: String, teacher: String, room: String, items: [String]) -> HomeworkEntry {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return HomeworkEntry(
                id: "demo-hw-\(dayOffset)-\(hold.replacingOccurrences(of: " ", with: ""))",
                date: date,
                displayDate: fmt.string(from: date),
                hold: hold,
                title: title,
                teacher: teacher,
                room: room,
                status: .normal,
                note: "Demo-lektier for App Review.",
                items: items.enumerated().map { index, text in
                    HomeworkItem(id: "demo-hwi-\(dayOffset)-\(index)", text: text, url: nil)
                }
            )
        }

        return [
            entry(dayOffset: 0, hold: "1x MA", title: "Integration", teacher: "MH", room: "24",
                  items: ["Læs s. 120-128", "Lav opgave 5.3 a-c"]),
            entry(dayOffset: 1, hold: "1x DA", title: "Romananalyse", teacher: "KA", room: "11",
                  items: ["Læs kapitel 3", "Skriv 1 siders analyse"]),
            entry(dayOffset: 2, hold: "1x EN", title: "Essay draft", teacher: "SO", room: "17",
                  items: ["Udkast til essay (500 ord)"]),
            entry(dayOffset: 4, hold: "1x FY", title: "Kinematik", teacher: "PE", room: "Lab 3",
                  items: ["Lav øvelse 4.1", "Noter observationer"]),
            entry(dayOffset: 6, hold: "1x SA", title: "Valgret", teacher: "AL", room: "22",
                  items: ["Forbered diskussion"])
        ]
    }

    // MARK: - Directory

    /// Full directory snapshot for demo mode — students, teachers, holds, rooms.
    /// Built via `DirectoryParser.buildDirectoryEntities` so synthetic classes,
    /// search tokens, and metadata match a real sync.
    static func directoryEntities(gymId: Int) -> [DirectoryEntity] {
        var items: [RawDirectoryItem] = []

        let firstNames = ["Anna", "Bjørn", "Camilla", "Daniel", "Emma", "Frederik", "Gustav", "Helene", "Ida", "Jonas",
                          "Karen", "Lars", "Mia", "Nikolaj", "Olivia", "Peter", "Rikke", "Sofie", "Tobias", "Ulrik"]
        let lastNames = ["Hansen", "Nielsen", "Jensen", "Pedersen", "Andersen", "Christensen", "Larsen", "Sørensen",
                         "Rasmussen", "Jørgensen", "Madsen", "Olsen", "Kristensen", "Thomsen"]
        for i in 0..<20 {
            let name = "\(firstNames[i % firstNames.count]) \(lastNames[(i * 3) % lastNames.count])"
            let numericID = "\(1000 + i)"
            items.append(RawDirectoryItem(
                gymId: gymId,
                rawLabel: "\(name) (1x \(i + 1))",
                rawPrefixedID: "S\(numericID)",
                prefix: "S",
                numericID: numericID,
                isActive: true,
                rawTypeMarker: nil
            ))
        }

        let teachers: [(name: String, abbr: String)] = [
            ("Mette Hansen", "MH"),
            ("Kasper Andersen", "KA"),
            ("Sofie Olsen", "SO"),
            ("Peter Eriksen", "PE"),
            ("Anne Larsen", "AL")
        ]
        for teacher in teachers {
            items.append(RawDirectoryItem(
                gymId: gymId,
                rawLabel: "\(teacher.name) (\(teacher.abbr))",
                rawPrefixedID: "T_\(teacher.abbr)",
                prefix: "T",
                numericID: "_\(teacher.abbr)",
                isActive: true,
                rawTypeMarker: nil
            ))
        }

        let holds = ["1x MA", "1x DA", "1x EN", "1x FY", "1x SA"]
        for (i, label) in holds.enumerated() {
            let numericID = "\(2000 + i)"
            items.append(RawDirectoryItem(
                gymId: gymId,
                rawLabel: label,
                rawPrefixedID: "HE\(numericID)",
                prefix: "HE",
                numericID: numericID,
                isActive: true,
                rawTypeMarker: nil
            ))
        }

        let rooms: [(label: String, id: String)] = [
            ("24 - Matematik", "24"),
            ("11 - Dansk", "11"),
            ("17 - Sprog", "17"),
            ("Lab 3 - Fysik", "lab3"),
            ("22 - Samfundsfag", "22")
        ]
        for room in rooms {
            items.append(RawDirectoryItem(
                gymId: gymId,
                rawLabel: room.label,
                rawPrefixedID: "RO\(room.id)",
                prefix: "RO",
                numericID: room.id,
                isActive: true,
                rawTypeMarker: nil
            ))
        }

        return DirectoryParser.buildDirectoryEntities(from: items, gymId: gymId)
    }

    static func directoryStudents(gymId: Int) -> [StudentEntry] {
        let first = ["Anna", "Bjørn", "Camilla", "Daniel", "Emma", "Frederik", "Gustav", "Helene", "Ida", "Jonas",
                     "Karen", "Lars", "Mia", "Nikolaj", "Olivia", "Peter", "Rikke", "Sofie", "Tobias", "Ulrik"]
        let last = ["Hansen", "Nielsen", "Jensen", "Pedersen", "Andersen", "Christensen", "Larsen", "Sørensen",
                    "Rasmussen", "Jørgensen", "Madsen", "Olsen", "Kristensen", "Thomsen"]

        var students: [StudentEntry] = []
        for i in 0..<20 {
            let name = "\(first[i % first.count]) \(last[(i * 3) % last.count])"
            students.append(
                StudentEntry(
                    studentId: "demo-s-\(i)",
                    name: name,
                    classLabel: "3a",
                    classNumber: "\(i + 1)",
                    gymId: gymId,
                    type: .student
                )
            )
        }

        let teachers = [
            ("demo-t-mh", "Mette Hansen", "MH"),
            ("demo-t-ka", "Kasper Andersen", "KA"),
            ("demo-t-so", "Sofie Olsen", "SO"),
            ("demo-t-pe", "Peter Eriksen", "PE"),
            ("demo-t-al", "Anne Larsen", "AL")
        ]
        for (id, name, abbr) in teachers {
            students.append(
                StudentEntry(
                    studentId: id,
                    name: name,
                    classLabel: abbr,
                    classNumber: "",
                    gymId: gymId,
                    type: .teacher
                )
            )
        }
        return students
    }

    // MARK: - Grades

    static func gradesReport() -> GradesReport {
        func cell(_ v: String) -> GradeCellValue {
            GradeCellValue(value: v, xprsSubject: nil, source: "demo", weight: 1.0)
        }
        let columns = [
            GradeColumn(key: "1.standpunkt", label: "1. standpunkt"),
            GradeColumn(key: "2.standpunkt", label: "2. standpunkt"),
            GradeColumn(key: "intern prøve", label: "Intern prøve"),
            GradeColumn(key: "årskarakter", label: "Årskarakter"),
            GradeColumn(key: "eksamenskarakter", label: "Eksamenskarakter")
        ]
        let grades: [GradeEntry] = [
            GradeEntry(id: "demo-g-ma", hold: "1x MA", holdElementId: nil, subject: "Matematik A",
                       grades: ["1.standpunkt": cell("10"), "2.standpunkt": cell("10"),
                                "intern prøve": cell("12"), "årskarakter": cell("10")]),
            GradeEntry(id: "demo-g-da", hold: "1x DA", holdElementId: nil, subject: "Dansk A",
                       grades: ["1.standpunkt": cell("7"), "2.standpunkt": cell("10"),
                                "årskarakter": cell("10")]),
            GradeEntry(id: "demo-g-en", hold: "1x EN", holdElementId: nil, subject: "Engelsk B",
                       grades: ["1.standpunkt": cell("10"), "2.standpunkt": cell("12"),
                                "intern prøve": cell("12"), "årskarakter": cell("12"),
                                "eksamenskarakter": cell("12")]),
            GradeEntry(id: "demo-g-fy", hold: "1x FY", holdElementId: nil, subject: "Fysik B",
                       grades: ["1.standpunkt": cell("7"), "2.standpunkt": cell("7"),
                                "årskarakter": cell("7")]),
            GradeEntry(id: "demo-g-sa", hold: "1x SA", holdElementId: nil, subject: "Samfundsfag C",
                       grades: ["1.standpunkt": cell("10")])
        ]
        let notes: [GradeNoteEntry] = [
            GradeNoteEntry(id: "demo-n-1", hold: "1x MA", gradeType: "Standpunkt", grade: "10",
                           insertedAt: "10/12-2025", note: "God indsats i eksamensopgaven.")
        ]
        return GradesReport(
            blockedWrittenProtocolTerm: nil,
            blockedOralProtocolTerm: nil,
            columns: columns,
            grades: grades,
            notes: notes
        )
    }

    // MARK: - Assignments

    static func assignments() -> [Assignment] {
        let calendar = Calendar.current
        let today = TimeProvider.now
        let fmt = DateFormatter()
        fmt.dateFormat = "d/M-yyyy HH:mm"

        func assignment(offset: Int, hold: String, title: String, status: AssignmentStatus, grade: String? = nil) -> Assignment {
            let deadline = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let deadlineStr = fmt.string(from: deadline)
            return Assignment(
                id: "demo-asg-\(offset)-\(hold.replacingOccurrences(of: " ", with: ""))",
                week: "Uge \(calendar.component(.weekOfYear, from: deadline))",
                hold: hold,
                holdElementId: "HE_DEMO_\(hold.replacingOccurrences(of: " ", with: ""))",
                title: title,
                deadline: deadlineStr,
                deadlineDate: deadline,
                studentTime: "1,00",
                status: status,
                absence: "0 %",
                awaiting: status == .waiting ? "Lærer" : nil,
                assignmentNote: status == .notSubmitted ? "Husk at aflevere til tiden." : nil,
                grade: grade,
                gradeNote: grade != nil ? "God besvarelse." : nil,
                studentNote: nil,
                detailURL: "/lectio/-1/ElevAflevering.aspx?exerciseid=demo"
            )
        }

        return [
            assignment(offset: -14, hold: "1x MA", title: "Integralregning", status: .submitted, grade: "10"),
            assignment(offset: -7, hold: "1x DA", title: "Romananalyse", status: .submitted, grade: "7"),
            assignment(offset: -2, hold: "1x EN", title: "Essay: Identity", status: .waiting),
            assignment(offset: 3, hold: "1x FY", title: "Rapport: Kinematik", status: .notSubmitted),
            assignment(offset: 5, hold: "1x SA", title: "Analyse: Valgret", status: .notSubmitted),
            assignment(offset: 10, hold: "1x MA", title: "Differentialligninger", status: .notSubmitted)
        ]
    }

    static func assignmentDetail(for assignment: Assignment) -> AssignmentDetail {
        AssignmentDetail(
            title: assignment.title,
            hold: assignment.hold,
            gradeScale: "7-trinsskalaen",
            teacher: "MH",
            studentTime: assignment.studentTime,
            deadline: assignment.deadline,
            assignmentNote: "Demo-opgavebeskrivelse. Besvar alle delopgaver skriftligt.",
            inDescription: false,
            descriptionFiles: [],
            submissions: [],
            awaiting: assignment.awaiting,
            status: assignment.status.displayName,
            completed: assignment.status == .submitted,
            grade: assignment.grade,
            gradeNote: assignment.gradeNote,
            studentNote: nil
        )
    }

    // MARK: - Absence

    static func absenceReport() -> AbsenceReport {
        let calendar = Calendar.current
        let today = TimeProvider.now

        func entry(offset: Int, hold: String, percent: String, reason: String?) -> AbsenceEntry {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return AbsenceEntry(
                id: "demo-abs-\(offset)-\(hold.replacingOccurrences(of: " ", with: ""))",
                registrationId: "demo-abs-\(offset)-\(hold.replacingOccurrences(of: " ", with: ""))",
                activityId: nil,
                date: date,
                week: "Uge \(calendar.component(.weekOfYear, from: date))",
                activity: "\(hold) • 1. modul",
                activityDetails: ActivityDetails(
                    title: "Demo lektion",
                    hold: hold,
                    teacher: "MH",
                    room: "24",
                    dateTime: "08:10 til 09:00",
                    hasNote: false,
                    hasHomework: false,
                    isChanged: false
                ),
                absencePercent: percent,
                absenceType: reason == nil ? "Fravær" : "Godskrevet",
                registeredAt: "", registeredBy: "MH",
                reason: reason,
                note: nil,
                remark: nil,
                isApproved: reason != nil
            )
        }

        return AbsenceReport(
            summary: AbsenceSummary(regularAbsence: "4,5 %", writtenAbsence: "2,0 %"),
            missingReasons: [
                entry(offset: -10, hold: "1x MA", percent: "100%", reason: nil),
                entry(offset: -7, hold: "1x DA", percent: "50%", reason: nil)
            ],
            registrations: [
                entry(offset: -20, hold: "1x FY", percent: "100%", reason: "Sygdom"),
                entry(offset: -15, hold: "1x EN", percent: "25%", reason: "Lægebesøg")
            ]
        )
    }

    // MARK: - Private helpers

    private static func thread(
        id: String,
        folderId: String,
        title: String,
        sender: String,
        senderType: SenderType = .teacher,
        date: String,
        read: Bool,
        flagged: Bool,
        attachment: Bool = false
    ) -> MessageThread {
        MessageThread(
            id: id,
            title: title,
            senderName: sender,
            firstSenderName: sender,
            recipients: "Demo Student",
            date: date,
            isRead: read,
            isFlagged: flagged,
            hasAttachment: attachment,
            senderType: senderType
        )
    }

    private static func demoMessageBody(for threadId: String) -> String {
        switch threadId {
        case "demo-thread-1":
            return "Hej og velkommen til BetterLectio-demoen! Alle data her er fiktive og bruges kun til app-gennemgang."
        case "demo-thread-2":
            return "Prøveplanen for december er nu klar. Se vedhæftet fil for detaljer."
        case "demo-thread-3":
            return "Husk at aflevering er fredag kl. 23:59. Send mig en besked hvis du har spørgsmål."
        case "demo-thread-4":
            return "Vi holder info-møde om studieturen på fredag kl. 14:00 i aula."
        case "demo-thread-5":
            return "Fredagsbar på fredag fra kl. 16! Alle er velkomne. Hilsen Elevrådet."
        case "demo-thread-6":
            return "Her er en ekstra øvelse til dem der vil dykke dybere ned i kinematik. Frivilligt."
        default:
            return "Demo-beskedsindhold."
        }
    }

    private static func demoAttachment(for threadId: String) -> MessageAttachment {
        MessageAttachment(
            id: "demo-att-\(threadId)",
            name: "Prøveplan.pdf",
            url: "about:blank"
        )
    }
}
