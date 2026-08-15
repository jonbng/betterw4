package dk.betterlectio.android.core.lectio.cookie

import dk.betterlectio.android.core.lectio.model.LectioCredentials
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CookieHeaderBuilderTest {

    @Test
    fun builds_ordered_header_with_isloggedin3() {
        val creds = LectioCredentials(
            autologinkey = "AUTOKEY",
            sessionId = "SESSION",
            additionalCookies = mapOf(
                "isloggedin3" to "Y",
                "foo" to "bar",
                "aaa" to "1",
            ),
        )
        val header = CookieHeaderBuilder.build(creds)
        assertEquals(
            "ASP.NET_SessionId=SESSION; autologinkeyV2=AUTOKEY; isloggedin3=Y; aaa=1; foo=bar",
            header,
        )
    }

    @Test
    fun omits_empty_session_id() {
        val creds = LectioCredentials(
            autologinkey = "AUTOKEY",
            sessionId = "",
            additionalCookies = mapOf("isloggedin3" to "Y"),
        )
        val header = CookieHeaderBuilder.build(creds)
        assertFalse(header.contains("ASP.NET_SessionId"))
        assertTrue(header.startsWith("autologinkeyV2=AUTOKEY"))
    }

    @Test
    fun seed_isloggedin_then_header_includes_it() {
        val creds = LectioCredentials(
            autologinkey = "A",
            sessionId = "S",
        ).seededIsLoggedIn()
        val header = CookieHeaderBuilder.build(creds)
        assertTrue(header.contains("isloggedin3=Y"))
    }
}
