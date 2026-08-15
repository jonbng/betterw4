package dk.betterlectio.android.core.lectio.http

import dk.betterlectio.android.core.lectio.model.FetchPriority
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import timber.log.Timber

/**
 * Serializes Lectio HTTP attempts AND enforces a minimum gap between consecutive requests.
 *
 * iOS parity: PriorityRequestLimiter in LectioHTTPClient.swift —
 * concurrent redirect races can look like token replay to Lectio's autologin detector.
 *
 * Cancellation-safe: cancelled waiters are removed from the queue; if a waiter already
 * received the permit and is then cancelled, the permit is released for the next waiter.
 *
 * [acquireTimeoutMs] prevents UI spins forever when a background job holds the slot
 * (e.g. NotificationDiffWorker stuck on a hung request).
 */
class PriorityRequestLimiter(
    private val minIntervalMs: Long = 100L,
    private val acquireTimeoutMs: Long = DEFAULT_ACQUIRE_TIMEOUT_MS,
) {
    private val mutex = Mutex()
    private var busy = false
    private val importantWaiters = ArrayDeque<CompletableDeferred<Unit>>()
    private val opportunisticWaiters = ArrayDeque<CompletableDeferred<Unit>>()
    private var lastEndedAtMs: Long = 0L

    suspend fun <T> withPermit(priority: FetchPriority, block: suspend () -> T): T {
        try {
            withTimeout(acquireTimeoutMs) {
                acquire(priority)
            }
        } catch (e: TimeoutCancellationException) {
            Timber.w(
                "Lectio request limiter acquire timed out after %dms (priority=%s, busy, queue i=%d o=%d)",
                acquireTimeoutMs,
                priority,
                importantWaiters.size,
                opportunisticWaiters.size,
            )
            throw e
        }
        try {
            val elapsed = System.currentTimeMillis() - lastEndedAtMs
            if (lastEndedAtMs > 0L && elapsed < minIntervalMs) {
                delay(minIntervalMs - elapsed)
            }
            return block()
        } finally {
            release()
        }
    }

    private suspend fun acquire(priority: FetchPriority) {
        val waiter = mutex.withLock {
            val canTakeImmediately = when (priority) {
                FetchPriority.Important -> !busy
                FetchPriority.Opportunistic -> !busy && importantWaiters.isEmpty()
            }
            if (canTakeImmediately) {
                busy = true
                null
            } else {
                Timber.d(
                    "Lectio limiter queueing %s (busy=%s, i=%d o=%d)",
                    priority,
                    busy,
                    importantWaiters.size,
                    opportunisticWaiters.size,
                )
                val deferred = CompletableDeferred<Unit>()
                when (priority) {
                    FetchPriority.Important -> importantWaiters.addLast(deferred)
                    FetchPriority.Opportunistic -> opportunisticWaiters.addLast(deferred)
                }
                deferred
            }
        }
        if (waiter == null) return
        try {
            waiter.await()
        } catch (e: CancellationException) {
            val ownsSlot = mutex.withLock {
                val stillQueued =
                    importantWaiters.remove(waiter) || opportunisticWaiters.remove(waiter)
                // Slot already transferred to us (complete succeeded) but we cancelled before block.
                !stillQueued && waiter.isCompleted && !waiter.isCancelled
            }
            if (ownsSlot) {
                release()
            }
            throw e
        }
    }

    private suspend fun release() {
        mutex.withLock {
            lastEndedAtMs = System.currentTimeMillis()
            while (true) {
                val next = importantWaiters.removeFirstOrNull()
                    ?: opportunisticWaiters.removeFirstOrNull()
                if (next == null) {
                    busy = false
                    break
                }
                // complete() returns false if the waiter was already cancelled/completed.
                if (next.complete(Unit)) break
            }
        }
    }

    companion object {
        /** Max wait for a free slot before failing the request (not the HTTP timeout). */
        const val DEFAULT_ACQUIRE_TIMEOUT_MS = 90_000L
    }
}
