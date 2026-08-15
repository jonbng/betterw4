package dk.betterlectio.android.feature.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationSnapshotDiffTest {
    @Test
    fun newIds_returnsOnlyFreshKeys() {
        val previous = setOf("a", "b")
        val current = setOf("a", "b", "c", "d")
        val fresh = NotificationSnapshotDiff.newIds(previous, current)
        assertEquals(setOf("c", "d"), fresh)
    }

    @Test
    fun newIds_emptyPrevious_returnsAll() {
        val current = setOf("x", "y")
        assertEquals(current, NotificationSnapshotDiff.newIds(emptySet(), current))
    }

    @Test
    fun newIds_noChange_empty() {
        val keys = setOf("a")
        assertTrue(NotificationSnapshotDiff.newIds(keys, keys).isEmpty())
    }

    @Test
    fun keyHelpers_areStable() {
        assertEquals("event:1:CANCELLED", NotificationSnapshotDiff.eventKey("1", "CANCELLED"))
        assertEquals("msg:42", NotificationSnapshotDiff.messageKey("42"))
        assertEquals("asg:9:Afleveret", NotificationSnapshotDiff.assignmentKey("9", "Afleveret"))
    }
}
