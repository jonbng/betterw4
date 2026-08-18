package dk.betterw4.android.core.w4.session

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import timber.log.Timber

/**
 * Encrypted W4 username + password for biometric re-login after PHPSESSID dies.
 *
 * Separate from [CredentialStore] (session cookies). Survives session expiry;
 * wiped on explicit logout, demo, or a failed saved-login retry.
 */
data class SavedLogin(
    val username: String,
    val password: String,
)

interface SavedLoginStore {
    fun save(username: String, password: String)
    fun load(): SavedLogin?
    fun clear()
}

class EncryptedSavedLoginStore(
    context: Context,
) : SavedLoginStore {

    private val prefs: SharedPreferences = createPrefs(context.applicationContext)

    override fun save(username: String, password: String) {
        val user = username.trim()
        if (user.isEmpty() || password.isEmpty()) return
        prefs.edit {
            putString(KEY_USERNAME, user)
            putString(KEY_PASSWORD, password)
        }
    }

    override fun load(): SavedLogin? {
        val username = prefs.getString(KEY_USERNAME, null)?.takeIf { it.isNotBlank() } ?: return null
        val password = prefs.getString(KEY_PASSWORD, null)?.takeIf { it.isNotEmpty() } ?: return null
        return SavedLogin(username = username, password = password)
    }

    override fun clear() {
        prefs.edit { clear() }
    }

    companion object {
        private const val PREFS_FILE = "w4_saved_login"
        private const val KEY_USERNAME = "username"
        private const val KEY_PASSWORD = "password"

        private fun createPrefs(context: Context): SharedPreferences {
            return try {
                val masterKey = MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                EncryptedSharedPreferences.create(
                    context,
                    PREFS_FILE,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            } catch (e: Exception) {
                Timber.e(e, "EncryptedSharedPreferences unavailable — refusing plaintext fallback")
                throw IllegalStateException(
                    "Secure credential storage unavailable; cannot store W4 login",
                    e,
                )
            }
        }
    }
}

/** In-memory store for unit tests. */
class InMemorySavedLoginStore : SavedLoginStore {
    private var saved: SavedLogin? = null

    override fun save(username: String, password: String) {
        val user = username.trim()
        if (user.isEmpty() || password.isEmpty()) return
        saved = SavedLogin(username = user, password = password)
    }

    override fun load(): SavedLogin? = saved

    override fun clear() {
        saved = null
    }
}
