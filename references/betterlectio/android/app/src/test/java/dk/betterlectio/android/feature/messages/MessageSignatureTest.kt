package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageSignatureTest {

    @Test
    fun skip_when_disable_setting() {
        assertTrue(MessageSignature.shouldSkipSignature(listOf("S123"), disableSignature = true))
    }

    @Test
    fun skip_when_teacher_recipient() {
        assertTrue(MessageSignature.shouldSkipSignature(listOf("T456"), disableSignature = false))
        assertTrue(MessageSignature.shouldSkipSignature(listOf("S1", "T2"), disableSignature = false))
    }

    @Test
    fun keep_for_students_only() {
        assertFalse(MessageSignature.shouldSkipSignature(listOf("S123", "S456"), disableSignature = false))
    }

    @Test
    fun append_adds_bbcode() {
        val out = MessageSignature.appendIfNeeded("Hej", listOf("S1"), disableSignature = false)
        assertTrue(out.startsWith("Hej"))
        assertTrue(out.contains("Sendt med BetterLectio"))
        assertTrue(out.contains("betterlectio.dk/download"))
    }

    @Test
    fun append_skips_for_teacher() {
        assertEquals(
            "Hej",
            MessageSignature.appendIfNeeded("Hej", listOf("T9"), disableSignature = false),
        )
    }

    @Test
    fun append_idempotent() {
        val once = MessageSignature.appendIfNeeded("x", listOf("S1"), false)
        val twice = MessageSignature.appendIfNeeded(once, listOf("S1"), false)
        assertEquals(once, twice)
    }
}
