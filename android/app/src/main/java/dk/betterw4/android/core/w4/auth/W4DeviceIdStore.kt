package dk.betterw4.android.core.w4.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Stable W4 `LoginForm[deviceId]` for this install.
 *
 * W4 binds 2FA to this value. A new id looks like a new device and re-prompts OTP.
 */
@Singleton
class W4DeviceIdStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences = createPrefs(context.applicationContext)

    fun getOrCreate(): String {
        prefs.getString(KEY, null)?.takeIf { it.isNotBlank() }?.let { return it }
        val created = UUID.randomUUID().toString()
        prefs.edit { putString(KEY, created) }
        return created
    }

    companion object {
        private const val PREFS_FILE = "w4_device_id"
        private const val KEY = "device_id"

        private fun createPrefs(context: Context): SharedPreferences {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            return EncryptedSharedPreferences.create(
                context,
                PREFS_FILE,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }
    }
}
