package dk.betterlectio.android.core.lectio.auth

import dagger.Lazy
import dk.betterlectio.android.core.lectio.session.SessionExternalWiper
import dk.betterlectio.android.feature.supabase.SupabaseAuthService
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Wipes WebView + Supabase local auth after Lectio logout.
 *
 * [SupabaseAuthService] is [Lazy] to break the DI cycle:
 * SessionController → SessionExternalWiper → SupabaseAuthService → LectioQrMinter → LectioClient → SessionController
 */
@Singleton
class DefaultSessionExternalWiper @Inject constructor(
    private val webViewCookieExtractor: WebViewCookieExtractor,
    private val supabaseAuth: Lazy<SupabaseAuthService>,
) : SessionExternalWiper {

    override suspend fun wipeExternalAuthState() {
        runCatching { webViewCookieExtractor.clearAllWebViewData() }
            .onFailure {
                Timber.w(it, "WebView wipe failed — falling back to cookie clear")
                webViewCookieExtractor.clearLectioCookies()
            }
        runCatching { supabaseAuth.get().signOutLocal() }
            .onFailure { Timber.w(it, "Supabase local sign-out failed") }
        Timber.i("External auth state wiped (WebView + Supabase)")
    }
}
