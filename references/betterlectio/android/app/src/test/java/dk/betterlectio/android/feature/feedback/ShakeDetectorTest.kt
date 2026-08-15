package dk.betterlectio.android.feature.feedback

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure constants / gesture-tracker checks — sensor events need instrumentation.
 */
class ShakeDetectorTest {

    @Test
    fun defaultsAreSensible() {
        assertTrue(ShakeDetector.DEFAULT_THRESHOLD > 1_200f)
        assertTrue(ShakeDetector.DEFAULT_THRESHOLD < 5_000f)
        assertTrue(ShakeDetector.DEFAULT_REQUIRED_PEAKS >= 2)
        assertTrue(ShakeDetector.DEFAULT_WINDOW_MS in 500L..2_000L)
        assertTrue(ShakeDetector.DEFAULT_COOLDOWN_MS in 1_000L..10_000L)
    }

    @Test
    fun singlePeakDoesNotTrigger() {
        val tracker = ShakeGestureTracker()
        assertFalse(tracker.onSpeed(1_000L, 3_000f))
    }

    @Test
    fun belowThresholdNeverCounts() {
        val tracker = ShakeGestureTracker()
        repeat(10) { i ->
            assertFalse(tracker.onSpeed(1_000L + i * 100L, 500f))
        }
    }

    @Test
    fun threeHardPeaksWithinWindowTriggers() {
        val tracker = ShakeGestureTracker()
        assertFalse(tracker.onSpeed(1_000L, 3_000f))
        assertFalse(tracker.onSpeed(1_200L, 3_000f))
        assertTrue(tracker.onSpeed(1_400L, 3_000f))
    }

    @Test
    fun peaksSpreadPastWindowDoNotTrigger() {
        val tracker = ShakeGestureTracker()
        assertFalse(tracker.onSpeed(1_000L, 3_000f))
        assertFalse(tracker.onSpeed(1_200L, 3_000f))
        // Gap > window → counter resets; still short of 3 after these:
        assertFalse(tracker.onSpeed(2_800L, 3_000f))
        assertFalse(tracker.onSpeed(3_000L, 3_000f))
    }

    @Test
    fun peaksTooCloseAreDedupedAndNeedThreeDistinct() {
        val tracker = ShakeGestureTracker()
        assertFalse(tracker.onSpeed(1_000L, 3_000f)) // 1
        assertFalse(tracker.onSpeed(1_040L, 3_000f)) // deduped
        assertFalse(tracker.onSpeed(1_200L, 3_000f)) // 2
        assertTrue(tracker.onSpeed(1_400L, 3_000f)) // 3
    }

    @Test
    fun cooldownBlocksImmediateRetrigger() {
        val tracker = ShakeGestureTracker()
        assertFalse(tracker.onSpeed(1_000L, 3_000f))
        assertFalse(tracker.onSpeed(1_200L, 3_000f))
        assertTrue(tracker.onSpeed(1_400L, 3_000f))

        // Immediate new window during cooldown
        assertFalse(tracker.onSpeed(1_600L, 3_000f))
        assertFalse(tracker.onSpeed(1_800L, 3_000f))
        assertFalse(tracker.onSpeed(2_000L, 3_000f))
    }
}
