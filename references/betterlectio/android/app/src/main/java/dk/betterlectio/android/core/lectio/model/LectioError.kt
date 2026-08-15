package dk.betterlectio.android.core.lectio.model

import dk.betterlectio.android.core.result.AppError

/**
 * Typed Lectio client failures.
 * iOS parity: `StudentModels.LectioError`
 */
sealed class LectioError : Exception() {
    data object Offline : LectioError() {
        private fun readResolve(): Any = Offline
        // Exception messages are English technical fallbacks; UI uses AppError + strings.
        override val message: String = "No internet connection"
    }

    /** Definitive: autologin dead; UI must re-auth. */
    data object SessionExpired : LectioError() {
        private fun readResolve(): Any = SessionExpired
        override val message: String = "Session expired"
    }

    /** Retryable auth blip before we declare session expired. */
    data object InvalidCredentials : LectioError() {
        private fun readResolve(): Any = InvalidCredentials
        override val message: String = "Invalid credentials"
    }

    data object MissingCookies : LectioError() {
        private fun readResolve(): Any = MissingCookies
        override val message: String = "Missing cookies"
    }

    data object RobotDetection : LectioError() {
        private fun readResolve(): Any = RobotDetection
        override val message: String = "Robot detection"
    }

    data class Http(val code: Int) : LectioError() {
        override val message: String = "HTTP $code"
    }

    data class Network(override val cause: Throwable? = null) : LectioError() {
        override val message: String = cause?.message ?: "Network error"
    }

    data class Parse(
        override val message: String,
        override val cause: Throwable? = null,
    ) : LectioError()

    data class Unknown(
        override val message: String? = null,
        override val cause: Throwable? = null,
    ) : LectioError()

    fun toAppError(): AppError = when (this) {
        Offline -> AppError.Offline
        SessionExpired, InvalidCredentials, MissingCookies -> AppError.SessionExpired
        RobotDetection -> AppError.RobotDetection
        is Http -> AppError.Network(message = message)
        is Network -> AppError.Network(message = message, cause = cause)
        is Parse -> AppError.Parsing(message = message, cause = cause)
        is Unknown -> AppError.Unknown(message = message, cause = cause)
    }
}
