package dk.betterlectio.android.core.lectio.cookie

import dk.betterlectio.android.core.lectio.model.LectioCredentials
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class LectioCookieJarTest {

    private val base = LectioCredentials(
        autologinkey = "OLD_AUTO",
        sessionId = "OLD_SESSION",
        additionalCookies = mapOf("isloggedin3" to "Y", "keep" to "1"),
    )

    @Test
    fun empty_primary_set_cookie_is_ignored() {
        val updated = LectioCookieJar.mergeSetCookies(
            base,
            listOf(
                "autologinkeyV2=; path=/",
                "ASP.NET_SessionId=; path=/",
            ),
            responseHost = "www.lectio.dk",
        )
        // Nothing should change (seeded equality) — empty primaries ignored
        assertNull(updated)
    }

    @Test
    fun non_empty_primaries_rotate() {
        val updated = LectioCookieJar.mergeSetCookies(
            base,
            listOf(
                "autologinkeyV2=NEW_AUTO; path=/; domain=.lectio.dk",
                "ASP.NET_SessionId=NEW_SESSION; path=/",
            ),
            responseHost = "www.lectio.dk",
        )
        assertNotNull(updated)
        assertEquals("NEW_AUTO", updated!!.autologinkey)
        assertEquals("NEW_SESSION", updated.sessionId)
    }

    @Test
    fun empty_non_primary_deletes_key() {
        val updated = LectioCookieJar.mergeSetCookies(
            base,
            listOf("keep=; path=/"),
            responseHost = "www.lectio.dk",
        )
        assertNotNull(updated)
        assertEquals(false, updated!!.additionalCookies.containsKey("keep"))
        assertEquals("Y", updated.additionalCookies["isloggedin3"])
    }

    @Test
    fun ignores_non_lectio_host_cookies() {
        val updated = LectioCookieJar.mergeSetCookies(
            base,
            listOf("autologinkeyV2=HACKED; path=/; domain=broker.unilogin.dk"),
            responseHost = "broker.unilogin.dk",
        )
        assertNull(updated)
    }
}
