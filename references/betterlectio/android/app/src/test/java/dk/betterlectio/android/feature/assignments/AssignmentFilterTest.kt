package dk.betterlectio.android.feature.assignments

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AssignmentFilterTest {
    private fun item(status: String, awaits: String = "") = AssignmentItem(
        id = "1",
        title = "T",
        team = "Mat",
        week = 10,
        deadline = null,
        status = status,
        studentTime = 2.0,
        awaits = awaits,
        note = "",
    )

    @Test
    fun awaitingMe_matchesElevOrMangler() {
        assertTrue(item("Afventer", "Elev").matches(AssignmentFilter.AWAITING_ME))
        assertTrue(item("Mangler aflevering").matches(AssignmentFilter.AWAITING_ME))
        assertFalse(item("Afleveret", "Lærer").matches(AssignmentFilter.AWAITING_ME))
    }

    @Test
    fun delivered_matchesAfleveret() {
        assertTrue(item("Afleveret", "Lærer").matches(AssignmentFilter.DELIVERED))
        assertTrue(item("Afsluttet").matches(AssignmentFilter.DELIVERED))
        assertFalse(item("Mangler").matches(AssignmentFilter.DELIVERED))
    }

    @Test
    fun missing_matchesMangler() {
        assertTrue(item("Mangler").matches(AssignmentFilter.MISSING))
        assertFalse(item("Afleveret").matches(AssignmentFilter.MISSING))
    }

    @Test
    fun all_alwaysMatches() {
        assertTrue(item("Anything").matches(AssignmentFilter.ALL))
    }
}
