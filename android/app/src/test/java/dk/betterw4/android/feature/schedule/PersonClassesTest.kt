package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PersonClassesTest {
    private val liveWeek = javaClass.classLoader!!
        .getResourceAsStream("w4/timetable-live-week.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun live_week_lists_linked_class_names_not_breakfast() {
        val week = W4TimetableParser.parseWeek(liveWeek, 2026, 35, source = "ac")
        val classes = PersonClasses.fromWeek(week)
        assertTrue(classes.any { it.name == "Economics" && it.id == "1EA16CECOX" })
        assertTrue(
            classes.any {
                it.name == "Mathematics Analysis and Approaches" && it.id == "1DA13HMTAA"
            },
        )
        assertTrue(classes.none { it.name.equals("Breakfast", ignoreCase = true) })
        assertTrue(classes.all { it.canOpen })
    }

    @Test
    fun merge_keeps_room_from_profile_when_week_only_has_name() {
        val merged = PersonClasses.merge(
            listOf(PersonClass(id = "1EA16CECOX", name = "Economics", year = "1", room = "A 1.6")),
            listOf(PersonClass(id = "1EA16CECOX", name = "Economics")),
        )
        assertEquals("A 1.6", merged.single().room)
        assertEquals("1", merged.single().year)
    }

    fun merge_is_case_insensitive_and_sorted() {
        assertEquals(
            listOf(
                PersonClass(id = "BIO", name = "biology"),
                PersonClass(id = "ECO", name = "Economics"),
            ),
            PersonClasses.merge(
                listOf(PersonClass(id = "ECO", name = "Economics")),
                listOf(
                    PersonClass(id = "BIO", name = "biology"),
                    PersonClass(id = "ECO", name = "Economics"),
                ),
            ),
        )
    }
}
