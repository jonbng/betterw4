package dk.betterlectio.android.core.lectio.model

/**
 * Request priority for the serial Lectio rate limiter.
 * iOS parity: [LectioHTTPClient.FetchPriority]
 */
enum class FetchPriority {
    /** User-facing / primary loads — jump ahead of opportunistic work. */
    Important,

    /** Prefetch / background — waits until no important work is queued. */
    Opportunistic,
}
