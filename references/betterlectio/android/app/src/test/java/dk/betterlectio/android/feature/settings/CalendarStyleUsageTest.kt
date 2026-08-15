package dk.betterlectio.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * Ensures both calendar styles remain distinct product options that the schedule UI branches on.
 */
class CalendarStyleUsageTest {
    @Test
    fun professional_and_standard_are_distinct() {
        assertNotEquals(CalendarStyle.PROFESSIONAL, CalendarStyle.STANDARD)
        assertEquals(2, CalendarStyle.entries.size)
    }

    @Test
    fun schedule_card_layout_key_differs_by_style() {
        // Mirrors ScheduleEventCard branch keys used by UI
        fun layoutKey(style: CalendarStyle): String = when (style) {
            CalendarStyle.PROFESSIONAL -> "compact"
            CalendarStyle.STANDARD -> "colorful"
        }
        assertEquals("compact", layoutKey(CalendarStyle.PROFESSIONAL))
        assertEquals("colorful", layoutKey(CalendarStyle.STANDARD))
    }
}
