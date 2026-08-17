package dk.betterw4.android.core.w4.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SavedLoginStoreTest {

    @Test
    fun saves_and_clears_username_and_password() {
        val store = InMemorySavedLoginStore()
        assertNull(store.load())

        store.save("  nc26jban  ", "secret")
        assertEquals(SavedLogin("nc26jban", "secret"), store.load())

        store.save("nc25eros", "other")
        assertEquals(SavedLogin("nc25eros", "other"), store.load())

        store.clear()
        assertNull(store.load())
    }

    @Test
    fun ignores_blank_username_or_password() {
        val store = InMemorySavedLoginStore()
        store.save("", "secret")
        store.save("nc26jban", "")
        assertNull(store.load())

        store.save("nc26jban", "secret")
        store.save("   ", "newer")
        assertEquals(SavedLogin("nc26jban", "secret"), store.load())
    }
}
