package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectorySearchTest {
    private val items = listOf(
        DirectoryEntity("1", "Anna Andersen", DirectoryEntityKind.STUDENT, "3x"),
        DirectoryEntity("2", "Bo Berg", DirectoryEntityKind.STUDENT, "2y"),
        DirectoryEntity("3", "Jens Jensen", DirectoryEntityKind.TEACHER, "Matematik"),
        DirectoryEntity("4", "201", DirectoryEntityKind.ROOM, "Bygning A"),
    )

    @Test
    fun rank_pins_first() {
        val ranked = DirectorySearch.rank(items, query = "", pinnedIds = setOf("3"))
        assertEquals("3", ranked.first().id)
    }

    @Test
    fun rank_prefix_beats_substring() {
        val ranked = DirectorySearch.rank(items, query = "an")
        assertEquals("Anna Andersen", ranked.first().name)
    }

    @Test
    fun classmates_filters_by_class() {
        val mates = DirectorySearch.classmates(items, "3x")
        assertEquals(1, mates.size)
        assertEquals("Anna Andersen", mates.first().name)
    }

    @Test
    fun empty_query_keeps_all_with_pin_order() {
        val ranked = DirectorySearch.rank(items, "", pinnedIds = setOf("4"))
        assertEquals(4, ranked.size)
        assertTrue(ranked.first().id == "4")
    }
}
