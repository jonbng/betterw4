package dk.betterw4.android.feature.demo

import dk.betterw4.android.core.model.Student
import dk.betterw4.android.core.model.W4School
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.onduty.OnDutyRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Lectio original was a Danish gymnasium. Demo copy a reviewer sees must stay English
 * and UWC-shaped — a single Danish character or Lectio token creeping back in is the
 * regression this file exists to catch.
 */
class DemoDataTest {

    @Test
    fun catalogueIsEnglishAndFreeOfLectio() {
        val danish = Regex("[æøåÆØÅ]")
        val lectioTokens = listOf(
            "lectio",
            "lektier",
            "lektie",
            "opgaver",
            "skema",
            "besked",
            "aflyst",
            "gymid",
            "mitid",
            "gymnasium",
            "aflever",
        )

        for (text in allUserFacingText()) {
            assertNull(
                "Demo content must be English — found a Danish character in: $text",
                danish.find(text),
            )
            val lowered = text.lowercase()
            for (token in lectioTokens) {
                assertFalse(
                    "Demo content must not carry the Lectio token '$token' — found in: $text",
                    lowered.contains(token),
                )
            }
        }
    }

    @Test
    fun identityIsUwcShaped() {
        assertEquals("Demo Student", Student.Demo.name)
        assertTrue(Student.Demo.classLabel!!.startsWith("Year "))
        assertEquals(W4School.NAME, Student.Demo.schoolName)
        assertEquals("Demo Student", DemoData.homePage().greetingName)
        assertTrue(DemoData.directory.any { it.name == "Demo Student" })
        assertTrue(DemoData.myClasses.any { item -> item.students.any { it.name == "Demo Student" } })
    }

    @Test
    fun directoryIsAnInternationalCollege() {
        val students = DemoData.directory.filter { it.kind == DirectoryEntityKind.STUDENT }
        assertTrue(students.size >= 16)
        assertFalse(DemoData.directory.any { it.name.contains("Andersen") })
        assertFalse(DemoData.directory.any { it.name.contains("Jensen") })
        assertTrue(students.any { it.name == "Bea Beltran" })
        assertTrue(students.any { it.name == "Dana Dlamini" })
        assertTrue(students.any { it.name == "Amara Okonkwo" })
        assertEquals(5, DemoData.houses.size)
        assertTrue(DemoData.houses.all { it.rooms.isNotEmpty() })
        assertTrue(DemoData.houses.sumOf { it.studentCount } >= 16)
        assertTrue(DemoData.myClasses.all { it.students.size >= 4 })
    }

    @Test
    fun teachingWeekIsIb() {
        val week = DemoData.scheduleWeek(IsoDateUtils.isoWeekYear(), IsoDateUtils.isoWeek())
        val titles = week.days.flatMap { it.events }.map { it.title }.toSet()
        assertTrue(titles.contains("Mathematics Analysis and Approaches"))
        assertTrue(titles.contains("Economics"))
        assertTrue(titles.contains("Physics"))
        assertTrue(titles.contains("History"))
    }

    private fun allUserFacingText(): List<String> {
        val text = mutableListOf<String>()
        text += listOfNotNull(
            Student.Demo.name,
            Student.Demo.classLabel,
            Student.Demo.schoolName,
        )
        text += DemoData.schools.map { it.name }

        val week = DemoData.scheduleWeek(IsoDateUtils.isoWeekYear(), IsoDateUtils.isoWeek())
        for (day in week.days) {
            for (event in day.events) {
                text += listOfNotNull(event.title, event.team, event.teacher, event.room, event.homework, event.notes)
                val detail = DemoData.lessonDetail(event)
                text += listOfNotNull(detail.title, detail.note, detail.homework)
                text += detail.contentBlocks.map { it.text }
                text += detail.participants.map { it.name }
                text += detail.participants.mapNotNull { it.role }
                text += detail.resources.map { it.title }
            }
        }

        for (thread in DemoData.messages) {
            text += listOf(thread.topic, thread.sender)
            val detail = DemoData.messageDetail(thread.id)
            text += detail.receivers
            for (entry in detail.entries) {
                text += listOfNotNull(entry.topic, entry.contentHtml, entry.senderName)
                text += entry.attachments.map { it.name }
            }
        }

        for (item in DemoData.homework) {
            text += listOf(item.note, item.activityTitle, item.team)
            text += DemoData.homeworkDetailHtml(item)
        }

        for (item in DemoData.assignments) {
            text += listOf(item.title, item.team, item.status, item.awaits, item.note)
        }

        text += DemoData.gradesReport.columns.map { it.label }
        text += DemoData.gradesReport.grades.map { it.subject }

        for (reg in DemoData.absence.registrations) {
            text += listOfNotNull(
                reg.team, reg.cause, reg.status, reg.activityTitle,
                reg.lessonTitle, reg.remark, reg.dateTimeLabel,
            )
        }

        for (entity in DemoData.directory) {
            text += listOfNotNull(entity.name, entity.subtitle)
        }

        text += DemoData.plans.map { it.title }
        text += DemoData.plans.map { it.team }
        text += DemoData.moduleStats.map { it.team }

        for (house in DemoData.houses) {
            text += house.name
            for (resident in house.leaders + house.rooms.flatMap { it.residents } + house.unassigned) {
                text += listOfNotNull(
                    resident.entity.name,
                    resident.entity.subtitle,
                    resident.country,
                    resident.status,
                    resident.detailLine,
                )
            }
            text += house.rooms.map { it.name }
        }

        for (item in DemoData.myClasses) {
            text += listOfNotNull(item.subject, item.subjectCode, item.levelLabel, item.room?.name)
            text += item.teachers.map { it.name }
            text += item.students.map { it.name }
        }

        val home = DemoData.homePage()
        text += listOfNotNull(
            home.greetingText,
            home.greetingName,
            home.announcementsEmptyText,
        )
        text += home.links.map { it.title }

        text += listOf("diary", "portfolio", "interviews", "safetynet", "activities")
            .map { DemoData.extraAcademicsHtml(it) }

        val onDuty = OnDutyRepository.demoSnapshot()
        text += listOfNotNull(onDuty.today.title, onDuty.today.dateLabel)
        text += onDuty.today.groups.map { it.role }
        text += onDuty.today.groups.flatMap { group -> group.people.map { it.name } }
        text += onDuty.today.groups.flatMap { group -> group.people.mapNotNull { it.role } }
        text += onDuty.upcoming.map { it.dateLabel }
        text += onDuty.upcoming.flatMap { day -> day.groups.map { it.role } }

        return text.filter { it.isNotBlank() }
    }
}
