package dk.betterw4.android.core.w4.model

import dk.betterw4.android.core.result.AppError

/**
 * Typed Lectio client failures.
 * iOS parity: `StudentModels.W4Error`
 */
sealed class W4Error : Exception() {
    data object Offline : W4Error() {
        private fun readResolve(): Any = Offline
        // Exception messages are English technical fallbacks; UI uses AppError + strings.
        override val message: String = "No internet connection"
    }

    /** Definitive: autologin dead; UI must re-auth. */
    data object SessionExpired : W4Error() {
        private fun readResolve(): Any = SessionExpired
        override val message: String = "Session expired"
    }

    /** Retryable auth blip before we declare session expired. */
    data object InvalidCredentials : W4Error() {
        private fun readResolve(): Any = InvalidCredentials
        override val message: String = "Invalid credentials"
    }

    data object MissingCookies : W4Error() {
        private fun readResolve(): Any = MissingCookies
        override val message: String = "Missing cookies"
    }

    data object RobotDetection : W4Error() {
        private fun readResolve(): Any = RobotDetection
        override val message: String = "Robot detection"
    }

    /** HTTP 403 without `Login Required` — logged in, wrong role. Not session expiry. */
    data object Forbidden : W4Error() {
        private fun readResolve(): Any = Forbidden
        override val message: String = "Not authorized"
    }

    /** HTTP 409 — Yii/AJAX server error; body is the message. */
    data class ServerConflict(val body: String) : W4Error() {
        override val message: String = body.ifBlank { "Server conflict" }
    }

    data class Http(val code: Int) : W4Error() {
        override val message: String = "HTTP $code"
    }

    data class Network(override val cause: Throwable? = null) : W4Error() {
        override val message: String = cause?.message ?: "Network error"
    }

    data class Parse(
        override val message: String,
        override val cause: Throwable? = null,
    ) : W4Error()

    data class Unknown(
        override val message: String? = null,
        override val cause: Throwable? = null,
    ) : W4Error()

    fun toAppError(): AppError = when (this) {
        Offline -> AppError.Offline
        SessionExpired, InvalidCredentials, MissingCookies -> AppError.SessionExpired
        RobotDetection -> AppError.RobotDetection
        // Wrong role, still logged in — do not bounce to native login (README §4.5).
        Forbidden -> AppError.Network(message = message)
        is ServerConflict -> AppError.Network(message = message)
        is Http -> AppError.Network(message = message)
        is Network -> AppError.Network(message = message, cause = cause)
        is Parse -> AppError.Parsing(message = message, cause = cause)
        is Unknown -> AppError.Unknown(message = message, cause = cause)
    }
}
