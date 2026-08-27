package dk.betterw4.android.core.analytics

import com.posthog.PostHog
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Error
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Small, process-wide boundary around PostHog.
 *
 * Telemetry must never become a new failure mode, and callers must not need to know whether
 * PostHog was configured for this build. Keep payloads technical: never include URLs with query
 * strings, request bodies, HTML, credentials, or message contents.
 */
object AppTelemetry {
    private val initialized = AtomicBoolean(false)

    fun markInitialized() {
        initialized.set(true)
    }

    fun capture(event: String, properties: Map<String, Any> = emptyMap()): Boolean {
        if (!initialized.get()) return false
        return runCatching { PostHog.capture(event = event, properties = properties) }.isSuccess
    }

    fun captureException(throwable: Throwable, properties: Map<String, Any> = emptyMap()) {
        if (!initialized.get()) return
        runCatching { PostHog.captureException(throwable, properties) }
    }

    fun identify(distinctId: String, userProperties: Map<String, Any>) {
        if (!initialized.get()) return
        runCatching { PostHog.identify(distinctId = distinctId, userProperties = userProperties) }
    }

    fun reset() {
        if (!initialized.get()) return
        runCatching { PostHog.reset() }
    }

    fun flush() {
        if (!initialized.get()) return
        runCatching { PostHog.flush() }
    }

    fun reportW4Failure(
        error: W4Error,
        method: String,
        endpoint: String,
        priority: FetchPriority,
        durationMs: Long,
    ) {
        val statusCode = error.httpStatusCode()
        val timeout = error.isTimeout()
        val properties = buildMap<String, Any> {
            put("operation", "w4_request")
            put("method", method)
            put("endpoint", endpoint)
            put("priority", priority.name.lowercase())
            put("failure_type", error.telemetryName())
            put("duration_ms", durationMs)
            put("exception_class", (error.cause ?: error).javaClass.name)
            put("error_message", error.telemetryMessage())
            put("is_timeout", timeout)
            put("is_server_error", statusCode?.let { it >= 500 } == true || error is W4Error.ServerConflict)
            statusCode?.let { put("status_code", it) }
        }

        capture("w4_request_failed", properties)

        when (error) {
            W4Error.Offline,
            W4Error.SessionExpired,
            W4Error.InvalidCredentials,
            W4Error.MissingCookies,
            W4Error.RobotDetection,
            W4Error.Forbidden,
            -> Unit

            is W4Error.Http,
            is W4Error.Network,
            is W4Error.Parse,
            is W4Error.ServerConflict,
            is W4Error.Unknown,
            -> captureException(error.telemetryThrowable(), properties)
        }
    }

    fun reportSlowW4Request(
        method: String,
        endpoint: String,
        priority: FetchPriority,
        durationMs: Long,
    ) {
        val properties = mapOf(
            "method" to method,
            "endpoint" to endpoint,
            "priority" to priority.name.lowercase(),
            "duration_ms" to durationMs,
            "threshold_ms" to SLOW_REQUEST_THRESHOLD_MS,
        )
        capture("w4_request_slow", properties)
        captureException(SlowW4RequestException(method, endpoint, durationMs), properties)
    }

    fun reportParsingFailure(area: String, message: String, cause: Throwable? = null) {
        captureException(
            cause ?: ParsingFailure(message),
            mapOf(
                "operation" to "parsing",
                "parser_area" to area,
                "failure_type" to "parsing",
            ),
        )
    }

    fun reportExternalRequestFailure(
        endpoint: String,
        statusCode: Int? = null,
        cause: Throwable? = null,
    ) {
        val properties = buildMap<String, Any> {
            put("operation", "external_request")
            put("endpoint", endpoint)
            statusCode?.let { put("status_code", it) }
        }
        if (cause != null) {
            captureException(cause, properties)
        } else {
            capture("external_request_failed", properties)
        }
    }

    fun reportSevereUiStall(durationMs: Long) {
        val properties = mapOf(
            "duration_ms" to durationMs,
            "threshold_ms" to SEVERE_UI_STALL_THRESHOLD_MS,
        )
        capture("severe_ui_stall", properties)
        captureException(SevereUiStallException(durationMs), properties)
    }

    private fun W4Error.telemetryName(): String = when (this) {
        W4Error.Offline -> "offline"
        W4Error.SessionExpired -> "session_expired"
        W4Error.InvalidCredentials -> "invalid_credentials"
        W4Error.MissingCookies -> "missing_cookies"
        W4Error.RobotDetection -> "robot_detection"
        W4Error.Forbidden -> "forbidden"
        is W4Error.ServerConflict -> "server_conflict"
        is W4Error.Http -> "http_$code"
        is W4Error.Network -> "network"
        is W4Error.Parse -> "parsing"
        is W4Error.Unknown -> "unknown"
    }

    private fun W4Error.httpStatusCode(): Int? = when (this) {
        is W4Error.Http -> code
        is W4Error.ServerConflict -> 409
        else -> null
    }

    private fun W4Error.isTimeout(): Boolean {
        val statusCode = httpStatusCode()
        if (statusCode == 408 || statusCode == 504) return true

        var current: Throwable? = this
        repeat(MAX_CAUSE_DEPTH) {
            if (current is SocketTimeoutException ||
                current?.javaClass?.simpleName?.contains("timeout", ignoreCase = true) == true ||
                current?.message?.contains("timed out", ignoreCase = true) == true
            ) {
                return true
            }
            current = current?.cause
        }
        return false
    }

    private fun W4Error.telemetryMessage(): String = when (this) {
        // HTTP 409 bodies can contain full HTML or user-visible server content.
        is W4Error.ServerConflict -> "HTTP 409 server conflict"
        else -> message.orEmpty().take(MAX_ERROR_MESSAGE_LENGTH)
    }

    private fun W4Error.telemetryThrowable(): Throwable = when (this) {
        is W4Error.ServerConflict -> RuntimeException(telemetryMessage())
        else -> cause ?: this
    }

    private class ParsingFailure(message: String) : RuntimeException(message)
    private class SlowW4RequestException(method: String, endpoint: String, durationMs: Long) :
        RuntimeException("$method $endpoint took ${durationMs}ms")

    private class SevereUiStallException(durationMs: Long) :
        RuntimeException("Main thread stalled for ${durationMs}ms")

    const val SLOW_REQUEST_THRESHOLD_MS = 10_000L
    const val SEVERE_UI_STALL_THRESHOLD_MS = 700L
    private const val MAX_CAUSE_DEPTH = 20
    private const val MAX_ERROR_MESSAGE_LENGTH = 500
}
