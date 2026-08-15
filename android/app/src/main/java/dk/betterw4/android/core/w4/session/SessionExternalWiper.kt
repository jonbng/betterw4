package dk.betterw4.android.core.w4.session

/**
 * Extra wipe after [SessionController.clearSession] (WebView cookies/storage).
 */
interface SessionExternalWiper {
    suspend fun wipeExternalAuthState()
}
