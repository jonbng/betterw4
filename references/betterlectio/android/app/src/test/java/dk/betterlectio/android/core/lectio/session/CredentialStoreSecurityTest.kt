package dk.betterlectio.android.core.lectio.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Structural check that EncryptedCredentialStore fails closed (no plaintext fallback).
 */
class CredentialStoreSecurityTest {

    @Test
    fun encrypted_store_source_refuses_plaintext_fallback() {
        val candidates = listOf(
            "src/main/java/dk/betterlectio/android/core/lectio/session/CredentialStore.kt",
            "app/src/main/java/dk/betterlectio/android/core/lectio/session/CredentialStore.kt",
            "../app/src/main/java/dk/betterlectio/android/core/lectio/session/CredentialStore.kt",
        )
        val file = candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: error("CredentialStore.kt not found from ${System.getProperty("user.dir")}")
        val src = file.readText()
        assertFalse(
            "must not fall back to MODE_PRIVATE plaintext prefs",
            src.contains("_fallback") && src.contains("MODE_PRIVATE") &&
                src.contains("falling back to private prefs"),
        )
        assertTrue(
            "must throw when EncryptedSharedPreferences fails",
            src.contains("refusing plaintext fallback") ||
                src.contains("Secure credential storage unavailable"),
        )
        assertTrue(src.contains("IllegalStateException"))
    }

    @Test
    fun in_memory_store_round_trips_for_tests() {
        val store = InMemoryCredentialStore()
        val creds = dk.betterlectio.android.core.lectio.model.LectioCredentials(
            autologinkey = "A",
            sessionId = "S",
        )
        store.saveCredentials(creds, "42")
        assertTrue(store.loadCredentials("42")!!.autologinkey == "A")
        store.deleteCredentials("42")
        assertTrue(store.loadCredentials("42") == null)
    }
}
