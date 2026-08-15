package dk.betterlectio.android.core.cache

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Proves the shipped cache backends wipe data (same clear path OfflineDataCleaner uses).
 */
class OfflineDataCleanerLogicTest {

    @Test
    fun entityOfflineStore_clear_wipes_entries() {
        val store = EntityOfflineStore(EntityOfflineStore.InMemoryBackend())
        store.put("homework_s1", "<html>secret</html>")
        assertTrue(store.contains("homework_s1"))
        store.clear()
        assertFalse(store.contains("homework_s1"))
        assertNull(store.get("homework_s1"))
    }
}
