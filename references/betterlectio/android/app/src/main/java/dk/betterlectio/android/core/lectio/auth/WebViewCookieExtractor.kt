package dk.betterlectio.android.core.lectio.auth

import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.BuildConfig
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_AUTOLOGIN
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.COOKIE_SESSION_ID
import dk.betterlectio.android.core.lectio.model.LectioCredentials.Companion.PRIMARY_COOKIE_NAMES
import dk.betterlectio.android.core.lectio.model.LectioError
import dk.betterlectio.android.core.lectio.scrape.LectioUrls
import dk.betterlectio.android.core.result.AppResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Pulls Lectio cookies after MitID/UniLogin WebView login and wipes WebView state on logout.
 * iOS parity: CookieManager.extractLectioCredentials / clearAllWebViewData.
 *
 * Android only exposes [CookieManager.getCookie] per URL, so we merge several Lectio URLs
 * (origin + /lectio/ paths) to approximate iOS's domain-wide `allCookies` filter.
 */
interface WebViewCookieExtractor {
    fun extractFromCookieManager(schoolId: String? = null): AppResult<LectioCredentials>

    /**
     * Best-effort sync clear (legacy). Prefer [clearAllWebViewData] on logout.
     */
    fun clearLectioCookies()

    /**
     * iOS `CookieManager.clearAllWebViewData` — cookies + DOM storage + WebView HTTP cache.
     * Awaited so the next MitID login does not see a poisoned UniLogin jar.
     */
    suspend fun clearAllWebViewData()
}

@Singleton
class AndroidWebViewCookieExtractor @Inject constructor(
    @param:ApplicationContext private val appContext: Context,
) : WebViewCookieExtractor {

    override fun extractFromCookieManager(schoolId: String?): AppResult<LectioCredentials> {
        val cm = CookieManager.getInstance()
        cm.flush()

        val map = linkedMapOf<String, String>()
        for (url in cookieProbeUrls(schoolId)) {
            val raw = cm.getCookie(url) ?: continue
            val parsed = parseCookieHeader(raw)
            if (BuildConfig.DEBUG) {
                Timber.d(
                    "WebView cookie probe url=%s names=%s hasAutologin=%s hasSession=%s",
                    url,
                    parsed.keys.sorted().joinToString(","),
                    parsed.containsKey(COOKIE_AUTOLOGIN),
                    parsed.containsKey(COOKIE_SESSION_ID),
                )
            }
            map.putAll(parsed)
        }

        if (map.isEmpty()) {
            Timber.w("WebView CookieManager: no cookies for lectio.dk probes")
            return AppResult.Failure(LectioError.MissingCookies.toAppError())
        }

        Timber.d(
            "WebView cookies: names=%s hasAutologin=%s hasSession=%s",
            map.keys.sorted().joinToString(","),
            map.containsKey(COOKIE_AUTOLOGIN),
            map.containsKey(COOKIE_SESSION_ID),
        )

        val autologin = map[COOKIE_AUTOLOGIN]
        val sessionId = map[COOKIE_SESSION_ID]
        if (autologin.isNullOrEmpty() || sessionId.isNullOrEmpty()) {
            return AppResult.Failure(LectioError.MissingCookies.toAppError())
        }

        val additional = map
            .filterKeys { it !in PRIMARY_COOKIE_NAMES }
            .filterValues { it.isNotEmpty() }
            .toMutableMap()

        val creds = LectioCredentials(
            autologinkey = autologin,
            sessionId = sessionId,
            autologinkeyExpiresAt = Instant.now().plusSeconds(60L * 60 * 24 * 60),
            sessionIdExpiresAt = Instant.now().plusSeconds(60L * 60 * 24 * 60),
            additionalCookies = additional,
        ).seededIsLoggedIn()

        return AppResult.Success(creds)
    }

    override fun clearLectioCookies() {
        val cm = CookieManager.getInstance()
        cm.removeAllCookies(null)
        cm.removeSessionCookies(null)
        cm.flush()
    }

    override suspend fun clearAllWebViewData() {
        withContext(Dispatchers.Main) {
            val cm = CookieManager.getInstance()
            // Await cookie wipe (iOS awaits WKWebsiteDataStore.removeData).
            suspendCancellableCoroutine { cont ->
                cm.removeAllCookies { _ ->
                    cm.removeSessionCookies { _ ->
                        cm.flush()
                        if (cont.isActive) cont.resume(Unit)
                    }
                }
            }
            runCatching { WebStorage.getInstance().deleteAllData() }
                .onFailure { Timber.w(it, "WebStorage.deleteAllData failed") }

            // Clear WebView HTTP disk/memory cache (needs a WebView instance).
            runCatching {
                WebView(appContext).apply {
                    clearCache(true)
                    clearFormData()
                    clearHistory()
                    destroy()
                }
            }.onFailure { Timber.w(it, "WebView cache clear failed") }

            Timber.i("WebView site data wiped (cookies + storage + cache)")
        }
    }

    internal fun parseCookieHeader(header: String): Map<String, String> {
        return header.split(';')
            .map { it.trim() }
            .mapNotNull { part ->
                val eq = part.indexOf('=')
                if (eq <= 0) null
                else part.substring(0, eq).trim() to part.substring(eq + 1).trim()
            }
            .toMap()
    }

    companion object {
        /**
         * Broad probe set — CookieManager only returns cookies that would be sent to each URL.
         * Include school-agnostic /lectio/ paths so path-scoped cookies still surface.
         */
        private val COOKIE_PROBE_URLS = listOf(
            LectioUrls.ORIGIN,
            "${LectioUrls.ORIGIN}/",
            "${LectioUrls.ORIGIN}/lectio/",
            "${LectioUrls.ORIGIN}/lectio/login.aspx",
            "${LectioUrls.ORIGIN}/lectio/forside.aspx",
            "${LectioUrls.ORIGIN}/lectio/integration/unilogin.aspx",
            "https://lectio.dk",
            "https://lectio.dk/",
            "https://lectio.dk/lectio/",
        )

        internal fun cookieProbeUrls(schoolId: String?): List<String> {
            val generic = COOKIE_PROBE_URLS
            val id = schoolId?.trim()?.takeIf { it.isNotEmpty() } ?: return generic
            val schoolSpecific = listOf(
                "${LectioUrls.ORIGIN}/lectio/$id/",
                "${LectioUrls.ORIGIN}/lectio/$id/login.aspx",
                "${LectioUrls.ORIGIN}/lectio/$id/forside.aspx",
                "${LectioUrls.ORIGIN}/lectio/$id/SkemaNy.aspx",
                "https://lectio.dk/lectio/$id/",
                "https://lectio.dk/lectio/$id/forside.aspx",
            )
            return schoolSpecific + generic
        }
    }
}
