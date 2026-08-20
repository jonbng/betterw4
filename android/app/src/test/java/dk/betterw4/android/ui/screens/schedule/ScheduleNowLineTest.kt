package dk.betterw4.android.ui.screens.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

class ScheduleNowLineTest {
    private val friday = LocalDate.of(2026, 8, 14)

    @Test
    fun captured_home_page_now_line_sits_at_394_from_07_00() {
        // W4's own #current_time was top: 394px on a 07:00 grid = 13:34 Oslo.
        val now = LocalDateTime.of(2026, 8, 14, 13, 34)
        assertEquals(
            394,
            ScheduleNowLine.minutesFromOrigin(
                now = now,
                date = friday,
                originHour = 7,
                spanMinutes = 15 * 60,
            ),
        )
    }

    @Test
    fun line_is_hidden_on_another_day() {
        val now = LocalDateTime.of(2026, 8, 14, 13, 34)
        assertNull(
            ScheduleNowLine.minutesFromOrigin(
                now = now,
                date = friday.minusDays(1),
                originHour = 7,
                spanMinutes = 15 * 60,
            ),
        )
    }

    @Test
    fun line_is_hidden_before_the_origin() {
        val now = LocalDateTime.of(2026, 8, 14, 7, 45)
        assertNull(
            ScheduleNowLine.minutesFromOrigin(
                now = now,
                date = friday,
                originHour = 8,
                spanMinutes = 8 * 60,
            ),
        )
    }

    @Test
    fun seconds_do_not_move_the_line_until_the_next_minute() {
        val almost = LocalDateTime.of(2026, 8, 14, 13, 34, 59)
        assertEquals(
            394,
            ScheduleNowLine.minutesFromOrigin(
                now = almost,
                date = friday,
                originHour = 7,
                spanMinutes = 15 * 60,
            ),
        )
    }

    @Test
    fun line_tracks_the_clock_across_an_hour() {
        val justAfter = LocalDateTime.of(2026, 8, 14, 13, 35)
        assertEquals(
            395,
            ScheduleNowLine.minutesFromOrigin(
                now = justAfter,
                date = friday,
                originHour = 7,
                spanMinutes = 15 * 60,
            ),
        )
    }
}
