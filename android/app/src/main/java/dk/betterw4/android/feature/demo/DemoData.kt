package dk.betterw4.android.feature.demo

import dk.betterw4.android.core.model.School
import dk.betterw4.android.core.model.W4School
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.feature.absence.AbsenceOverview
import dk.betterw4.android.feature.absence.AbsenceRegistration
import dk.betterw4.android.feature.absence.W4AbsenceMeter
import dk.betterw4.android.feature.assignments.AssignmentItem
import dk.betterw4.android.feature.classes.ClassLevel
import dk.betterw4.android.feature.classes.ClassMember
import dk.betterw4.android.feature.classes.ClassRoom
import dk.betterw4.android.feature.classes.MyClass
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.directory.House
import dk.betterw4.android.feature.directory.HouseResident
import dk.betterw4.android.feature.directory.HouseRoom
import dk.betterw4.android.feature.grades.GradeCellValue
import dk.betterw4.android.feature.grades.GradeColumn
import dk.betterw4.android.feature.grades.GradeRow
import dk.betterw4.android.feature.grades.GradesReport
import dk.betterw4.android.feature.homework.HomeworkItem
import dk.betterw4.android.feature.messages.MessageAttachment
import dk.betterw4.android.feature.messages.MessageFolder
import dk.betterw4.android.feature.messages.MessageThread
import dk.betterw4.android.feature.messages.MessageThreadDetail
import dk.betterw4.android.feature.messages.ThreadEntry
import dk.betterw4.android.feature.plans.StudyPlan
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.LessonContentBlock
import dk.betterw4.android.feature.schedule.LessonDetail
import dk.betterw4.android.feature.schedule.LessonParticipant
import dk.betterw4.android.feature.schedule.LessonResource
import dk.betterw4.android.feature.schedule.ScheduleDay
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleWeek
import dk.betterw4.android.feature.teams.ModuleStat
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

object DemoData {
    val schools = listOf(
        School.Demo,
        W4School.school,
    )

    fun scheduleWeek(year: Int, week: Int): ScheduleWeek {
        val monday = IsoDateUtils.weekStart(year, week)
        val today = LocalDate.now()
        val days = (0..4).map { offset ->
            val date = monday.plusDays(offset.toLong())
            val events = if (date == today || offset == today.dayOfWeek.value - 1) {
                listOf(
                    ScheduleEvent(
                        id = "demo1-$offset",
                        title = "Mathematics Analysis and Approaches",
                        team = "1DA13HMTAA",
                        teacher = "Sam Rivera",
                        room = "A 1.3",
                        status = EventStatus.NORMAL,
                        start = LocalDateTime.of(date, LocalTime.of(8, 15)),
                        end = LocalDateTime.of(date, LocalTime.of(9, 15)),
                        date = date,
                        homework = "Ex. 12–15",
                    ),
                    ScheduleEvent(
                        id = "demo2-$offset",
                        title = "Economics",
                        team = "1EA16CECOX",
                        teacher = "Frankie Fossum",
                        room = "A 1.6",
                        status = if (offset == 1) EventStatus.CHANGED else EventStatus.NORMAL,
                        start = LocalDateTime.of(date, LocalTime.of(9, 25)),
                        end = LocalDateTime.of(date, LocalTime.of(10, 25)),
                        date = date,
                    ),
                    ScheduleEvent(
                        id = "demo3-$offset",
                        title = "Physics",
                        team = "1BE12CPHYX",
                        teacher = "Alex Nwosu",
                        room = "E 1.2",
                        status = if (offset == 2) EventStatus.CANCELLED else EventStatus.NORMAL,
                        start = LocalDateTime.of(date, LocalTime.of(10, 45)),
                        end = LocalDateTime.of(date, LocalTime.of(11, 45)),
                        date = date,
                    ),
                )
            } else {
                listOf(
                    ScheduleEvent(
                        id = "demo-x-$offset",
                        title = "History",
                        team = "1DK11CHIST",
                        teacher = "Maya Iversen",
                        room = "K 1.1",
                        start = LocalDateTime.of(date, LocalTime.of(8, 15)),
                        end = LocalDateTime.of(date, LocalTime.of(9, 15)),
                        date = date,
                    ),
                )
            }
            ScheduleDay(date, events)
        }
        return ScheduleWeek(year, week, days)
    }

    val messages = listOf(
        MessageThread(
            id = "m1",
            topic = "Welcome back to term 2",
            sender = "House Leader",
            dateChanged = LocalDateTime.now().minusHours(2),
            folderId = MessageFolder.UNREAD.id,
            unread = true,
        ),
        MessageThread(
            id = "m2",
            topic = "Mathematics assignment postponed",
            sender = "Sam Rivera",
            dateChanged = LocalDateTime.now().minusDays(1),
            folderId = MessageFolder.INBOX.id,
            unread = false,
        ),
    )

    fun messageDetail(id: String) = MessageThreadDetail(
        thread = messages.firstOrNull { it.id == id } ?: messages.first(),
        entries = listOf(
            ThreadEntry(
                id = "e1",
                topic = "Message",
                contentHtml = "<p>This is a <b>demo message</b>. Sign in for real campus data.</p>" +
                    "<p>An embedded image is shown below (demo).</p>" +
                    "<img src=\"https://picsum.photos/seed/msg-demo/640/280\" alt=\"Demo figure\"/>" +
                    "<div class=\"message-attachements\"><a href=\"demo://attachment/worksheet.pdf\">worksheet.pdf</a></div>",
                senderName = "System",
                sentAt = LocalDateTime.now().minusHours(2),
                attachments = listOf(
                    MessageAttachment("worksheet.pdf", "demo://attachment/worksheet.pdf"),
                    MessageAttachment("diagram.png", "https://picsum.photos/seed/betterw4/640/360"),
                ),
            ),
        ),
        receivers = listOf("Demo Student", "Sam Rivera"),
    )

    val homework = listOf(
        HomeworkItem(
            id = "h1",
            note = "Read the enzymes handout before the lab.",
            activityTitle = "Biology HL",
            date = LocalDate.now().plusDays(1),
            team = "BIO HL",
            href = "index.php?r=academics/deadlines",
            detailHtml = null,
        ),
        HomeworkItem(
            id = "h2",
            note = "Finish the close reading of chapter 6.",
            activityTitle = "English A HL",
            date = LocalDate.now().plusDays(2),
            team = "ENG A HL",
            href = "index.php?r=academics/deadlines",
        ),
    )

    fun homeworkDetailHtml(item: HomeworkItem): String =
        """
        <h2>${item.activityTitle}</h2>
        <p><b>Preparation:</b> ${item.note}</p>
        <p>Demo preparation for ${item.team}. Review the material before class.</p>
        <img src="https://picsum.photos/seed/hw-${item.id}/640/280" alt="Demo figure"/>
        <ul><li>Bring your book</li><li>Notes from last lesson</li></ul>
        """.trimIndent()

    val assignments = listOf(
        AssignmentItem(
            id = "a1",
            title = "Waves lab report",
            team = "PHYX",
            week = IsoDateUtils.isoWeek(),
            deadline = LocalDateTime.now().plusDays(5).withHour(23).withMinute(59),
            status = "Pending",
            studentTime = 5.0,
            awaits = "Student",
            note = "",
        ),
        AssignmentItem(
            id = "a2",
            title = "Modernism essay",
            team = "LALI",
            week = IsoDateUtils.isoWeek() + 1,
            deadline = LocalDateTime.now().plusDays(12).withHour(12).withMinute(0),
            status = "Submitted",
            studentTime = 8.0,
            awaits = "Teacher",
            note = "",
        ),
    )

    val gradesReport = GradesReport(
        columns = listOf(
            GradeColumn("predicted", "Predicted"),
            GradeColumn("final", "Final"),
        ),
        grades = listOf(
            GradeRow(
                team = "AN",
                subject = "Mathematics HL",
                teamId = "demo-ma",
                grades = mapOf(
                    "predicted" to GradeCellValue("6"),
                    "final" to GradeCellValue("6"),
                ),
            ),
            GradeRow(
                team = "KL",
                subject = "English A HL",
                teamId = "demo-en",
                grades = mapOf(
                    "predicted" to GradeCellValue("7"),
                    "final" to GradeCellValue("6"),
                ),
            ),
            GradeRow(
                team = "JS",
                subject = "Biology SL",
                teamId = "demo-bi",
                grades = mapOf(
                    "predicted" to GradeCellValue("5"),
                ),
            ),
            GradeRow(
                team = "MR",
                subject = "History HL",
                teamId = "demo-hi",
                grades = mapOf(
                    "predicted" to GradeCellValue("6"),
                    "final" to GradeCellValue("5"),
                ),
            ),
        ),
        notes = emptyList(),
        alerts = emptyList(),
    )

    val absence = AbsenceOverview(
        teams = emptyList(),
        academicMeter = W4AbsenceMeter(absences = 2, latenesses = 1),
        eaMeter = W4AbsenceMeter(absences = 0, latenesses = 0),
        registrations = listOf(
            AbsenceRegistration(
                id = "ac|math|absence",
                date = LocalDate.now().minusDays(10),
                team = "Mathematics HL",
                cause = "Absence",
                status = "Registered",
                activityTitle = "Mathematics HL",
                teacher = "AN",
                dateTimeLabel = "04-Aug-2026 · P3",
                lessonTitle = "Academics",
                remark = "Academics",
                editable = false,
            ),
            AbsenceRegistration(
                id = "ac|english|late",
                date = LocalDate.now().minusDays(7),
                team = "English A HL",
                cause = "Lateness",
                status = "Registered",
                activityTitle = "English A HL",
                teacher = "KL",
                dateTimeLabel = "07-Aug-2026 · P1",
                lessonTitle = "Academics",
                remark = "Academics",
                editable = false,
            ),
            AbsenceRegistration(
                id = "ac|history|absence",
                date = LocalDate.now().minusDays(3),
                team = "History HL",
                cause = "Absence",
                status = "Registered",
                activityTitle = "History HL",
                teacher = "MR",
                dateTimeLabel = "11-Aug-2026 · P4",
                lessonTitle = "Academics",
                remark = "Academics",
                editable = false,
            ),
        ),
    )

    private fun identicon(seed: String): String {
        val hex = seed.hashCode().toUInt().toString(16).padStart(32, '0')
        return "https://www.gravatar.com/avatar/$hex?d=identicon&s=128"
    }

    private data class DemoStudentSpec(
        val id: String,
        val name: String,
        val country: String,
        val year: String,
        val houseId: String,
        val room: String? = null,
        val status: String = "On campus",
        val village: String? = null,
    )

    private data class DemoTeacherSpec(
        val id: String,
        val name: String,
        val subject: String,
    )

    private val demoStudents = listOf(
        DemoStudentSpec("S1", "Demo Student", "Denmark", "1", "denmark", "Room 101", village = "Haugland"),
        DemoStudentSpec("S2", "Bea Beltran", "Italy", "2", "denmark", "Room 101"),
        DemoStudentSpec("S3", "Dana Dlamini", "South Africa", "1", "denmark", "Room 102"),
        DemoStudentSpec("S4", "Noor Haddad", "Jordan", "1", "denmark", "Room 102"),
        DemoStudentSpec("S5", "Cara Cole", "Canada", "2", "finland", "Room 101"),
        DemoStudentSpec("S6", "Priya Sharma", "India", "2", "finland", "Room 101"),
        DemoStudentSpec("S7", "Mei Nakamura", "Japan", "1", "finland", "Room 102"),
        DemoStudentSpec("S8", "Gita Ghosh", "India", "1", "finland", status = "Off campus"),
        DemoStudentSpec("S9", "Luis Ortega", "Mexico", "2", "iceland", "Room 101"),
        DemoStudentSpec("S10", "Amara Okonkwo", "Nigeria", "1", "iceland", "Room 101"),
        DemoStudentSpec("S11", "Sofia Alvarez", "Argentina", "2", "norway", "Room 101"),
        DemoStudentSpec("S12", "Tomas Novak", "Czechia", "1", "norway", "Room 101"),
        DemoStudentSpec("S13", "Linh Nguyen", "Vietnam", "1", "norway", "Room 102"),
        DemoStudentSpec("S14", "Amina Diallo", "Senegal", "2", "sweden", "Room 101"),
        DemoStudentSpec("S15", "Hana Kim", "South Korea", "1", "sweden", "Room 101"),
        DemoStudentSpec("S16", "Mateo Silva", "Brazil", "2", "sweden", "Room 102"),
        DemoStudentSpec("S17", "Jamal Farouk", "Egypt", "2", "sweden", "Room 102"),
    )

    private val demoTeachers = listOf(
        DemoTeacherSpec("T1", "Sam Rivera", "Mathematics"),
        DemoTeacherSpec("T2", "Frankie Fossum", "Economics"),
        DemoTeacherSpec("T3", "Sofia Duncan", "English"),
        DemoTeacherSpec("T4", "Alex Nwosu", "Physics"),
        DemoTeacherSpec("T5", "Chris Chen", "Advisor"),
        DemoTeacherSpec("T6", "Maya Iversen", "History"),
    )

    private val houseNames = listOf(
        "denmark" to "Denmark",
        "finland" to "Finland",
        "iceland" to "Iceland",
        "norway" to "Norway",
        "sweden" to "Sweden",
    )

    val directory: List<DirectoryEntity> =
        demoStudents.map { spec ->
            DirectoryEntity(
                id = spec.id,
                name = spec.name,
                kind = DirectoryEntityKind.STUDENT,
                subtitle = listOfNotNull(
                    "Year ${spec.year}",
                    spec.village ?: houseNames.first { it.first == spec.houseId }.second,
                ).joinToString(" · "),
                avatarUrl = identicon(spec.id),
                year = spec.year,
            )
        } + demoTeachers.map { spec ->
            DirectoryEntity(
                id = spec.id,
                name = spec.name,
                kind = DirectoryEntityKind.TEACHER,
                subtitle = spec.subject,
                avatarUrl = identicon(spec.id),
            )
        }

    val plans = listOf(
        StudyPlan("p1", "Mathematics — study plan", "MTAA"),
        StudyPlan("p2", "English A — study plan", "LALI"),
    )

    val moduleStats = listOf(
        ModuleStat("MTAA", 120, 4, 2),
        ModuleStat("LALI", 110, 6, 1),
        ModuleStat("PHYX", 90, 10, 0),
    )

    fun lessonDetail(event: ScheduleEvent) = LessonDetail(
        eventId = event.id,
        title = event.title,
        note = event.notes ?: "Demo note: bring a calculator.",
        homework = event.homework ?: "Read chapter 3",
        contentBlocks = listOf(
            LessonContentBlock("heading", "Read chapter 3", isHomework = true),
            LessonContentBlock("paragraph", "Work through the exercises in the book.", isHomework = true),
            LessonContentBlock("heading", "In class", isHomework = false),
            LessonContentBlock("paragraph", "We'll go through the exercises and recap together.", isHomework = false),
            LessonContentBlock(
                kind = "image",
                text = "Board diagram",
                url = "https://picsum.photos/seed/lesson-${event.id}/640/300",
                isHomework = false,
            ),
            LessonContentBlock("note", "Bring your book.", isHomework = false),
        ),
        participants = directory
            .filter { it.kind == DirectoryEntityKind.STUDENT || it.name == event.teacher }
            .map { LessonParticipant.fromDirectory(it) },
        resources = listOf(
            LessonResource("Worksheet (PDF)", "demo://attachment/worksheet.pdf", isFile = true),
            LessonResource("GeoGebra", "https://www.geogebra.org/", isFile = false),
        ),
        holdId = "HE1",
    )

    private fun demoResident(
        id: String,
        name: String,
        kind: DirectoryEntityKind = DirectoryEntityKind.STUDENT,
        country: String? = null,
        year: String? = null,
        status: String? = "On campus",
    ) = HouseResident(
        entity = DirectoryEntity(
            id = id,
            name = name,
            kind = kind,
            subtitle = listOfNotNull(country, year?.let { "Year $it" }).joinToString(" · ")
                .ifBlank { null },
        ),
        country = country,
        year = year,
        status = status,
    )

    val houses = houseNames.map { (houseId, houseName) ->
        val inHouse = demoStudents.filter { it.houseId == houseId }
        val rooms = inHouse
            .mapNotNull { spec -> spec.room?.let { it to spec } }
            .groupBy({ it.first }, { it.second })
            .toSortedMap()
            .map { (roomName, people) ->
                HouseRoom(
                    id = "$houseId-${roomName.lowercase().replace(" ", "")}",
                    name = roomName,
                    residents = people.map {
                        demoResident(it.id, it.name, country = it.country, year = it.year, status = it.status)
                    },
                )
            }
        House(
            id = houseId,
            name = houseName,
            leaders = if (houseId == "denmark") {
                listOf(demoResident("T5", "Chris Chen", DirectoryEntityKind.TEACHER, status = null))
            } else {
                emptyList()
            },
            rooms = rooms,
            unassigned = inHouse.filter { it.room == null }.map {
                demoResident(
                    it.id,
                    it.name,
                    country = it.country,
                    year = it.year,
                    status = it.status,
                )
            },
            loaded = true,
        )
    }

    private fun demoMember(
        id: String,
        name: String,
        kind: DirectoryEntityKind,
        level: ClassLevel = ClassLevel.UNKNOWN,
    ) = ClassMember(id = id, name = name, kind = kind, level = level)

    private fun studentMember(id: String, level: ClassLevel = ClassLevel.UNKNOWN) =
        demoStudents.first { it.id == id }.let { demoMember(it.id, it.name, DirectoryEntityKind.STUDENT, level) }

    private fun teacherMember(id: String) =
        demoTeachers.first { it.id == id }.let { demoMember(it.id, it.name, DirectoryEntityKind.TEACHER) }

    val myClasses = listOf(
        MyClass(
            id = "1DA13HMTAA",
            subject = "Mathematics Analysis and Approaches",
            subjectCode = "MTAA",
            year = "1",
            block = "D",
            level = ClassLevel.HIGHER,
            levelLabel = "HL",
            room = ClassRoom(id = "a13", name = "A 1.3"),
            teachers = listOf(teacherMember("T1")),
            students = listOf("S1", "S3", "S7", "S10", "S12", "S13", "S15").map { studentMember(it) },
            loaded = true,
        ),
        MyClass(
            id = "1YA25SLALI",
            subject = "English Language & Literature",
            subjectCode = "LALI",
            year = "1",
            block = "Y",
            level = ClassLevel.STANDARD,
            levelLabel = "SL",
            room = ClassRoom(id = "a25", name = "A 2.5"),
            teachers = listOf(teacherMember("T3")),
            students = listOf("S1", "S2", "S5", "S6", "S11", "S14").map { studentMember(it) },
            loaded = true,
        ),
        MyClass(
            id = "1EA16CECOX",
            subject = "Economics",
            subjectCode = "ECOX",
            year = "1",
            block = "E",
            level = ClassLevel.COMBINED,
            levelLabel = "Combined",
            room = ClassRoom(id = "a16", name = "A 1.6"),
            teachers = listOf(teacherMember("T2")),
            students = listOf(
                studentMember("S1", ClassLevel.HIGHER),
                studentMember("S2", ClassLevel.STANDARD),
                studentMember("S4", ClassLevel.HIGHER),
                studentMember("S9", ClassLevel.STANDARD),
                studentMember("S16", ClassLevel.HIGHER),
                studentMember("S17", ClassLevel.STANDARD),
            ),
            loaded = true,
        ),
        MyClass(
            id = "1BE12CPHYX",
            subject = "Physics",
            subjectCode = "PHYX",
            year = "1",
            block = "B",
            level = ClassLevel.COMBINED,
            levelLabel = "Combined",
            room = ClassRoom(id = "e12", name = "E 1.2"),
            teachers = listOf(teacherMember("T4")),
            students = listOf("S1", "S3", "S7", "S12").map { studentMember(it) },
            loaded = true,
        ),
        MyClass(
            id = "1ZAUDXCORE",
            subject = "Core meetings",
            subjectCode = "CORE",
            year = "1",
            block = "Z",
            level = ClassLevel.NONE,
            room = ClassRoom(id = "aud", name = "Auditorium"),
            teachers = listOf(teacherMember("T5")),
            students = demoStudents.map { studentMember(it.id) },
            loaded = true,
        ),
    )

    fun homePage(): dk.betterw4.android.feature.home.HomePage =
        dk.betterw4.android.feature.home.HomePage(
            greetingText = "Hello Demo Student",
            greetingName = "Demo Student",
            uwcId = "nc00demo",
            birthdaysToday = listOf(
                dk.betterw4.android.feature.home.HomeBirthday("nc16demo", isStaff = true),
                dk.betterw4.android.feature.home.HomeBirthday("nc25demo", isStaff = false),
            ),
            announcementsEmptyText = "No announcements...",
            links = listOf(
                dk.betterw4.android.feature.home.HomeLink(
                    title = "ManageBac",
                    url = "https://uwcrcn.managebac.com/",
                ),
                dk.betterw4.android.feature.home.HomeLink(
                    title = "Trip Form",
                    url = "https://w4.uwcrcn.no/index.php?r=academics/trips",
                    route = "academics/trips",
                ),
            ),
            serverVersion = "25.9.1",
        )

    fun extraAcademicsHtml(page: String): String = when (page) {
        "diary" -> "<h2>My EA diary</h2><p>No diary entries this week.</p>"
        "portfolio" -> "<h2>My portfolio</h2><p>Nothing in your portfolio yet.</p>"
        "interviews" -> "<h2>My CAS interviews</h2><p>Interview 1 of 3 completed.</p>"
        "safetynet" -> "<h2>My SafetyNet</h2><p>Average wellness 4.2 · Sleep 7h · Exercise 3.</p>"
        else -> "<div id=\"content_inner\"><h2>My activities</h2><p>Badminton — Tuesday 16:00 — running.</p></div>"
    }.let { html ->
        if (html.contains("content_inner")) html
        else "<div id=\"content_inner\">$html</div>"
    }
}
