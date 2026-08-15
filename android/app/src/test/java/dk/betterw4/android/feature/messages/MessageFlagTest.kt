package dk.betterw4.android.feature.messages

import dk.betterw4.android.feature.demo.DemoData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Drives shipped [DemoMessageState] (same code path [MessageRepository] uses in demo mode).
 * Proves toggleFlag mutates the list and loadDetail after toggle returns flagged thread.
 */
class MessageFlagTest {

    @Test
    fun toggleFlag_then_loadDetail_keeps_flagged_true() {
        val state = DemoMessageState()
        val id = DemoData.messages.first().id
        assertFalse(state.find(id)!!.flagged)

        val toggled = state.toggleFlag(id)
        assertNotNull(toggled)
        assertTrue(toggled!!.flagged)
        assertTrue(state.find(id)!!.flagged)

        // Reopen path: detail must merge live list, not immutable DemoData.messages
        val detail = state.loadDetail(id)
        assertTrue(detail.thread.flagged)
        assertEquals(id, detail.thread.id)
        assertTrue(detail.entries.isNotEmpty())
    }

    @Test
    fun toggleFlag_twice_returns_to_unflagged_on_loadDetail() {
        val state = DemoMessageState()
        val id = DemoData.messages.first().id
        state.toggleFlag(id)
        state.toggleFlag(id)
        assertFalse(state.loadDetail(id).thread.flagged)
    }

    @Test
    fun markRead_and_delete_mutate_list() {
        val state = DemoMessageState()
        val id = DemoData.messages.first { it.unread }.id
        assertTrue(state.markRead(id))
        assertFalse(state.find(id)!!.unread)
        assertTrue(state.delete(id))
        assertEquals(null, state.find(id))
    }

    @Test
    fun markUnread_then_loadDetail_keeps_unread_true() {
        val state = DemoMessageState()
        val id = DemoData.messages.first { !it.unread }.id
        assertTrue(state.markUnread(id))
        assertTrue(state.find(id)!!.unread)
        assertTrue(state.loadDetail(id).thread.unread)
    }
}
