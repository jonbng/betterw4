package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RateLimitedAvatarLoaderTest {
    @Test
    fun acquire_respects_max_concurrent() {
        val clock = longArrayOf(1000L)
        val loader = RateLimitedAvatarLoader(maxConcurrent = 2, minIntervalMs = 0, clock = { clock[0] })
        assertTrue(loader.acquire())
        clock[0] += 1
        assertTrue(loader.acquire())
        clock[0] += 1
        assertFalse(loader.acquire())
        loader.release()
        clock[0] += 1
        assertTrue(loader.acquire())
        assertEquals(2, loader.inFlightCount())
    }

    @Test
    fun acquire_respects_min_interval() {
        val clock = longArrayOf(0L)
        val loader = RateLimitedAvatarLoader(maxConcurrent = 4, minIntervalMs = 100, clock = { clock[0] })
        assertTrue(loader.acquire())
        clock[0] = 50
        assertFalse(loader.acquire())
        clock[0] = 120
        assertTrue(loader.acquire())
    }

    @Test
    fun remember_and_cachedUrl() {
        val loader = RateLimitedAvatarLoader()
        loader.remember("S1", "https://example.com/a.png")
        assertEquals("https://example.com/a.png", loader.cachedUrl("S1"))
    }
}
