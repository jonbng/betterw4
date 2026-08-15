package dk.betterw4.android.core.w4.auth

import android.webkit.CookieManager
import android.webkit.WebStorage
import dk.betterw4.android.core.w4.session.SessionExternalWiper
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * Clears leftover WebView cookies/storage on logout.
 */
@Singleton
class DefaultSessionExternalWiper @Inject constructor() : SessionExternalWiper {

    override suspend fun wipeExternalAuthState() {
        runCatching {
            suspendCoroutine { cont ->
                CookieManager.getInstance().removeAllCookies {
                    CookieManager.getInstance().flush()
                    runCatching { WebStorage.getInstance().deleteAllData() }
                    cont.resume(Unit)
                }
            }
        }.onFailure { Timber.w(it, "WebView wipe failed") }
        Timber.i("External auth state wiped (WebView)")
    }
}
