package dk.betterlectio.android.core.lectio.http

import dk.betterlectio.android.core.lectio.model.FetchPriority
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class PriorityRequestLimiterTest {

    @Test
    fun serializes_requests() = runBlocking {
        val limiter = PriorityRequestLimiter(minIntervalMs = 0)
        val concurrent = AtomicInteger(0)
        val maxConcurrent = AtomicInteger(0)

        val jobs = List(5) {
            async {
                limiter.withPermit(FetchPriority.Important) {
                    val now = concurrent.incrementAndGet()
                    maxConcurrent.updateAndGet { maxOf(it, now) }
                    delay(30)
                    concurrent.decrementAndGet()
                }
            }
        }
        jobs.forEach { it.await() }
        assertTrue("expected serial execution", maxConcurrent.get() == 1)
    }

    @Test
    fun important_runs_before_queued_opportunistic() = runBlocking {
        val limiter = PriorityRequestLimiter(minIntervalMs = 0)
        val order = mutableListOf<String>()

        // Hold the slot with an important request, queue opportunistic + important.
        val holder = async {
            limiter.withPermit(FetchPriority.Important) {
                order += "hold-start"
                delay(80)
                order += "hold-end"
            }
        }
        delay(10)
        val opp = async {
            limiter.withPermit(FetchPriority.Opportunistic) {
                order += "opp"
            }
        }
        delay(10)
        val imp = async {
            limiter.withPermit(FetchPriority.Important) {
                order += "imp"
            }
        }

        holder.await()
        opp.await()
        imp.await()

        val holdEnd = order.indexOf("hold-end")
        val impIdx = order.indexOf("imp")
        val oppIdx = order.indexOf("opp")
        assertTrue(impIdx > holdEnd)
        assertTrue(oppIdx > holdEnd)
        assertTrue("important should run before opportunistic", impIdx < oppIdx)
    }

    @Test
    fun cancelled_queued_waiter_does_not_deadlock_later_requests() = runBlocking {
        val limiter = PriorityRequestLimiter(minIntervalMs = 0)

        val holder = async {
            limiter.withPermit(FetchPriority.Important) {
                delay(120)
            }
        }
        delay(20)
        // Queue a waiter that we cancel while still waiting.
        val cancelled = async {
            limiter.withPermit(FetchPriority.Important) {
                error("cancelled waiter should not run")
            }
        }
        delay(20)
        cancelled.cancelAndJoin()
        holder.await()

        // A later request must still complete (no stuck busy slot).
        var ran = false
        withTimeout(2_000) {
            limiter.withPermit(FetchPriority.Important) {
                ran = true
            }
        }
        assertTrue("later request must acquire after cancelled waiter", ran)
    }

    @Test
    fun multiple_cancellations_still_allow_progress() = runBlocking {
        val limiter = PriorityRequestLimiter(minIntervalMs = 0)
        val holder = async {
            limiter.withPermit(FetchPriority.Important) { delay(100) }
        }
        delay(15)
        val waiters = List(3) {
            async {
                limiter.withPermit(FetchPriority.Important) { /* no-op */ }
            }
        }
        delay(15)
        waiters.forEach { it.cancel() }
        waiters.forEach { runCatching { it.join() } }
        holder.await()

        val counter = AtomicInteger(0)
        withTimeout(2_000) {
            limiter.withPermit(FetchPriority.Important) {
                counter.incrementAndGet()
            }
        }
        assertEquals(1, counter.get())
    }
}
