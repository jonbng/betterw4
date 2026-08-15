package dk.betterlectio.android.core.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.time.LocalDate

class LectioDateUtilsTest {
    @Test
    fun parseWeekdayPrefixed_homework_dates() {
        val d = LectioDateUtils.parseWeekdayPrefixedDate("fr 13/3", defaultYear = 2026)
        assertEquals(LocalDate.of(2026, 3, 13), d)
        assertEquals(
            LocalDate.of(2026, 3, 16),
            LectioDateUtils.parseWeekdayPrefixedDate("ma 16/3", 2026),
        )
    }

    @Test
    fun parseLectioDate_weekday_prefix_via_main_entry() {
        val dt = LectioDateUtils.parseLectioDate("fr 11/3", defaultYear = 2026)
        assertNotNull(dt)
        assertEquals(LocalDate.of(2026, 3, 11), dt!!.toLocalDate())
    }

    @Test
    fun parseLectioDate_message_timestamp() {
        val dt = LectioDateUtils.parseLectioDate("04-03-2026 11:05:41")
        assertNotNull(dt)
        assertEquals(11, dt!!.hour)
        assertEquals(5, dt.minute)
    }

    @Test
    fun parseTimeRange_til_and_dash() {
        val til = LectioDateUtils.parseTimeRange("10/3-2026 08:15 til 09:15")
        assertNotNull(til)
        assertEquals(8, til!!.first.hour)
        assertEquals(9, til.second.hour)

        val dash = LectioDateUtils.parseTimeRange("08:15-09:15")
        assertNotNull(dash)
    }
}
