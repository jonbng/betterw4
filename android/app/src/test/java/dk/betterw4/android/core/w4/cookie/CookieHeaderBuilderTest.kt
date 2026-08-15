package dk.betterw4.android.core.w4.cookie

import dk.betterw4.android.core.w4.model.W4Credentials
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CookieHeaderBuilderTest {

    @Test
    fun sends_only_phpsessid() {
        val creds = W4Credentials(
            autologinkey = "AUTOKEY",
            sessionId = "SESSION",
            additionalCookies = mapOf(
                "isloggedin3" to "Y",
                "foo" to "bar",
                "aaa" to "1",
            ),
        )
        val header = CookieHeaderBuilder.build(creds)
        assertEquals("PHPSESSID=SESSION; aaa=1; foo=bar", header)
        assertFalse(header.contains("autologinkeyV2"))
        assertFalse(header.contains("isloggedin3"))
    }

    @Test
    fun omits_empty_session_id() {
        val creds = W4Credentials(
            autologinkey = "AUTOKEY",
            sessionId = "",
            additionalCookies = mapOf("isloggedin3" to "Y"),
        )
        val header = CookieHeaderBuilder.build(creds)
        assertEquals("", header)
        assertFalse(header.contains("PHPSESSID"))
        assertFalse(header.contains("autologinkeyV2"))
    }

    @Test
    fun seed_isloggedin_is_not_sent() {
        val creds = W4Credentials(
            autologinkey = "A",
            sessionId = "S",
        ).seededIsLoggedIn()
        val header = CookieHeaderBuilder.build(creds)
        assertEquals("PHPSESSID=S", header)
        assertTrue(CookieHeaderBuilder.redactedPreview(creds).contains("PHPSESSID="))
        assertFalse(CookieHeaderBuilder.redactedPreview(creds).contains("autologin"))
    }
}
