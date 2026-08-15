package dk.betterlectio.android.core.lectio.cookie

import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_AUTOLOGIN
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_SESSION_ID
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.PRIMARY_COOKIE_NAMES

/**
 * Pure cookie merge rules for Lectio credentials.
 *
 * iOS parity: [CookieManager.updateCredentials] —
 * - Only merge cookies for lectio.dk domains
 * - Empty primary cookie values are IGNORED (token-replay / stale concurrent races)
 * - Empty non-primary values delete the key
 */
object LectioCookieJar {

    /**
     * @return updated credentials, or null if nothing changed.
     */
    fun mergeSetCookies(
        current: LectioCredentials,
        setCookieHeaders: List<String>,
        responseHost: String?,
    ): LectioCredentials? {
        // Only merge cookies from the lectio.dk realm (iOS CookieManager).
        if (!isLikelyLectioHost(responseHost)) return null

        val cookies = SetCookieParser.parse(setCookieHeaders, responseHost)
            .filter { cookie ->
                val domain = cookie.domain
                domain == null ||
                    SetCookieParser.isLectioDomain(domain) ||
                    isLikelyLectioHost(responseHost)
            }
        if (cookies.isEmpty()) return null

        var autologinkey = current.autologinkey
        var sessionId = current.sessionId
        val additional = current.additionalCookies.toMutableMap().apply {
            remove(COOKIE_SESSION_ID)
            remove(COOKIE_AUTOLOGIN)
        }

        for (cookie in cookies) {
            when (cookie.name) {
                COOKIE_AUTOLOGIN -> {
                    // iOS: empty means invalidation signal — do not wipe stored key.
                    if (cookie.value.isNotEmpty()) {
                        autologinkey = cookie.value
                    }
                }
                COOKIE_SESSION_ID -> {
                    if (cookie.value.isNotEmpty()) {
                        sessionId = cookie.value
                    }
                }
                else -> {
                    if (cookie.value.isEmpty()) {
                        additional.remove(cookie.name)
                    } else if (cookie.name !in PRIMARY_COOKIE_NAMES) {
                        additional[cookie.name] = cookie.value
                    }
                }
            }
        }

        val next = LectioCredentials(
            autologinkey = autologinkey,
            sessionId = sessionId,
            autologinkeyExpiresAt = current.autologinkeyExpiresAt,
            sessionIdExpiresAt = current.sessionIdExpiresAt,
            additionalCookies = additional,
        ).seededIsLoggedIn()

        return if (next == current.seededIsLoggedIn()) null else next
    }

    private fun isLikelyLectioHost(host: String?): Boolean {
        if (host.isNullOrBlank()) return false
        return host.contains("lectio.dk", ignoreCase = true)
    }
}
