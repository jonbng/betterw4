package dk.betterw4.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class AssessmentMonthTest {
    @Test
    fun query_zeroPadsMonth() {
        val august = AssessmentMonth(2026, 8)
        assertEquals("2026-08", august.key)
        assertEquals(mapOf("month" to "08", "year" to "2026"), august.query)
        assertEquals("August 2026", august.title())
    }

    @Test
    fun offset_rollsYear() {
        val august = AssessmentMonth(2026, 8)
        assertEquals(AssessmentMonth(2026, 9), august.offset(1))
        assertEquals(AssessmentMonth(2026, 7), august.offset(-1))
        assertEquals(AssessmentMonth(2027, 1), AssessmentMonth(2026, 12).offset(1))
        assertEquals(AssessmentMonth(2025, 12), AssessmentMonth(2026, 1).offset(-1))
    }

    @Test
    fun calendarDays_mondayFirstAndPadsNeighbours() {
        val month = AssessmentMonth(2026, 8)
        val items = listOf(
            HomeworkItem("1", "Essay", "English", LocalDate.of(2026, 8, 20)),
            HomeworkItem("2", "Done", "Maths", LocalDate.of(2026, 8, 3), done = true),
        )
        val days = assessmentCalendarDays(month, items, today = LocalDate.of(2026, 8, 18))
        assertEquals(LocalDate.of(2026, 7, 27), days.first().date)
        assertEquals(0, days.size % 7)
        val twentieth = days.first { it.date == LocalDate.of(2026, 8, 20) }
        assertTrue(twentieth.isInMonth)
        assertEquals(1, twentieth.total)
        assertEquals(1, twentieth.pending)
        val third = days.first { it.date == LocalDate.of(2026, 8, 3) }
        assertEquals(1, third.total)
        assertEquals(0, third.pending)
        val neighbour = days.first()
        assertFalse(neighbour.isInMonth)
    }
}
