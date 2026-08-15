package dk.betterlectio.android.feature.assignments

import org.junit.Assert.assertEquals
import org.junit.Test

class AssignmentParserTest {
    @Test
    fun parses_assignments_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/assignments_list.html")!!
            .bufferedReader().readText()
        val items = AssignmentParser.parseList(html)
        assertEquals(1, items.size)
        assertEquals("555", items[0].id)
        assertEquals("Rapport", items[0].title)
        assertEquals("Fy B", items[0].team)
        assertEquals("HE555", items[0].holdElementId)
        assertEquals(11, items[0].week)
        assertEquals(5.0, items[0].studentTime, 0.01)
        assertEquals("Venter", items[0].status)
        assertEquals("7", items[0].grade)
        assertEquals("Fin", items[0].gradeNote)
        assertEquals("OK", items[0].studentNote)
    }
}

