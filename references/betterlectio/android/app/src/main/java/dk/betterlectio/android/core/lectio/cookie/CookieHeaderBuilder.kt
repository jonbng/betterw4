package dk.betterlectio.android.core.lectio.cookie

import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_AUTOLOGIN
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_IS_LOGGED_IN
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_SESSION_ID

/**
 * Builds the Cookie request header.
 *
 * iOS parity: [CookieManager.cookieHeader] —
 * order: ASP.NET_SessionId (if non-empty) → autologinkeyV2 → isloggedin3 → remaining sorted.
 */
object CookieHeaderBuilder {
    fun build(credentials: LectioCredentials): String {
        val rest = credentials.additionalCookies.toMutableMap()
        rest.remove(COOKIE_SESSION_ID)
        rest.remove(COOKIE_AUTOLOGIN)
        val isLoggedIn = rest.remove(COOKIE_IS_LOGGED_IN)

        val segments = mutableListOf<String>()
        if (credentials.sessionId.isNotEmpty()) {
            segments += "$COOKIE_SESSION_ID=${credentials.sessionId}"
        }
        if (credentials.autologinkey.isNotEmpty()) {
            segments += "$COOKIE_AUTOLOGIN=${credentials.autologinkey}"
        }
        if (isLoggedIn != null) {
            segments += "$COOKIE_IS_LOGGED_IN=$isLoggedIn"
        }
        for (name in rest.keys.sorted()) {
            val value = rest[name] ?: continue
            segments += "$name=$value"
        }
        return segments.joinToString("; ")
    }

    /** Redacted for debug logs — never log full cookie values in release. */
    fun redactedPreview(credentials: LectioCredentials): String {
        fun preview(value: String): String =
            if (value.length <= 8) "***" else "${value.take(4)}…${value.takeLast(2)}"

        return buildString {
            append("session=")
            append(if (credentials.sessionId.isEmpty()) "(empty)" else preview(credentials.sessionId))
            append(" autologin=")
            append(if (credentials.autologinkey.isEmpty()) "(empty)" else preview(credentials.autologinkey))
            append(" extras=")
            append(credentials.additionalCookies.keys.sorted().joinToString(","))
        }
    }
}
