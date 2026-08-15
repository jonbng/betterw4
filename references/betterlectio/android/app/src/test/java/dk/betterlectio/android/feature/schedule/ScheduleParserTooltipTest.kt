package dk.betterlectio.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class ScheduleParserTooltipTest {
    @Test
    fun title_prefers_free_title_when_hold_not_digit_prefix() {
        val tip = ScheduleParser.parseTooltip(
            """
            Ændret!
            Matematik A
            10/3-2026 08:15 til 09:15
            Hold: Ma A
            Lærer: Jens
            Lokale: 201
            Lektier:
            Opg. 1-5
            side 12
            """.trimIndent(),
            LocalDate.of(2026, 3, 10),
        )
        assertEquals("Matematik A", tip.title)
        assertEquals("Ma A", tip.holdName)
        assertTrue(tip.homework!!.contains("Opg. 1-5"))
        assertTrue(tip.homework!!.contains("side 12"))
        assertEquals(8, tip.start!!.hour)
    }

    @Test
    fun title_prefers_digit_hold() {
        val tip = ScheduleParser.parseTooltip(
            """
            Stemmeretten
            Hold: 1x Sa
            """.trimIndent(),
            LocalDate.of(2026, 3, 10),
        )
        assertEquals("1x Sa", tip.title)
    }

    @Test
    fun contentBasedId_is_stable_sha256() {
        val a = ScheduleParser.contentBasedId(LocalDate.of(2026, 3, 10), "Hele dagen\nFest")
        val b = ScheduleParser.contentBasedId(LocalDate.of(2026, 3, 10), "Hele dagen\nFest")
        assertEquals(a, b)
        assertTrue(a.startsWith("AD"))
        assertEquals(34, a.length) // AD + 32 hex chars (16 bytes)
    }

    @Test
    fun week_fixture_uses_activity_title_not_brick_text() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/schedule_week.html")!!
            .bufferedReader().readText()
        val week = ScheduleParser.parseWeek(html, 2026, 11)
        val mon = week.days.first()
        assertEquals("Matematik A", mon.events[0].title)
        assertEquals("Ma A", mon.events[0].team)
        assertTrue(mon.events[0].homework!!.contains("Opg. 1-5"))
    }
}
