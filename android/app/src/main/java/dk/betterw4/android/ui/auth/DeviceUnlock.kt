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
    data object Canceled : DeviceAuthResult()
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
        .build()
    prompt.authenticate(info)
    cont.invokeOnCancellation { prompt.cancelAuthentication() }
}

private fun Int.toDeviceAuthResult(): DeviceAuthResult = when (this) {
    BiometricPrompt.ERROR_HW_UNAVAILABLE,
    BiometricPrompt.ERROR_HW_NOT_PRESENT,
    BiometricPrompt.ERROR_NO_BIOMETRICS,
    BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
    BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
    -> DeviceAuthResult.Unavailable
    else -> DeviceAuthResult.Canceled
}
