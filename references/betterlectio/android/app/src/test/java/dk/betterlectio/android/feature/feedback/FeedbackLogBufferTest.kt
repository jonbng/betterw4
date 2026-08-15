package dk.betterlectio.android.feature.feedback

import android.util.Log
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class FeedbackLogBufferTest {

    private lateinit var buffer: FeedbackLogBuffer

    @Before
    fun setUp() {
        buffer = FeedbackLogBuffer()
        buffer.setCapacity(5)
    }

    @Test
    fun ringsAtCapacity() {
        repeat(8) { i ->
            buffer.record(Log.INFO, "T", "line-$i")
        }
        assertEquals(5, buffer.size())
        val snap = buffer.snapshot()
        assertFalse(snap.contains("line-0"))
        assertFalse(snap.contains("line-1"))
        assertFalse(snap.contains("line-2"))
        assertTrue(snap.contains("line-3"))
        assertTrue(snap.contains("line-7"))
    }

    @Test
    fun snapshotTruncatesWhenTooLong() {
        buffer.setCapacity(50)
        // Force long lines past MAX_SNAPSHOT_CHARS with many long entries.
        val longMsg = "x".repeat(FeedbackLogBuffer.MAX_LINE_CHARS)
        repeat(30) {
            buffer.record(Log.DEBUG, "Tag", longMsg)
        }
        val snap = buffer.snapshot(maxChars = 2_000)
        assertTrue(snap.length <= 2_000 + "…[older logs truncated]\n".length)
        assertTrue(snap.startsWith("…[older logs truncated]"))
    }

    @Test
    fun includesThrowableSnippet() {
        buffer.record(Log.ERROR, "Err", "boom", RuntimeException("nope"))
        val snap = buffer.snapshot()
        assertTrue(snap.contains("boom"))
        assertTrue(snap.contains("RuntimeException") || snap.contains("nope"))
    }

    @Test
    fun clearEmpties() {
        buffer.record(Log.INFO, "T", "hi")
        assertEquals(1, buffer.size())
        buffer.clear()
        assertEquals(0, buffer.size())
        assertEquals("", buffer.snapshot())
    }
}
