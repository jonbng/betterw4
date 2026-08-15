package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PinStoreTest {
    @Test
    fun toggle_persists_via_callback() {
        var saved: Set<String> = emptySet()
        val store = PinStore(
            load = { emptySet() },
            persist = { saved = it },
        )
        assertTrue(store.toggle("S1"))
        assertTrue(store.isPinned("S1"))
        assertEquals(setOf("S1"), saved)
        assertFalse(store.toggle("S1"))
        assertFalse(store.isPinned("S1"))
        assertTrue(saved.isEmpty())
    }

    @Test
    fun sortPinnedFirst_orders_correctly() {
        val store = PinStore(load = { setOf("b") }, persist = {})
        val items = listOf(
            DirectoryEntity("a", "A", DirectoryEntityKind.STUDENT),
            DirectoryEntity("b", "B", DirectoryEntityKind.STUDENT),
            DirectoryEntity("c", "C", DirectoryEntityKind.STUDENT),
        )
        val sorted = store.sortPinnedFirst(items) { it.id }
        assertEquals(listOf("b", "a", "c"), sorted.map { it.id })
    }

    @Test
    fun load_initial_pins() {
        val store = PinStore(load = { setOf("x", "y") }, persist = {})
        assertTrue(store.isPinned("x"))
        assertTrue(store.isPinned("y"))
        assertEquals(2, store.pinnedIds().size)
    }
}
