package dk.betterw4.android.ui.auth

import android.content.Context
import android.content.ContextWrapper
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dk.betterw4.android.core.w4.auth.DeviceAuthenticator
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

sealed class DeviceAuthResult {
    data object Success : DeviceAuthResult()
    /** User dismissed the sheet. Do not auto-prompt again this visit. */
    data object UserCanceled : DeviceAuthResult()
    /** Activity paused / prompt not ready. Safe to retry on the next resume. */
    data object SystemCanceled : DeviceAuthResult()
    data object Lockout : DeviceAuthResult()
    data object Unavailable : DeviceAuthResult()
}

fun Context.findFragmentActivity(): FragmentActivity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is FragmentActivity) return current
        current = current.baseContext
    }
    return null
}

suspend fun FragmentActivity.promptDeviceCredential(
    title: String,
    subtitle: String? = null,
): DeviceAuthResult = suspendCancellableCoroutine { cont ->
    val executor = ContextCompat.getMainExecutor(this)
    val prompt = BiometricPrompt(
        this,
        executor,
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                if (cont.isActive) cont.resume(DeviceAuthResult.Success)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (!cont.isActive) return
                cont.resume(errorCode.toDeviceAuthResult())
            }
        },
    )
    val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle(title)
        .apply { if (!subtitle.isNullOrBlank()) setSubtitle(subtitle) }
        .setAllowedAuthenticators(DeviceAuthenticator.ALLOWED_AUTHENTICATORS)
        // Face unlock should not require an extra "Confirm" tap after a match.
        .setConfirmationRequired(false)
        .build()
    try {
        prompt.authenticate(info)
    } catch (_: Exception) {
        if (cont.isActive) cont.resume(DeviceAuthResult.SystemCanceled)
        return@suspendCancellableCoroutine
    }
    cont.invokeOnCancellation { prompt.cancelAuthentication() }
}

internal fun Int.toDeviceAuthResult(): DeviceAuthResult = when (this) {
    BiometricPrompt.ERROR_HW_UNAVAILABLE,
    BiometricPrompt.ERROR_HW_NOT_PRESENT,
    BiometricPrompt.ERROR_NO_BIOMETRICS,
    BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
    BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
    -> DeviceAuthResult.Unavailable
    BiometricPrompt.ERROR_LOCKOUT,
    BiometricPrompt.ERROR_LOCKOUT_PERMANENT,
    -> DeviceAuthResult.Lockout
    BiometricPrompt.ERROR_USER_CANCELED,
    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
    -> DeviceAuthResult.UserCanceled
    else -> DeviceAuthResult.SystemCanceled
}
