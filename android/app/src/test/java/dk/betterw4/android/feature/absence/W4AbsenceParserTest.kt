package dk.betterw4.android.feature.absence

import dk.betterw4.android.feature.schedule.LessonAttendance
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class W4AbsenceParserTest {
    private fun load(name: String): String = javaClass.classLoader!!
        .getResourceAsStream("w4/$name")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_home_meters_from_chrome() {
        val meters = W4AbsenceParser.parseHomeMeters(load("campus-chrome.html"))
        assertEquals(W4AbsenceMeter(2, 1), meters.academic)
        assertEquals(W4AbsenceMeter(0, 0), meters.ea)
    }

    @Test
    fun empty_list_is_empty_not_an_error() {
        val page = W4AbsenceParser.parseList(load("absences-list-empty.html"), AbsenceSource.ACADEMICS)
        assertTrue(page.registrations.isEmpty())
        assertNull(page.meter)
    }

    @Test
    fun empty_ea_list_is_empty() {
        val page = W4AbsenceParser.parseList(load("ea-absences-list-empty.html"), AbsenceSource.EA)
        assertTrue(page.registrations.isEmpty())
    }

    @Test
    fun list_maps_real_headers() {
        val page = W4AbsenceParser.parseList(load("absences-list-rows.html"), AbsenceSource.ACADEMICS)
        assertEquals(3, page.registrations.size)
        val first = page.registrations[0]
        assertEquals(LocalDate.of(2026, 8, 4), first.date)
        assertEquals("Mathematics HL", first.team)
        assertEquals("A. Teacher", first.addedBy)
        assertEquals("Absent", first.studentWas)
        assertEquals("Absence", first.cause)
        assertFalse(first.editable)
        val late = page.registrations[1]
        assertTrue(W4AbsenceParser.isLateness(late.cause) || W4AbsenceParser.isLateness(late.studentWas))
        assertEquals("Bus delay", late.note)
        val prearranged = page.registrations[2]
        assertEquals("History HL", prearranged.team)
        assertEquals("College trip", prearranged.note)
    }

    @Test
    fun week_grid_is_not_a_list() {
        val page = W4AbsenceParser.parseList(load("absences-week-classes.html"), AbsenceSource.ACADEMICS)
        assertTrue(page.registrations.isEmpty())
    }

    @Test
    fun week_empty_has_no_class_lessons() {
        val week = W4AbsenceParser.parseWeek(load("absences-week-empty.html"), AbsenceSource.ACADEMICS)
        val marked = week.days.flatMap { it.events }.filter { it.attendance != null }
        assertTrue(marked.isEmpty())
    }

    @Test
    fun week_classes_mark_unchecked_on_lessons() {
        val week = W4AbsenceParser.parseWeek(
            load("absences-week-classes.html"),
            AbsenceSource.ACADEMICS,
            fallbackYear = 2026,
            fallbackWeek = 36,
        )
        val events = week.days.flatMap { it.events }
        val marked = events.filter { it.attendance != null }
        assertTrue(
            "days=${week.days.size} events=${events.size} marked=${marked.size} sample=${events.take(6).map { it.title to it.attendance }}",
            marked.size >= 8,
        )
        assertTrue(marked.all { it.attendance == LessonAttendance.UNCHECKED })
        assertEquals("no absence", marked.first().attendanceTooltip)
        assertTrue(marked.any { it.title.contains("Economics", ignoreCase = true) })
        val unmarked = week.days.flatMap { it.events }.filter { it.attendance == null }
        assertTrue(unmarked.any { it.title.contains("Breakfast", ignoreCase = true) || it.title.contains("Break", ignoreCase = true) })
    }

    @Test
    fun register_empty_day() {
        val form = W4AbsenceParser.parseRegisterForm(load("absences-register-empty-day.html"))
        assertTrue(form.slots.isEmpty())
        assertNotNull(form.emptyDayMessage)
        assertTrue(form.isEmptyDay)
    }

    @Test
    fun register_class_day_has_slots() {
        val form = W4AbsenceParser.parseRegisterForm(load("absences-register-class-day.html"))
        assertEquals("31-Aug-2026", form.dateRaw)
        assertNull(form.emptyDayMessage)
        assertEquals(3, form.slots.size)
        assertTrue(form.slots[0].value.contains("_"))
        assertTrue(form.slots.any { it.label.contains("Economics") })
    }

    @Test
    fun submission_error_is_read_from_yii_error_markup() {
        val html = """
            <form><div class="errorMessage">Please select at least one class.</div></form>
        """.trimIndent()
        assertEquals("Please select at least one class.", W4AbsenceParser.parseSubmissionError(html))
    }

    @Test
    fun successful_submission_has_no_error() {
        assertNull(W4AbsenceParser.parseSubmissionError("<main>Registration saved.</main>"))
    }

    @Test
    fun register_payload_uses_the_captured_repeated_checkbox_name() {
        val fields = absenceRegisterFields(
            dateRaw = "31-Aug-2026",
            slotValues = listOf("CLASS_A_08:15", "CLASS_B_10:10"),
            reason = "Appointment",
            wholeDay = false,
        )
        assertEquals(
            listOf("CLASS_A_08:15", "CLASS_B_10:10"),
            fields.filter { it.first == "StudentAbsenceForm[absences][]" }.map { it.second },
        )
        assertTrue(fields.contains("StudentAbsenceForm[absences]" to ""))
        assertTrue(fields.contains("yt0" to "Register absences"))
    }
}
