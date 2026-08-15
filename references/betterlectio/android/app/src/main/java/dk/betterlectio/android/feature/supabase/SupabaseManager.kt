package dk.betterlectio.android.feature.supabase

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Owns the optional official Supabase Kotlin client (iOS: `SupabaseManager`).
 * When not configured, [client] is null and all services skip remote work.
 *
 * [awaitSessionReady] lets callers wait until cold-start / login auth bootstrap finishes
 * so RLS-protected RPCs don't race the edge-function mint.
 */
@Singleton
class SupabaseManager @Inject constructor(
    val configuration: SupabaseConfig,
) {
    val client: SupabaseClient? = if (configuration.isConfigured) {
        createSupabaseClient(
            supabaseUrl = configuration.url.trimEnd('/'),
            supabaseKey = configuration.publishableKey,
        ) {
            install(Auth)
            install(Postgrest)
            install(Functions)
            install(Storage)
        }
    } else {
        Timber.w("Supabase not configured (SUPABASE_URL / SUPABASE_ANON_KEY); remote sync disabled")
        null
    }

    val isConfigured: Boolean get() = client != null

    /**
     * Completes when Supabase auth bootstrap is done (or immediately if unconfigured).
     * Reset on logout so the next login re-gates.
     */
    private val sessionGate = SupabaseSessionGate(isConfigured)

    fun completeSessionBootstrap(result: SupabaseSessionState) {
        sessionGate.complete(result)
        Timber.d("Supabase session gate completed: %s", result)
    }

    /** After logout — next login must re-mint before remote work. */
    fun resetSessionReady() {
        sessionGate.reset()
        Timber.d("Supabase session gate: reset")
    }

    /**
     * Wait until auth bootstrap completes. A timeout is an unavailable state; callers must
     * skip their remote operation so an anonymous request cannot race authentication.
     */
    suspend fun awaitSessionReady(timeoutMs: Long = SESSION_READY_TIMEOUT_MS): SupabaseSessionState {
        val result = sessionGate.await(timeoutMs)
        if (result == SupabaseSessionState.Unavailable(SupabaseUnavailableReason.TIMEOUT)) {
            Timber.w("Supabase session gate: timed out after %dms", timeoutMs)
        }
        return result
    }

    companion object {
        const val SESSION_READY_TIMEOUT_MS = 15_000L
    }
}

internal class SupabaseSessionGate(
    private val enabled: Boolean,
) {
    @Volatile
    private var state = initialState()

    @Synchronized
    fun complete(result: SupabaseSessionState) {
        val current = state
        if (!current.isCompleted) {
            current.complete(result)
        } else {
            state = CompletableDeferred<SupabaseSessionState>().also { it.complete(result) }
        }
    }

    @Synchronized
    fun reset() {
        state = initialState()
    }

    suspend fun await(timeoutMs: Long): SupabaseSessionState {
        val result = withTimeoutOrNull(timeoutMs) { state.await() }
        return result ?: SupabaseSessionState.Unavailable(SupabaseUnavailableReason.TIMEOUT)
    }

    private fun initialState(): CompletableDeferred<SupabaseSessionState> =
        if (enabled) {
            CompletableDeferred()
        } else {
            CompletableDeferred<SupabaseSessionState>().also {
                it.complete(
                    SupabaseSessionState.Unavailable(SupabaseUnavailableReason.NOT_CONFIGURED),
                )
            }
        }
}
