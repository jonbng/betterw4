package dk.betterw4.android.core.analytics

import com.posthog.PostHog
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Error
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

    fun capture(event: String, properties: Map<String, Any> = emptyMap()) {
        if (!initialized.get()) return
        runCatching { PostHog.capture(event = event, properties = properties) }
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

    fun reportW4Failure(
        error: W4Error,
        method: String,
        endpoint: String,
        priority: FetchPriority,
        durationMs: Long,
    ) {
        val properties = mapOf(
            "operation" to "w4_request",
            "method" to method,
            "endpoint" to endpoint,
            "priority" to priority.name.lowercase(),
            "failure_type" to error.telemetryName(),
            "duration_ms" to durationMs,
        )

        when (error) {
            W4Error.Offline,
            W4Error.SessionExpired,
            W4Error.InvalidCredentials,
            W4Error.MissingCookies,
            W4Error.RobotDetection,
            W4Error.Forbidden,
            -> capture("w4_request_failed", properties)

            is W4Error.Http,
            is W4Error.Network,
            is W4Error.Parse,
            is W4Error.ServerConflict,
            is W4Error.Unknown,
            -> captureException(error, properties)
        }
    }

    fun reportSlowW4Request(
        method: String,
        endpoint: String,
        priority: FetchPriority,
        durationMs: Long,
    ) {
        capture(
            "w4_request_slow",
            mapOf(
                "method" to method,
                "endpoint" to endpoint,
                "priority" to priority.name.lowercase(),
                "duration_ms" to durationMs,
                "threshold_ms" to SLOW_REQUEST_THRESHOLD_MS,
            ),
        )
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
        capture(
            "severe_ui_stall",
            mapOf(
                "duration_ms" to durationMs,
                "threshold_ms" to SEVERE_UI_STALL_THRESHOLD_MS,
            ),
        )
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

    private class ParsingFailure(message: String) : RuntimeException(message)

    const val SLOW_REQUEST_THRESHOLD_MS = 10_000L
    const val SEVERE_UI_STALL_THRESHOLD_MS = 700L
}
