package dk.betterlectio.android.core.lectio.model

import org.json.JSONObject
import java.time.Instant

/**
 * Lectio session cookies.
 *
 * iOS parity: `StudentModels.LectioCredentials` — primaries plus every other lectio.dk cookie
 * snapshot from WebView and merged from Set-Cookie.
 */
data class LectioCredentials(
    val autologinkey: String,
    val sessionId: String,
    val autologinkeyExpiresAt: Instant = Instant.now().plusSeconds(60L * 60 * 24 * 60),
    val sessionIdExpiresAt: Instant = Instant.now().plusSeconds(60L * 60 * 24 * 60),
    /** Must not contain the two primary cookie names. */
    val additionalCookies: Map<String, String> = emptyMap(),
) {
    val isValid: Boolean
        get() = autologinkey.isNotEmpty() && autologinkeyExpiresAt.isAfter(Instant.now())

    fun clearingSessionId(): LectioCredentials {
        val extras = additionalCookies.toMutableMap().apply {
            remove(COOKIE_SESSION_ID)
        }
        return copy(
            sessionId = "",
            sessionIdExpiresAt = Instant.EPOCH,
            additionalCookies = extras,
        )
    }

    fun withSessionId(newSessionId: String): LectioCredentials {
        val extras = additionalCookies.toMutableMap().apply {
            remove(COOKIE_SESSION_ID)
        }
        return copy(
            sessionId = newSessionId,
            sessionIdExpiresAt = Instant.now().plusSeconds(60L * 60 * 24 * 60),
            additionalCookies = extras,
        )
    }

    fun seededIsLoggedIn(): LectioCredentials {
        if (additionalCookies.containsKey(COOKIE_IS_LOGGED_IN)) return this
        return copy(
            additionalCookies = additionalCookies + (COOKIE_IS_LOGGED_IN to "Y"),
        )
    }

    fun toJson(): String {
        val o = JSONObject()
        o.put("autologinkey", autologinkey)
        o.put("sessionId", sessionId)
        o.put("autologinkeyExpiresAt", autologinkeyExpiresAt.toEpochMilli())
        o.put("sessionIdExpiresAt", sessionIdExpiresAt.toEpochMilli())
        val extras = JSONObject()
        additionalCookies.forEach { (k, v) -> extras.put(k, v) }
        o.put("additionalCookies", extras)
        return o.toString()
    }

    companion object {
        const val COOKIE_SESSION_ID = "ASP.NET_SessionId"
        const val COOKIE_AUTOLOGIN = "autologinkeyV2"
        const val COOKIE_IS_LOGGED_IN = "isloggedin3"

        val PRIMARY_COOKIE_NAMES = setOf(COOKIE_SESSION_ID, COOKIE_AUTOLOGIN)

        fun fromJson(json: String): LectioCredentials? = try {
            val o = JSONObject(json)
            val extrasObj = o.optJSONObject("additionalCookies")
            val extras = mutableMapOf<String, String>()
            if (extrasObj != null) {
                val keys = extrasObj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    extras[k] = extrasObj.getString(k)
                }
            }
            LectioCredentials(
                autologinkey = o.getString("autologinkey"),
                sessionId = o.getString("sessionId"),
                autologinkeyExpiresAt = Instant.ofEpochMilli(o.getLong("autologinkeyExpiresAt")),
                sessionIdExpiresAt = Instant.ofEpochMilli(o.getLong("sessionIdExpiresAt")),
                additionalCookies = extras,
            ).seededIsLoggedIn()
        } catch (_: Exception) {
            null
        }
    }
}
