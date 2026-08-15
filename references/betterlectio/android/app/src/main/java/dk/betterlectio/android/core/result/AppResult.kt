package dk.betterlectio.android.core.result

/**
 * Lightweight result type for domain / repository layers.
 * Prefer over exceptions for expected Lectio failures (session, parse, offline).
 */
sealed class AppResult<out T> {
    data class Success<T>(val data: T) : AppResult<T>()
    data class Failure(val error: AppError) : AppResult<Nothing>()

    val isSuccess: Boolean get() = this is Success
    val isFailure: Boolean get() = this is Failure

    fun getOrNull(): T? = (this as? Success)?.data

    fun errorOrNull(): AppError? = (this as? Failure)?.error

    inline fun <R> map(transform: (T) -> R): AppResult<R> = when (this) {
        is Success -> Success(transform(data))
        is Failure -> this
    }

    inline fun onSuccess(block: (T) -> Unit): AppResult<T> {
        if (this is Success) block(data)
        return this
    }

    inline fun onFailure(block: (AppError) -> Unit): AppResult<T> {
        if (this is Failure) block(error)
        return this
    }
}

sealed class AppError {
    data object Offline : AppError()
    data object SessionExpired : AppError()
    data object RobotDetection : AppError()
    data object Unauthorized : AppError()
    data class Network(val message: String? = null, val cause: Throwable? = null) : AppError()
    data class Parsing(val message: String, val cause: Throwable? = null) : AppError()
    data class Unknown(val message: String? = null, val cause: Throwable? = null) : AppError()
}

inline fun <T> appRunCatching(block: () -> T): AppResult<T> = try {
    AppResult.Success(block())
} catch (t: Throwable) {
    AppResult.Failure(AppError.Unknown(t.message, t))
}
