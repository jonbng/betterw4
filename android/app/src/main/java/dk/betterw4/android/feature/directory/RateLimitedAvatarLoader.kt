package dk.betterw4.android.feature.directory

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Token-bucket style rate limiter for avatar/image URL loads.
 */
@Singleton
class RateLimitedAvatarLoader @Inject constructor() {
    private val maxConcurrent: Int = 4
    private val minIntervalMs: Long = 80L
    private val clock: () -> Long = { System.currentTimeMillis() }
    private val inFlight = AtomicInteger(0)
    /** Negative so first acquire is never blocked by interval. */
    private val lastStartMs = AtomicLong(Long.MIN_VALUE / 4)
    private val cache = ConcurrentHashMap<String, String>() // id -> last known url

    fun remember(entityId: String, url: String) {
        if (url.isNotBlank()) cache[entityId] = url
    }

    fun cachedUrl(entityId: String): String? = cache[entityId]

    /**
     * Returns true if a load may start now. Call [release] when the load finishes (success or fail).
     */
    @Synchronized
    fun acquire(): Boolean {
        if (inFlight.get() >= maxConcurrent) return false
        val now = clock()
        val last = lastStartMs.get()
        if (last != Long.MIN_VALUE / 4 && now - last < minIntervalMs) return false
        inFlight.incrementAndGet()
        lastStartMs.set(now)
        return true
    }

    fun release() {
        inFlight.updateAndGet { (it - 1).coerceAtLeast(0) }
    }

    fun inFlightCount(): Int = inFlight.get()

    /** Test helper: force-reset counters. */
    fun resetForTest() {
        inFlight.set(0)
        lastStartMs.set(Long.MIN_VALUE / 4)
        cache.clear()
    }
}
