package dk.betterw4.android.core.w4

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class W4SessionTest {

    @Test
    fun login_url_is_only_site_login() {
        assertTrue(W4Session.isLoginUrl("https://w4.uwcrcn.no/index.php?r=site/login"))
        assertTrue(W4Session.isLoginUrl("https://w4.uwcrcn.no/index.php?r=site%2Flogin"))
        assertFalse(W4Session.isLoginUrl("https://w4.uwcrcn.no/index.php?r=site/otp"))
        assertFalse(W4Session.isLoginUrl("https://w4.uwcrcn.no/index.php?r=site/verify2fa"))
        assertFalse(W4Session.isLoginUrl("https://w4.uwcrcn.no/index.php?r=site/index"))
        assertFalse(W4Session.isLoginUrl("https://w4.uwcrcn.no/index.php?r=site/logout"))
    }

    @Test
    fun otp_and_home_are_auth_progress_not_expiry() {
        assertTrue(W4Session.isOtpUrl("https://w4.uwcrcn.no/index.php?r=site/otp"))
        assertTrue(W4Session.isOtpUrl("https://w4.uwcrcn.no/index.php?r=site/verify2fa"))
        assertTrue(W4Session.isOtpUrl("https://w4.uwcrcn.no/index.php?r=site%2Fverify2fa"))
        assertTrue(W4Session.isHomeUrl("https://w4.uwcrcn.no/index.php?r=site/index"))
        assertTrue(W4Session.isAuthProgressUrl("https://w4.uwcrcn.no/index.php?r=site/otp"))
        assertTrue(W4Session.isAuthProgressUrl("https://w4.uwcrcn.no/index.php?r=site/verify2fa"))
        assertTrue(W4Session.isAuthProgressUrl("https://w4.uwcrcn.no/index.php?r=site/index"))
        assertFalse(W4Session.isAuthProgressUrl("https://w4.uwcrcn.no/index.php?r=site/login"))
        assertFalse(W4Session.isOtpUrl("https://w4.uwcrcn.no/index.php?r=site/login"))
    }
}
