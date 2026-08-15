package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** sanitizeUrl still used by rich editor + link dialog. */
class BbcodeEditTest {

    @Test
    fun sanitizeUrl_prepends_https() {
        assertEquals("https://example.com", BbcodeEdit.sanitizeUrl("example.com"))
        assertEquals("https://ok.dk", BbcodeEdit.sanitizeUrl("https://ok.dk"))
        assertEquals("mailto:a@b.dk", BbcodeEdit.sanitizeUrl("mailto:a@b.dk"))
    }

    @Test
    fun sanitizeUrl_empty() {
        assertEquals("", BbcodeEdit.sanitizeUrl("   "))
    }

    @Test
    fun wrap_selection_still_available_for_legacy() {
        // Keep wrap helpers working for any non-UI callers
        val r = BbcodeEdit.bold("hello world", 0, 5)
        assertEquals("[b]hello[/b] world", r.text)
    }

    @Test
    fun insertLink_blank_url_returns_null() {
        assertNull(BbcodeEdit.insertLink("x", 0, 1, "   "))
    }
}
