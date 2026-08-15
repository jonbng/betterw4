package dk.betterw4.android.core.w4.cookie

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Credentials.Companion.COOKIE_SESSION_ID
import dk.betterw4.android.core.w4.model.W4Credentials.Companion.PRIMARY_COOKIE_NAMES

/**
 * Merge `Set-Cookie` into the W4 jar.
 *
 * Rules (README §4.1):
 * - Only cookies for host-only `w4.uwcrcn.no`
 * - Primary cookie is `PHPSESSID` — **ignore empty values** (do not wipe)
 * - PHP may regenerate the id; last non-empty value wins
 * - One name, one value
 */
object W4CookieJar {

    fun mergeSetCookies(
        current: W4Credentials,
        setCookieHeaders: List<String>,
        responseHost: String?,
    ): W4Credentials? {
        if (!W4Hosts.isW4Host(responseHost)) return null

        val cookies = SetCookieParser.parse(setCookieHeaders, responseHost)
            .filter { cookie ->
                val domain = cookie.domain
                domain == null || W4Hosts.isW4Host(domain) || W4Hosts.isW4Host(responseHost)
            }
        if (cookies.isEmpty()) return null

        var sessionId = current.sessionId
        val additional = current.additionalCookies.toMutableMap().apply {
            remove(COOKIE_SESSION_ID)
        }

        for (cookie in cookies) {
            when (cookie.name) {
                COOKIE_SESSION_ID -> {
                    if (cookie.value.isNotEmpty()) {
                        sessionId = cookie.value
                    }
                }
                else -> {
                    if (cookie.name in PRIMARY_COOKIE_NAMES) continue
                    if (cookie.value.isEmpty()) {
                        additional.remove(cookie.name)
                    } else {
                        additional[cookie.name] = cookie.value
                    }
                }
            }
        }

        val next = current.copy(
            sessionId = sessionId,
            additionalCookies = additional,
        )
        return if (next.sessionId == current.sessionId &&
            next.additionalCookies == current.additionalCookies
        ) {
            null
        } else {
            next
        }
    }
}
