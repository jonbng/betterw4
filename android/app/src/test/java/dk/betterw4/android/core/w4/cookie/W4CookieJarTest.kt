package dk.betterw4.android.core.w4.cookie

import dk.betterw4.android.core.w4.model.W4Credentials
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class W4CookieJarTest {

    private val base = W4Credentials(
        sessionId = "OLD_SESSION",
        additionalCookies = mapOf("keep" to "1"),
    )

    @Test
    fun empty_phpsessid_is_ignored() {
        val updated = W4CookieJar.mergeSetCookies(
            base,
            listOf("PHPSESSID=; path=/; secure"),
            responseHost = "w4.uwcrcn.no",
        )
        assertNull(updated)
    }

    @Test
    fun non_empty_phpsessid_rotates() {
        val updated = W4CookieJar.mergeSetCookies(
            base,
            listOf("PHPSESSID=NEW_SESSION; path=/; secure"),
            responseHost = "w4.uwcrcn.no",
        )
        assertNotNull(updated)
        assertEquals("NEW_SESSION", updated!!.sessionId)
        assertEquals("1", updated.additionalCookies["keep"])
    }

    @Test
    fun ignores_non_w4_host() {
        val updated = W4CookieJar.mergeSetCookies(
            base,
            listOf("PHPSESSID=HACKED; path=/"),
            responseHost = "broker.unilogin.dk",
        )
        assertNull(updated)
    }

    @Test
    fun empty_non_primary_deletes_key() {
        val updated = W4CookieJar.mergeSetCookies(
            base,
            listOf("keep=; path=/"),
            responseHost = "w4.uwcrcn.no",
        )
        assertNotNull(updated)
        assertEquals(false, updated!!.additionalCookies.containsKey("keep"))
        assertEquals("OLD_SESSION", updated.sessionId)
    }
}
