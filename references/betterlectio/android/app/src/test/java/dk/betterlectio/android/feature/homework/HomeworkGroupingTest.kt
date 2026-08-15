package dk.betterlectio.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class HomeworkGroupingTest {
    @Test
    fun groupedByDate_sortsDatesAndNullLast() {
        val items = listOf(
            HomeworkItem("1", "Note B", "Act B", LocalDate.of(2026, 3, 12)),
            HomeworkItem("2", "Note A", "Act A", LocalDate.of(2026, 3, 10)),
            HomeworkItem("3", "No date", "Later", null),
            HomeworkItem("4", "Same day", "Act C", LocalDate.of(2026, 3, 10)),
        )
        val groups = items.groupedByDate()
        assertEquals(3, groups.size)
        assertEquals(LocalDate.of(2026, 3, 10), groups[0].date)
        assertEquals(2, groups[0].items.size)
        assertEquals(LocalDate.of(2026, 3, 12), groups[1].date)
        assertNull(groups[2].date)
        assertEquals("Uden dato", groups[2].label)
    }
}
