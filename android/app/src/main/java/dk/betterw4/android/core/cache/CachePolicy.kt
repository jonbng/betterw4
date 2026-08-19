package dk.betterw4.android.core.cache

/**
 * Per-surface TTLs matching iOS `CachePolicy.swift` (features.md §2.5).
 * Android's [SimpleCache] used to serve HTML forever — that is deliberately not ported.
 */
enum class W4Surface {
    HOME,
    TIMETABLE_ACADEMICS,
    TIMETABLE_EXTRA_ACADEMICS,
    ASSESSMENTS,
    MAIL_INBOX,
    MAIL_ARCHIVE,
    MAIL_MESSAGE,
    ATTENDANCE_ACADEMICS,
    ATTENDANCE_EXTRA_ACADEMICS,
    ATTENDANCE_METERS,
    GRADES,
    DOCUMENTS,
    TRIPS,
    TRAVEL,
    PEOPLE,
    CLASSES,
    ON_DUTY,
    PROFILE,
    EXTRA_ACADEMICS,
    RESOURCES,
    FEEDS,
    CHROME,
}

object CachePolicy {
    fun ttlMs(surface: W4Surface): Long = when (surface) {
        W4Surface.CHROME -> 60_000L
        W4Surface.MAIL_INBOX, W4Surface.MAIL_ARCHIVE -> 5 * 60_000L
        W4Surface.HOME, W4Surface.ASSESSMENTS, W4Surface.ATTENDANCE_METERS,
        W4Surface.ON_DUTY -> 15 * 60_000L
        W4Surface.TIMETABLE_ACADEMICS, W4Surface.TIMETABLE_EXTRA_ACADEMICS,
        W4Surface.CLASSES -> 30 * 60_000L
        W4Surface.ATTENDANCE_ACADEMICS, W4Surface.ATTENDANCE_EXTRA_ACADEMICS,
        W4Surface.GRADES, W4Surface.TRIPS, W4Surface.TRAVEL -> 30 * 60_000L
        W4Surface.EXTRA_ACADEMICS, W4Surface.RESOURCES, W4Surface.PROFILE -> 60 * 60_000L
        W4Surface.DOCUMENTS, W4Surface.FEEDS -> 6 * 60 * 60_000L
        W4Surface.MAIL_MESSAGE -> Long.MAX_VALUE
        W4Surface.PEOPLE -> 7 * 24 * 60 * 60_000L
    }

    fun isFresh(fetchedAtMs: Long, surface: W4Surface, nowMs: Long = System.currentTimeMillis()): Boolean {
        val ttl = ttlMs(surface)
        if (ttl == Long.MAX_VALUE) return true
        return nowMs - fetchedAtMs < ttl
    }
}
