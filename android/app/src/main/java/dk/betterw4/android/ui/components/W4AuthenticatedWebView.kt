package dk.betterw4.android.ui.components

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.R
import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Session
import dk.betterw4.android.core.w4.http.W4UserAgent
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.w4.session.SessionEvents
import javax.inject.Inject

data class W4WebTarget(
    val title: String,
    val url: String,
)

@HiltViewModel
class W4WebViewModel @Inject constructor(
    private val session: SessionController,
    private val sessionEvents: SessionEvents,
) : ViewModel() {
    val isDemo: Boolean get() = session.currentStudent?.isDemo == true
    val credentials: W4Credentials? get() = session.loadCredentialsForCurrentStudent()
    fun onSessionExpired() = sessionEvents.emitSessionExpired()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun W4WebSheet(
    target: W4WebTarget?,
    onDismiss: () -> Unit,
    viewModel: W4WebViewModel = hiltViewModel(),
) {
    if (target == null) return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(target.title) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cd_back))
                        }
                    },
                )
            },
        ) { padding ->
            W4AuthenticatedWebView(
                url = target.url,
                credentials = viewModel.credentials,
                isDemo = viewModel.isDemo,
                onSessionExpired = viewModel::onSessionExpired,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun W4AuthenticatedWebView(
    url: String,
    credentials: W4Credentials?,
    isDemo: Boolean,
    onSessionExpired: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    if (isDemo || credentials == null || credentials.sessionId.isBlank()) {
        Box(modifier, contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.webview_demo_unavailable))
        }
        return
    }
    var loading by remember { mutableStateOf(true) }
    Box(modifier) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                WebView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.userAgentString = W4UserAgent.VALUE
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    webChromeClient = WebChromeClient()
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            request: WebResourceRequest,
                        ): Boolean {
                            val target = request.url ?: return false
                            if (request.isForMainFrame && W4Session.isLoginUrl(target.toString())) {
                                onSessionExpired()
                                return true
                            }
                            val host = target.host
                            if (W4Hosts.isW4Host(host) || !request.isForMainFrame) return false
                            if (target.scheme.equals("http", true) || target.scheme.equals("https", true)) {
                                runCatching {
                                    ctx.startActivity(Intent(Intent.ACTION_VIEW, target))
                                }
                                return true
                            }
                            return false
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            loading = true
                            if (url != null && W4Session.isLoginUrl(url)) {
                                onSessionExpired()
                            }
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            loading = false
                        }
                    }
                    val cookie =
                        "${W4Credentials.COOKIE_SESSION_ID}=${credentials.sessionId}; Path=/; Secure"
                    CookieManager.getInstance().setCookie(W4Hosts.ORIGIN, cookie) {
                        CookieManager.getInstance().flush()
                        loadUrl(url)
                    }
                }
            },
            update = { webView ->
                if (webView.url != url) {
                    val cookie =
                        "${W4Credentials.COOKIE_SESSION_ID}=${credentials.sessionId}; Path=/; Secure"
                    CookieManager.getInstance().setCookie(W4Hosts.ORIGIN, cookie) {
                        CookieManager.getInstance().flush()
                        webView.loadUrl(url)
                    }
                }
            },
        )
        if (loading) {
            CircularProgressIndicator(Modifier.align(Alignment.Center))
        }
    }
}

fun openExternalOrW4(url: String, onW4: (String) -> Unit, startExternal: (Uri) -> Unit) {
    val host = runCatching { Uri.parse(url).host }.getOrNull()
    if (W4Hosts.isW4Host(host) || url.startsWith("/") || url.contains("index.php?r=")) {
        onW4(url)
    } else {
        startExternal(Uri.parse(url))
    }
}
