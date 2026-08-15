package dk.betterlectio.android.feature.supabase

sealed interface SupabaseSessionState {
    data object Ready : SupabaseSessionState

    data class Unavailable(
        val reason: SupabaseUnavailableReason,
    ) : SupabaseSessionState
}

enum class SupabaseUnavailableReason {
    NOT_CONFIGURED,
    DEMO_SESSION,
    MISSING_CREDENTIALS,
    AUTHENTICATION_FAILED,
    IDENTITY_MISMATCH,
    QR_MINT_FAILED,
    /** @deprecated Cookie handoff removed; kept for binary/test compatibility. */
    COOKIE_PERSISTENCE_FAILED,
    TIMEOUT,
}

class SupabaseUnavailableException(
    val reason: SupabaseUnavailableReason,
) : IllegalStateException("Supabase session unavailable: $reason")
