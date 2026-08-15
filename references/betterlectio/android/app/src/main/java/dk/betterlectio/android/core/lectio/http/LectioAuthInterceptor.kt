package dk.betterlectio.android.core.lectio.http

import dk.betterlectio.android.core.lectio.cookie.CookieHeaderBuilder
import dk.betterlectio.android.core.lectio.session.CredentialStore
import okhttp3.Interceptor
import okhttp3.Response

/**
 * Injects Lectio session cookies + browser headers for lectio.dk requests.
 *
 * Coil (and any other client) uses a separate OkHttp stack from [LectioHttpEngine],
 * so authenticated assets like `GetImage.aspx` need this interceptor — Lectio rejects
 * unauthenticated image fetches with empty/login HTML.
 */
class LectioAuthInterceptor(
    private val credentialStore: CredentialStore,
    private val isLectioHost: (String) -> Boolean = Companion::defaultIsLectioHost,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        if (!isLectioHost(original.url.host)) {
            return chain.proceed(original)
        }

        val builder = original.newBuilder()
        if (original.header("User-Agent").isNullOrBlank()) {
            builder.header("User-Agent", LectioUserAgent.VALUE)
        }
        if (original.header("Referer").isNullOrBlank()) {
            builder.header("Referer", LectioUserAgent.REFERER)
        }

        // Prefer an explicit Cookie already set by the caller; otherwise attach session cookies.
        if (original.header("Cookie").isNullOrBlank()) {
            val cookie = currentCookieHeader()
            if (!cookie.isNullOrBlank()) {
                builder.header("Cookie", cookie)
            }
        }

        return chain.proceed(builder.build())
    }

    private fun currentCookieHeader(): String? {
        val student = credentialStore.loadStudent() ?: return null
        if (student.isDemo) return null
        val credentials = credentialStore.loadCredentials(student.studentId) ?: return null
        val header = CookieHeaderBuilder.build(credentials)
        return header.takeIf { it.isNotBlank() }
    }

    companion object {
        fun defaultIsLectioHost(host: String): Boolean =
            host.contains("lectio.dk", ignoreCase = true)
    }
}
