package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalTime

class W4TimetableParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/timetable-week.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_header_dates_and_period_blocks() {
        val week = W4TimetableParser.parseWeek(html, year = 2026, week = 33)
        assertEquals(7, week.days.size)
        val monday = week.days[0]
        assertEquals(1, monday.events.size)
        val bio = monday.events[0]
        assertEquals("Biology HL", bio.title)
        assertEquals("A 2.1", bio.room)
        assertEquals(LocalTime.of(8, 0), bio.start?.toLocalTime())
        assertEquals(LocalTime.of(9, 0), bio.end?.toLocalTime())

        val wednesday = week.days[2]
        assertEquals("TOK", wednesday.events.single().title)
        assertEquals(LocalTime.of(9, 0), wednesday.events.single().start?.toLocalTime())
        assertEquals(LocalTime.of(11, 0), wednesday.events.single().end?.toLocalTime())

        assertTrue(week.days[5].events.isEmpty())
        assertTrue(week.days[6].events.isEmpty())
    }

    @Test
    fun merge_combines_ac_and_ea_without_dropping_days() {
        val ac = W4TimetableParser.parseWeek(html, 2026, 33, source = "ac")
        val ea = ac.copy(
            days = ac.days.map { day ->
                if (day.date.dayOfMonth == 10) {
                    day.copy(
                        events = listOf(
                            day.events.first().copy(
                                id = "ea-1",
                                title = "Badminton",
                                team = "EA",
                            ),
                        ),
                    )
                } else {
                    day.copy(events = emptyList())
                }
            },
        )
        val merged = W4TimetableParser.mergeWeeks(ac, ea)
        assertEquals(2, merged.days[0].events.size)
        assertEquals(7, merged.days.size)
    }
}
