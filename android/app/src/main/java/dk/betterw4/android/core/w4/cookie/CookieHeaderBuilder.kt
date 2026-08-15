package dk.betterw4.android.core.w4.cookie

import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Credentials.Companion.COOKIE_AUTOLOGIN
import dk.betterw4.android.core.w4.model.W4Credentials.Companion.COOKIE_IS_LOGGED_IN
import dk.betterw4.android.core.w4.model.W4Credentials.Companion.COOKIE_SESSION_ID

/**
 * Builds the Cookie request header for W4.
 *
 * Only `PHPSESSID` is a W4 cookie (README §4.1). Lectio leftovers
 * (`autologinkeyV2`, `isloggedin3`) are never sent.
 */
object CookieHeaderBuilder {
    private val LECTIO_LEFTOVERS = setOf(
        COOKIE_SESSION_ID,
        COOKIE_AUTOLOGIN,
        COOKIE_IS_LOGGED_IN,
    )

    fun build(credentials: W4Credentials): String {
        val segments = mutableListOf<String>()
        if (credentials.sessionId.isNotEmpty()) {
            segments += "$COOKIE_SESSION_ID=${credentials.sessionId}"
        }
        for (name in credentials.additionalCookies.keys.sorted()) {
            if (name in LECTIO_LEFTOVERS) continue
            val value = credentials.additionalCookies[name] ?: continue
            if (value.isEmpty()) continue
            segments += "$name=$value"
        }
        return segments.joinToString("; ")
    }

    /** Redacted for debug logs — never log full cookie values in release. */
    fun redactedPreview(credentials: W4Credentials): String {
        fun preview(value: String): String =
            if (value.length <= 8) "***" else "${value.take(4)}…${value.takeLast(2)}"

        val extras = credentials.additionalCookies.keys
            .filter { it !in LECTIO_LEFTOVERS }
            .sorted()
        return buildString {
            append("PHPSESSID=")
            append(if (credentials.sessionId.isEmpty()) "(empty)" else preview(credentials.sessionId))
            if (extras.isNotEmpty()) {
                append(" extras=")
                append(extras.joinToString(","))
            }
        }
    }
}
