package dk.betterw4.android.ui.auth

import androidx.biometric.BiometricPrompt
import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceUnlockTest {

    @Test
    fun hardware_and_enrollment_gaps_are_unavailable() {
        listOf(
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_NO_BIOMETRICS,
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
        ).forEach { code ->
            assertEquals(DeviceAuthResult.Unavailable, code.toDeviceAuthResult())
        }
    }

    @Test
    fun lockout_is_distinct_from_cancel() {
        assertEquals(DeviceAuthResult.Lockout, BiometricPrompt.ERROR_LOCKOUT.toDeviceAuthResult())
        assertEquals(
            DeviceAuthResult.Lockout,
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT.toDeviceAuthResult(),
        )
    }

    @Test
    fun user_dismiss_does_not_look_like_a_system_cancel() {
        assertEquals(
            DeviceAuthResult.UserCanceled,
            BiometricPrompt.ERROR_USER_CANCELED.toDeviceAuthResult(),
        )
        assertEquals(
            DeviceAuthResult.UserCanceled,
            BiometricPrompt.ERROR_NEGATIVE_BUTTON.toDeviceAuthResult(),
        )
    }

    @Test
    fun system_interrupt_can_be_retried() {
        assertEquals(
            DeviceAuthResult.SystemCanceled,
            BiometricPrompt.ERROR_CANCELED.toDeviceAuthResult(),
        )
        assertEquals(
            DeviceAuthResult.SystemCanceled,
            BiometricPrompt.ERROR_TIMEOUT.toDeviceAuthResult(),
        )
        assertEquals(
            DeviceAuthResult.SystemCanceled,
            BiometricPrompt.ERROR_UNABLE_TO_PROCESS.toDeviceAuthResult(),
        )
    }
}
