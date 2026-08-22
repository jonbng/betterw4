package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class PersonBirthdayTest {

    @Test
    fun parses_w4_short_month() {
        val parsed = PersonBirthday.parse("28-Jan")!!
        assertEquals(1, parsed.month)
        assertEquals(28, parsed.day)
        assertEquals("28 January", parsed.display)
    }

    @Test
    fun parses_staff_short_month() {
        val parsed = PersonBirthday.parse("17-Nov")!!
        assertEquals(11, parsed.month)
        assertEquals(17, parsed.day)
        assertEquals("17 November", parsed.display)
    }

    @Test
    fun parses_long_month_and_strips_year() {
        val parsed = PersonBirthday.parse("1 January 2008")!!
        assertEquals(1, parsed.month)
        assertEquals(1, parsed.day)
        assertEquals("1 January", parsed.display)
    }

    @Test
    fun days_until_today_and_tomorrow() {
        val today = LocalDate.of(2026, 8, 21)
        val same = PersonBirthday.parse("21-Aug")!!
        assertEquals(0, same.daysUntil(today))

        val tomorrow = PersonBirthday.parse("22-Aug")!!
        assertEquals(1, tomorrow.daysUntil(today))

        val january = PersonBirthday.parse("28-Jan")!!
        assertEquals(160, january.daysUntil(today))
    }

    @Test
    fun feb_29_clamps_in_common_year() {
        val today = LocalDate.of(2026, 2, 28)
        val parsed = PersonBirthday.parse("29-Feb")!!
        assertEquals(0, parsed.daysUntil(today))
    }

    @Test
    fun blank_is_null() {
        assertNull(PersonBirthday.parse(" "))
        assertNull(PersonBirthday.parse(null))
    }
}
