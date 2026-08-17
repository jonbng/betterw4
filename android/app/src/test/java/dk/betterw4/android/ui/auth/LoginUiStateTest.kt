package dk.betterw4.android.ui.auth

import dk.betterw4.android.core.w4.session.LastSchoolHint
import dk.betterw4.android.core.w4.session.LastSchoolReason
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LoginUiStateTest {

    @Test
    fun unlock_only_when_saved_login_and_device_auth_available() {
        val base = LoginUiState(
            username = "nc26jban",
            hasSavedLogin = true,
            canUnlock = true,
        )
        assertTrue(base.showUnlock)
        assertTrue(base.canSubmitUnlock)
        assertFalse(base.copy(preferPasswordForm = true).showUnlock)
        assertFalse(base.copy(canUnlock = false).showUnlock)
        assertFalse(base.copy(hasSavedLogin = false).showUnlock)
        assertFalse(base.copy(loggingIn = true).canSubmitUnlock)
    }

    @Test
    fun session_expired_flag_comes_from_last_school_hint() {
        val expired = LoginUiState(
            lastSchool = LastSchoolHint(
                gymId = 1,
                schoolName = "W4",
                reason = LastSchoolReason.SESSION_EXPIRED,
                username = "nc26jban",
            ),
        )
        assertTrue(expired.sessionExpired)
        assertFalse(expired.copy(lastSchool = expired.lastSchool!!.copy(reason = LastSchoolReason.LOGGED_OUT)).sessionExpired)
    }
}
