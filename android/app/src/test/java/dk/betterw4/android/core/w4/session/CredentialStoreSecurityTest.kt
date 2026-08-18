package dk.betterw4.android.core.w4.session

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
            "src/main/java/dk/betterw4/android/core/w4/session/CredentialStore.kt",
            "app/src/main/java/dk/betterw4/android/core/w4/session/CredentialStore.kt",
            "../app/src/main/java/dk/betterw4/android/core/w4/session/CredentialStore.kt",
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
    fun saved_login_store_source_refuses_plaintext_fallback() {
        val candidates = listOf(
            "src/main/java/dk/betterw4/android/core/w4/session/SavedLoginStore.kt",
            "app/src/main/java/dk/betterw4/android/core/w4/session/SavedLoginStore.kt",
            "../app/src/main/java/dk/betterw4/android/core/w4/session/SavedLoginStore.kt",
        )
        val file = candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: error("SavedLoginStore.kt not found from ${System.getProperty("user.dir")}")
        val src = file.readText()
        assertFalse(
            "must not fall back to MODE_PRIVATE plaintext prefs",
            src.contains("MODE_PRIVATE"),
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
        val creds = dk.betterw4.android.core.w4.model.W4Credentials(
            autologinkey = "A",
            sessionId = "S",
        )
        store.saveCredentials(creds, "42")
        assertTrue(store.loadCredentials("42")!!.autologinkey == "A")
        store.deleteCredentials("42")
        assertTrue(store.loadCredentials("42") == null)
    }
}
