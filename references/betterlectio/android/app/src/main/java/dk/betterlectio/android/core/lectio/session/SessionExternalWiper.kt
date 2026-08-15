package dk.betterlectio.android.core.lectio.session

/**
 * Non-Keychain half of iOS `AuthenticationService.wipeAuthState`:
 * WebView/UniLogin site data + Supabase local session.
 *
 * Always call after [SessionController.clearSession] on force-logout / session death
 * so the next MitID login does not inherit a poisoned jar.
 */
interface SessionExternalWiper {
    suspend fun wipeExternalAuthState()
}
