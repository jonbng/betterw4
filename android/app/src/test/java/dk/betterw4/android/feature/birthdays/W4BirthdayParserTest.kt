package dk.betterw4.android.feature.birthdays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class W4BirthdayParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/birthdays.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun reads_month_year_and_adjacent_links() {
        val month = W4BirthdayParser.parse(html)
        assertEquals("August 2026", month.monthLabel)
        assertEquals(2026, month.year)
        assertEquals(8, month.month)
        assertEquals(BirthdayMonthRef(2026, 7), month.previous)
        assertEquals(BirthdayMonthRef(2026, 9), month.next)
    }

    @Test
    fun reads_named_people_and_kind_from_each_href() {
        val month = W4BirthdayParser.parse(html)
        val first = month.days.first { it.dayNumber == 1 }
        assertEquals(listOf("nc00aaa", "nc00bbb"), first.people.map { it.uwcId })
        assertEquals(listOf("Alex Andersen", "Bea Beltran"), first.people.map { it.displayName })
        assertEquals(listOf(false, false), first.people.map { it.isStaff })

        val second = month.days.first { it.dayNumber == 2 }
        assertEquals(listOf("nc00ccc", "nc00ddd"), second.people.map { it.uwcId })
        assertEquals(listOf(true, false), second.people.map { it.isStaff })
        assertEquals("Ann Ong'uti", second.people.last().displayName)
        assertEquals(LocalDate.of(2026, 8, 2), second.date)
    }

    @Test
    fun placeholder_photo_is_dropped_and_thumbs_are_upgraded() {
        val month = W4BirthdayParser.parse(html)
        val placeholder = month.days.first { it.dayNumber == 8 }.people.single()
        assertEquals("Eli Eriksen", placeholder.displayName)
        assertNull(placeholder.photoUrl)

        val named = month.days.first { it.dayNumber == 21 }.people.single()
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc00ggg_photo.jpg",
            named.photoUrl,
        )
    }

    @Test
    fun mixed_day_keeps_staff_and_students_together() {
        val month = W4BirthdayParser.parse(html)
        val day = month.days.first { it.dayNumber == 27 }
        assertEquals(listOf("nc00fff", "nc00hhh", "nc00iii"), day.people.map { it.uwcId })
        assertEquals(listOf(true, false, false), day.people.map { it.isStaff })
        assertEquals("Staff", day.people.first().roleLabel)
    }

    @Test
    fun empty_day_is_kept_and_no_day_cells_are_skipped() {
        val month = W4BirthdayParser.parse(html)
        assertTrue(month.days.any { it.dayNumber == 3 && it.people.isEmpty() })
        assertFalse(month.days.any { it.dayNumber == 0 })
        assertEquals(
            listOf(1, 2, 8, 21, 27, 31),
            month.daysWithPeople().map { it.dayNumber },
        )
    }

    @Test
    fun filter_drops_the_other_kind() {
        val month = W4BirthdayParser.parse(html).filtered(BirthdayKindFilter.STAFF)
        assertEquals(listOf("nc00ccc", "nc00fff"), month.people.map { it.uwcId })
        assertTrue(month.days.first { it.dayNumber == 21 }.people.isEmpty())
    }

    @Test
    fun unparseable_html_is_empty() {
        val month = W4BirthdayParser.parse("")
        assertTrue(month.isEmpty)
        assertNull(month.year)
    }
}
