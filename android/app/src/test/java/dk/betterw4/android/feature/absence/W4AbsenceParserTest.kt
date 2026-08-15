package dk.betterw4.android.feature.absence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun parses_ac_list_and_meter() {
        val page = W4AbsenceParser.parseList(load("absences.html"), AbsenceSource.ACADEMICS)
        assertEquals(W4AbsenceMeter(2, 1), page.meter)
        assertEquals(3, page.registrations.size)
        val first = page.registrations[0]
        assertEquals(LocalDate.of(2026, 8, 4), first.date)
        assertEquals("Mathematics HL", first.team)
        assertEquals("Absence", first.cause)
        assertEquals("Academics", first.lessonTitle)
        assertFalse(first.editable)
        val late = page.registrations[1]
        assertEquals("Lateness", late.cause)
        assertEquals("Bus delay", late.note)
        assertTrue(W4AbsenceParser.isLateness(late.cause))
        assertEquals(LocalDate.of(2026, 8, 11), page.registrations[2].date)
    }

    @Test
    fun parses_empty_ea_list() {
        val page = W4AbsenceParser.parseList(load("ea-absences.html"), AbsenceSource.EA)
        assertEquals(W4AbsenceMeter(0, 0), page.meter)
        assertTrue(page.registrations.isEmpty())
    }
}
