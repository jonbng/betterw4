package dk.betterw4.android.core.w4.auth

import android.content.Context
import androidx.biometric.BiometricManager
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Whether the device can show a system biometric / PIN prompt.
 *
 * The prompt itself lives in the UI layer ([dk.betterw4.android.ui.auth.promptDeviceCredential])
 * because [androidx.biometric.BiometricPrompt] needs a [androidx.fragment.app.FragmentActivity].
 */
interface DeviceAuthenticator {
    fun canAuthenticate(): Boolean

    companion object {
        /** Face (often Class 2), fingerprint, or the device PIN / pattern / password. */
        const val ALLOWED_AUTHENTICATORS: Int =
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
    }
}

@Singleton
class AndroidDeviceAuthenticator @Inject constructor(
    @ApplicationContext private val context: Context,
) : DeviceAuthenticator {
    override fun canAuthenticate(): Boolean {
        val status = BiometricManager.from(context)
            .canAuthenticate(DeviceAuthenticator.ALLOWED_AUTHENTICATORS)
        return status == BiometricManager.BIOMETRIC_SUCCESS
    }
}
