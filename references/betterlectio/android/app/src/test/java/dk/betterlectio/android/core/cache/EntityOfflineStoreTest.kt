package dk.betterlectio.android.core.cache

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EntityOfflineStoreTest {
    @Test
    fun putAndGet_roundTrip() {
        val store = EntityOfflineStore(EntityOfflineStore.InMemoryBackend())
        assertEquals("hello", store.putAndGet("k1", "hello"))
        assertTrue(store.contains("k1"))
        assertEquals("hello", store.get("k1"))
    }

    @Test
    fun remove_and_clear() {
        val store = EntityOfflineStore(EntityOfflineStore.InMemoryBackend())
        store.put("a", "1")
        store.put("b", "2")
        store.remove("a")
        assertNull(store.get("a"))
        assertEquals("2", store.get("b"))
        store.clear()
        assertFalse(store.contains("b"))
    }
}
