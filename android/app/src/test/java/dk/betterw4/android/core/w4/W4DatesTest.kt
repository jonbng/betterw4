package dk.betterw4.android.core.w4

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.ZonedDateTime

class W4DatesTest {

    @Test
    fun formats_en_gb_dd_mmm_yyyy() {
        assertEquals("14-Aug-2026", W4Dates.format(LocalDate.of(2026, 8, 14)))
    }

    @Test
    fun parses_captured_datepicker_shapes() {
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("14-Aug-2026"))
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("14-Aug-26"))
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("2026-08-14"))
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("14/8/2026"))
        assertNull(W4Dates.parse(""))
    }

    @Test
    fun millis_until_next_oslo_minute_is_the_remainder() {
        val atMinute = ZonedDateTime.of(2026, 8, 14, 13, 34, 0, 0, W4Dates.ZONE)
        assertEquals(60_000L, W4Dates.millisUntilNextMinute(atMinute))

        val midMinute = ZonedDateTime.of(2026, 8, 14, 13, 34, 15, 0, W4Dates.ZONE)
        assertEquals(45_000L, W4Dates.millisUntilNextMinute(midMinute))

        val lastMilli = ZonedDateTime.of(2026, 8, 14, 13, 34, 59, 999_000_000, W4Dates.ZONE)
        assertEquals(1L, W4Dates.millisUntilNextMinute(lastMilli))
    }

    @Test
    fun now_is_oslo_wall_clock_not_the_phone_zone() {
        val utcMidnight = LocalDateTime.of(2026, 8, 14, 0, 0)
        val oslo = utcMidnight.atZone(W4Dates.ZONE)
        val utc = utcMidnight.atZone(ZoneOffset.UTC)
        assertTrue(oslo.toInstant() != utc.toInstant())
        assertEquals("Europe/Oslo", W4Dates.ZONE.id)
    }
}
