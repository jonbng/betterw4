package dk.betterlectio.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleParserTest {
    @Test
    fun parses_week_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/schedule_week.html")!!
            .bufferedReader().readText()
        val week = ScheduleParser.parseWeek(html, 2026, 11)
        assertEquals(2, week.days.size)
        val mon = week.days.first()
        assertEquals(2, mon.events.size)
        assertEquals(EventStatus.CHANGED, mon.events[0].status)
        assertEquals(EventStatus.CANCELLED, mon.events[1].status)
        assertTrue(mon.events[0].title.contains("Matematik") || mon.events[0].team.contains("Ma"))
        assertEquals("201", mon.events[0].room)
    }
}
