package dk.betterlectio.android.ui.auth

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import dk.betterlectio.android.BuildConfig
import dk.betterlectio.android.R
import dk.betterlectio.android.core.lectio.auth.MitIdAuthUrls
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.model.School
import timber.log.Timber
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Holds latest Compose callbacks so a long-lived WebView never sees stale lambdas.
 */
private class MitIdWebViewCallbacks {
    /** Fired immediately when auth success is detected — show loading overlay over Lectio chrome. */
    var onLoginDetected: () -> Unit = {}
    var onLoginComplete: (callbackUrl: String) -> Unit = {}
    var onExternalAppLaunchFailed: ((String) -> Unit)? = null
    val completed = AtomicBoolean(false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** Show loading overlay as soon as we know auth succeeded (before cookies settle). */
    fun signalDetected() {
        onLoginDetected()
    }

    /**
     * Finish as soon as Lectio session cookies are readable (or after a short cap).
     *
     * Previously a fixed 500ms sleep after [onPageFinished] left users staring at a fully
     * loaded forside. iOS uses ~0.3s only after UniLogin callback; forside completes
     * immediately. We poll CookieManager so the common case exits in one frame.
     *
     * UniLogin integration must load first (see [shouldOverrideUrlLoading]) so Lectio can
     * mint cookies; only forside is completed from navigation without waiting for paint.
     */
    fun completeOnce(callbackUrl: String) {
        if (!completed.compareAndSet(false, true)) return
        onLoginDetected()
        scope.launch {
            val cm = CookieManager.getInstance()
            cm.flush()
            val deadline = SystemClock.elapsedRealtime() + COOKIE_WAIT_MAX_MS
            var waited = 0L
            while (SystemClock.elapsedRealtime() < deadline) {
                if (hasLectioSessionCookies(cm)) {
                    Timber.d(
                        "MitID cookies ready after %dms (url=%s)",
                        waited,
                        callbackUrl.take(120),
                    )
                    break
                }
                delay(COOKIE_POLL_MS)
                waited += COOKIE_POLL_MS
            }
            if (!hasLectioSessionCookies(cm)) {
                Timber.w(
                    "MitID cookie poll timed out after %dms — proceeding (HTTP replay may still recover)",
                    COOKIE_WAIT_MAX_MS,
                )
            }
            cm.flush()
            onLoginComplete(callbackUrl)
        }
    }

    fun dispose() {
        scope.cancel()
    }

    companion object {
        /** Cap matches iOS UniLogin didFinish delay; usually exit much earlier via poll. */
        private const val COOKIE_WAIT_MAX_MS = 300L
        private const val COOKIE_POLL_MS = 40L

        /**
         * True when CookieManager has the two cookies required by [WebViewCookieExtractor].
         * Probe a few Lectio URLs — cookies can be path-scoped.
         */
        fun hasLectioSessionCookies(cm: CookieManager): Boolean {
            val probes = listOf(
                "https://www.lectio.dk/",
                "https://www.lectio.dk/lectio/",
                "https://www.lectio.dk/lectio/integration/unilogin.aspx",
            )
            var hasAutologin = false
            var hasSession = false
            for (url in probes) {
                val header = cm.getCookie(url) ?: continue
                if (header.contains(LectioCredentials.COOKIE_AUTOLOGIN)) hasAutologin = true
                if (header.contains(LectioCredentials.COOKIE_SESSION_ID)) hasSession = true
                if (hasAutologin && hasSession) return true
            }
            return false
        }
    }
}

/**
 * Full MitID / UniLogin WebView for Lectio login.
 *
 * Critical (iOS parity): do **not** cancel navigation to the UniLogin integration callback.
 * Cancelling prevented Lectio from minting session cookies and caused
 * "Could not parse student id" after cookie extract.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun MitIdWebView(
    school: School,
    onLoginComplete: (callbackUrl: String) -> Unit,
    onLoginDetected: () -> Unit = {},
    onExternalAppLaunchFailed: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val loginUrl = remember(school.id) {
        "https://www.lectio.dk/lectio/${school.id}/login.aspx"
    }

    val callbacks = remember { MitIdWebViewCallbacks() }
    callbacks.onLoginDetected = onLoginDetected
    callbacks.onLoginComplete = onLoginComplete
    callbacks.onExternalAppLaunchFailed = onExternalAppLaunchFailed

    val webView = remember(school.id) {
        WebView(context).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.loadWithOverviewMode = true
            settings.useWideViewPort = true
            settings.setSupportMultipleWindows(false)
            settings.javaScriptCanOpenWindowsAutomatically = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE

            val cookieManager = CookieManager.getInstance()
            cookieManager.setAcceptCookie(true)
            cookieManager.setAcceptThirdPartyCookies(this, true)

            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): Boolean {
                    val url = request?.url?.toString().orEmpty()
                    if (url.isEmpty()) return false

                    Timber.d("MitID WebView nav: %s", url)

                    // External MitID app switch — leave WebView.
                    if (MitIdAuthUrls.isExternalAppUrl(url)) {
                        val launched = launchExternalApp(context, url)
                        if (!launched) {
                            Timber.w("Failed to open MitID / external URL: %s", url)
                            callbacks.onExternalAppLaunchFailed?.invoke(url)
                        }
                        return true
                    }

                    if (MitIdAuthUrls.isAuthSuccessUrl(url)) {
                        val lower = url.lowercase()
                        // iOS: cancel forside and extract immediately — cookies already
                        // minted on the redirect chain; no need to paint Lectio chrome.
                        if (lower.contains("/forside.aspx")) {
                            Timber.d("MitID forside success — completing without painting: %s", url)
                            callbacks.completeOnce(url)
                            return true
                        }
                        // UniLogin integration: MUST allow load so Lectio can mint cookies
                        // (cancelling here was the original "Could not parse student id" bug).
                        // Show overlay now; complete from onPageFinished once the page settled.
                        Timber.d("MitID UniLogin callback — allowing load (overlay on): %s", url)
                        callbacks.signalDetected()
                        return false
                    }

                    return false
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    super.onPageFinished(view, url)
                    val u = url.orEmpty()
                    Timber.d("MitID WebView finished: %s", u)
                    if (BuildConfig.DEBUG) {
                        view?.evaluateJavascript(
                            """
                            (() => JSON.stringify({
                              href: location.href,
                              title: document.title,
                              readyState: document.readyState,
                              bodyText: (document.body && document.body.innerText || '').slice(0, 160),
                              elevidLinks: document.querySelectorAll('a[href*="elevid"]').length,
                              laereridLinks: document.querySelectorAll('a[href*="laererid"]').length,
                              studentCards: document.querySelectorAll('[data-lectiocontextcard^="S"],[data-lectioContextCard^="S"]').length,
                              teacherCards: document.querySelectorAll('[data-lectiocontextcard^="T"],[data-lectioContextCard^="T"]').length,
                              hasMainTitle: !!document.querySelector('#s_m_HeaderContent_MainTitle'),
                              hasSubHeader: !!document.querySelector('div[id*="subHeaderDiv"]')
                            }))()
                            """.trimIndent(),
                        ) { result ->
                            Timber.d("MitID WebView DOM probe: %s", result)
                        }
                    }
                    // Backup if success was reached without shouldOverride (e.g. after app switch).
                    if (MitIdAuthUrls.isAuthSuccessUrl(u)) {
                        callbacks.completeOnce(u)
                    }
                }

                override fun onReceivedError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    error: WebResourceError?,
                ) {
                    val failing = request?.url?.toString().orEmpty()
                    Timber.d(
                        "MitID WebView error (ignored if mid app-switch): %s code=%s",
                        failing,
                        error?.errorCode,
                    )
                    if (request?.isForMainFrame == true &&
                        MitIdAuthUrls.isMitIdAppSwitchUrl(failing)
                    ) {
                        return
                    }
                    super.onReceivedError(view, request, error)
                }
            }

            loadUrl(loginUrl)
        }
    }

    DisposableEffect(webView, lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    webView.onResume()
                    // After MitID app returns, page may already be at callback/forside.
                    webView.url?.let { current ->
                        if (MitIdAuthUrls.isAuthSuccessUrl(current)) {
                            callbacks.completeOnce(current)
                        }
                    }
                }
                Lifecycle.Event.ON_PAUSE -> webView.onPause()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            callbacks.dispose()
            webView.stopLoading()
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView.destroy()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = {
            (webView.parent as? ViewGroup)?.removeView(webView)
            webView
        },
    )
}

/**
 * Open MitID (or other eID) via ACTION_VIEW / intent:// parse.
 * Uses a chooser for appswitch HTTPS like Flutter's `launchChooser("Vælg app")`.
 *
 * Do not strip `returnUrl=Chrome` — MitID needs it for same-device approval;
 * without it the app falls back to the cross-device QR flow.
 */
internal fun launchExternalApp(context: Context, url: String): Boolean {
    return try {
        val intent = buildExternalIntent(url) ?: return false
        val chooserLabel = context.getString(R.string.login_mitid_app_chooser)
        val launch = if (MitIdAuthUrls.isMitIdAppSwitchUrl(url) &&
            (url.startsWith("http://", ignoreCase = true) ||
                url.startsWith("https://", ignoreCase = true))
        ) {
            Intent.createChooser(intent, chooserLabel)
        } else {
            intent
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(launch)
        true
    } catch (e: ActivityNotFoundException) {
        Timber.w(e, "No activity for MitID URL: %s", url)
        false
    } catch (e: Exception) {
        Timber.e(e, "Error launching MitID URL: %s", url)
        false
    }
}

internal fun buildExternalIntent(url: String): Intent? {
    return when {
        url.startsWith("intent:", ignoreCase = true) -> {
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
        }
        else -> Intent(Intent.ACTION_VIEW, Uri.parse(url))
    }
}
