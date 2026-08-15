package dk.betterw4.android.core.w4.http

import dk.betterw4.android.core.w4.cookie.CookieHeaderBuilder
import dk.betterw4.android.core.w4.session.CredentialStore
import dk.betterw4.android.core.w4.W4Hosts
import okhttp3.Interceptor
import okhttp3.Response

/**
 * Injects `PHPSESSID` + browser headers for `w4.uwcrcn.no` requests.
 *
 * Coil uses a separate OkHttp stack from [W4HttpEngine], so authenticated
 * assets (people thumbs, documents) need this interceptor.
 */
class W4AuthInterceptor(
    private val credentialStore: CredentialStore,
    private val isW4Host: (String) -> Boolean = Companion::defaultIsW4Host,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        if (!isW4Host(original.url.host)) {
            return chain.proceed(original)
        }

        val builder = original.newBuilder()
        if (original.header("User-Agent").isNullOrBlank()) {
            builder.header("User-Agent", W4UserAgent.VALUE)
        }
        if (original.header("Referer").isNullOrBlank()) {
            builder.header("Referer", W4UserAgent.REFERER)
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
        fun defaultIsW4Host(host: String): Boolean = W4Hosts.isW4Host(host)
    }
}
