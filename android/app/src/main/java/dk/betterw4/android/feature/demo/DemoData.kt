package dk.betterw4.android.feature.demo

import dk.betterw4.android.core.model.School
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.feature.absence.AbsenceOverview
import dk.betterw4.android.feature.absence.AbsenceRegistration
import dk.betterw4.android.feature.absence.W4AbsenceMeter
import dk.betterw4.android.feature.assignments.AssignmentItem
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
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
        School(1, "Demo Gymnasium Nord"),
        School(94, "Sorø Akademis Skole"),
        School(256, "Gammel Hellerup Gymnasium"),
        School(517, "Nørre Gymnasium"),
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
                        title = "Matematik A",
                        team = "Ma A",
                        teacher = "Jens Jensen",
                        room = "201",
                        status = EventStatus.NORMAL,
                        start = LocalDateTime.of(date, LocalTime.of(8, 15)),
                        end = LocalDateTime.of(date, LocalTime.of(9, 15)),
                        date = date,
                        homework = "Opg. 12–15",
                    ),
                    ScheduleEvent(
                        id = "demo2-$offset",
                        title = "Dansk A",
                        team = "Da A",
                        teacher = "Anne Andersen",
                        room = "105",
                        status = if (offset == 1) EventStatus.CHANGED else EventStatus.NORMAL,
                        start = LocalDateTime.of(date, LocalTime.of(9, 25)),
                        end = LocalDateTime.of(date, LocalTime.of(10, 25)),
                        date = date,
                    ),
                    ScheduleEvent(
                        id = "demo3-$offset",
                        title = "Fysik B",
                        team = "Fy B",
                        teacher = "Peter Petersen",
                        room = "Lab 1",
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
                        title = "Historie B",
                        team = "Hi B",
                        teacher = "Mette Madsen",
                        room = "312",
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
            topic = "Velkommen til BetterW4 demo",
            sender = "System",
            dateChanged = LocalDateTime.now().minusHours(2),
            folderId = MessageFolder.UNREAD.id,
            unread = true,
        ),
        MessageThread(
            id = "m2",
            topic = "Aflevering i matematik udsat",
            sender = "Jens Jensen",
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
                topic = "Besked",
                contentHtml = "<p>Dette er en <b>demo-besked</b>. Log ind med MitID for rigtige data.</p>" +
                    "<p>Nedenfor er et indlejret billede (demo).</p>" +
                    "<img src=\"https://picsum.photos/seed/msg-demo/640/280\" alt=\"Demo figur\"/>" +
                    "<div class=\"message-attachements\"><a href=\"https://www.lectio.dk/demo.pdf\">Opgavesæt.pdf</a></div>",
                senderName = "System",
                sentAt = LocalDateTime.now().minusHours(2),
                attachments = listOf(
                    MessageAttachment("Opgavesæt.pdf", "https://www.lectio.dk/demo.pdf"),
                    MessageAttachment("diagram.png", "https://picsum.photos/seed/betterw4/640/360"),
                ),
            ),
        ),
        receivers = listOf("Demo Elev", "Jens Jensen"),
    )

    val homework = listOf(
        HomeworkItem(
            id = "h1",
            note = "Læs kapitel 4 og løs opg. 1–5",
            activityTitle = "Matematik A",
            date = LocalDate.now().plusDays(1),
            team = "Ma A",
            href = "aktivitet/aktivitetforside.aspx?absid=demo-h1",
            detailHtml = null,
        ),
        HomeworkItem(
            id = "h2",
            note = "Analyser digtet side 42–45",
            activityTitle = "Dansk A",
            date = LocalDate.now().plusDays(2),
            team = "Da A",
            href = "aktivitet/aktivitetforside.aspx?absid=demo-h2",
        ),
    )

    fun homeworkDetailHtml(item: HomeworkItem): String =
        """
        <h2>${item.activityTitle}</h2>
        <p><b>Lektie:</b> ${item.note}</p>
        <p>Demo lektieindhold for hold ${item.team}. Gennemgå materialet inden timen.</p>
        <img src="https://picsum.photos/seed/hw-${item.id}/640/280" alt="Demo figur"/>
        <ul><li>Medbring bog</li><li>Noter fra sidste gang</li></ul>
        """.trimIndent()

    val assignments = listOf(
        AssignmentItem(
            id = "a1",
            title = "Rapport om bølger",
            team = "Fy B",
            week = IsoDateUtils.isoWeek(),
            deadline = LocalDateTime.now().plusDays(5).withHour(23).withMinute(59),
            status = "Afventer",
            studentTime = 5.0,
            awaits = "Elev",
            note = "",
        ),
        AssignmentItem(
            id = "a2",
            title = "Essay: modernisme",
            team = "Da A",
            week = IsoDateUtils.isoWeek() + 1,
            deadline = LocalDateTime.now().plusDays(12).withHour(12).withMinute(0),
            status = "Afleveret",
            studentTime = 8.0,
            awaits = "Lærer",
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

    val directory = listOf(
        DirectoryEntity(
            "S1", "Demo Elev", DirectoryEntityKind.STUDENT, "3x",
            avatarUrl = "https://www.gravatar.com/avatar/11111111111111111111111111111111?d=identicon&s=128",
        ),
        DirectoryEntity(
            "T1", "Jens Jensen", DirectoryEntityKind.TEACHER, "Matematik",
            avatarUrl = "https://www.gravatar.com/avatar/22222222222222222222222222222222?d=identicon&s=128",
        ),
        DirectoryEntity("SC1", "3x", DirectoryEntityKind.CLASS, null),
        DirectoryEntity("RO1", "201", DirectoryEntityKind.ROOM, "Bygning A"),
        DirectoryEntity(
            "S2", "Anna Andersen", DirectoryEntityKind.STUDENT, "3x",
            avatarUrl = "https://www.gravatar.com/avatar/33333333333333333333333333333333?d=identicon&s=128",
        ),
    )

    val plans = listOf(
        StudyPlan("p1", "Matematik A – studieplan", "Ma A"),
        StudyPlan("p2", "Dansk A – studieplan", "Da A"),
    )

    val moduleStats = listOf(
        ModuleStat("Ma A", 120, 4, 2),
        ModuleStat("Da A", 110, 6, 1),
        ModuleStat("Fy B", 90, 10, 0),
    )

    fun lessonDetail(event: ScheduleEvent) = LessonDetail(
        eventId = event.id,
        title = event.title,
        note = event.notes ?: "Demo-note: medbring lommeregner.",
        homework = event.homework ?: "Læs kap. 3",
        contentBlocks = listOf(
            LessonContentBlock("heading", "Læs kap. 3", isHomework = true),
            LessonContentBlock("paragraph", "Gennemgå opgaverne i bogen.", isHomework = true),
            LessonContentBlock("heading", "I timen", isHomework = false),
            LessonContentBlock("paragraph", "Gennemgang af opgaver og fælles opsamling.", isHomework = false),
            LessonContentBlock(
                kind = "image",
                text = "Tavle-figur",
                url = "https://picsum.photos/seed/lesson-${event.id}/640/300",
                isHomework = false,
            ),
            LessonContentBlock("note", "Husk bog.", isHomework = false),
        ),
        participants = listOf(
            LessonParticipant(
                id = "T1",
                name = "Jens Jensen",
                role = "Lærer",
                kind = DirectoryEntityKind.TEACHER,
            ),
            LessonParticipant(
                id = "S1",
                name = "Demo Elev",
                role = "Elev",
                kind = DirectoryEntityKind.STUDENT,
            ),
            LessonParticipant(
                id = "S2",
                name = "Anna Andersen",
                role = "Elev",
                kind = DirectoryEntityKind.STUDENT,
            ),
        ),
        resources = listOf(
            LessonResource("Opgavesæt (PDF)", "https://www.lectio.dk/", isFile = true),
            LessonResource("Geogebra", "https://www.geogebra.org/", isFile = false),
        ),
        holdId = "HE1",
    )

    val directoryMembers = mapOf(
        "SC1" to listOf(
            DirectoryEntity("S1", "Demo Elev", DirectoryEntityKind.STUDENT, "3x"),
            DirectoryEntity("S2", "Anna Andersen", DirectoryEntityKind.STUDENT, "3x"),
            DirectoryEntity("S3", "Bo Berg", DirectoryEntityKind.STUDENT, "3x"),
        ),
    )

}
