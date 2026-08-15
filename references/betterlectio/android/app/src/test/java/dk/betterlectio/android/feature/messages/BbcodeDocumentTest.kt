package dk.betterlectio.android.feature.messages

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BbcodeDocumentTest {

    @Test
    fun plain_round_trip() {
        val src = "Hej verden"
        val ann = BbcodeDocument.bbcodeToAnnotated(src)
        assertEquals(src, ann.text)
        assertEquals(src, BbcodeDocument.annotatedToBbcode(ann))
    }

    @Test
    fun bold_round_trip() {
        val src = "[b]hej[/b]"
        val ann = BbcodeDocument.bbcodeToAnnotated(src)
        assertEquals("hej", ann.text)
        assertTrue(BbcodeDocument.flagsAt(ann, 0).bold)
        assertEquals("[b]hej[/b]", BbcodeDocument.annotatedToBbcode(ann))
    }

    @Test
    fun nested_bold_italic() {
        val src = "[b][i]x[/i][/b]"
        val ann = BbcodeDocument.bbcodeToAnnotated(src)
        assertEquals("x", ann.text)
        val f = BbcodeDocument.flagsAt(ann, 0)
        assertTrue(f.bold)
        assertTrue(f.italic)
        val out = BbcodeDocument.annotatedToBbcode(ann)
        assertTrue(out.contains("[b]"))
        assertTrue(out.contains("[i]"))
        assertTrue(out.contains("x"))
    }

    @Test
    fun link_with_label_round_trip() {
        val src = "[url=https://a.dk]klik[/url]"
        val ann = BbcodeDocument.bbcodeToAnnotated(src)
        assertEquals("klik", ann.text)
        assertEquals("https://a.dk", BbcodeDocument.flagsAt(ann, 0).url)
        val out = BbcodeDocument.annotatedToBbcode(ann)
        assertTrue(out.contains("https://a.dk"))
        assertTrue(out.contains("klik"))
    }

    @Test
    fun bare_url_tag() {
        val src = "[url]https://b.dk[/url]"
        val ann = BbcodeDocument.bbcodeToAnnotated(src)
        assertEquals("https://b.dk", ann.text)
        assertEquals("https://b.dk", BbcodeDocument.flagsAt(ann, 0).url)
    }

    @Test
    fun toggle_bold_on_selection() {
        val tfv = TextFieldValue(
            annotatedString = BbcodeDocument.bbcodeToAnnotated("hello"),
            selection = TextRange(0, 5),
        )
        val toggled = BbcodeDocument.toggleStyle(tfv, BbcodeDocument.StyleKind.Bold)
        assertTrue(BbcodeDocument.flagsAt(toggled.annotatedString, 0).bold)
        assertEquals("[b]hello[/b]", BbcodeDocument.annotatedToBbcode(toggled.annotatedString))
        val off = BbcodeDocument.toggleStyle(toggled, BbcodeDocument.StyleKind.Bold)
        assertFalse(BbcodeDocument.flagsAt(off.annotatedString, 0).bold)
        assertEquals("hello", BbcodeDocument.annotatedToBbcode(off.annotatedString))
    }

    @Test
    fun apply_link_on_selection() {
        val tfv = TextFieldValue(
            annotatedString = BbcodeDocument.bbcodeToAnnotated("here"),
            selection = TextRange(0, 4),
        )
        val linked = BbcodeDocument.applyLink(tfv, "betterlectio.dk")!!
        assertEquals("https://betterlectio.dk", BbcodeDocument.flagsAt(linked.annotatedString, 0).url)
        val out = BbcodeDocument.annotatedToBbcode(linked.annotatedString)
        assertTrue(out.contains("url="))
        assertTrue(out.contains("here"))
    }

    @Test
    fun merge_edit_preserves_prefix_styles() {
        val old = TextFieldValue(
            annotatedString = BbcodeDocument.bbcodeToAnnotated("[b]ab[/b]"),
            selection = TextRange(2, 2),
        )
        // User types "c" at end → "abc" with bold on all if active bold, or left style
        val incoming = TextFieldValue("abc", TextRange(3, 3))
        val merged = BbcodeDocument.mergeEdit(
            old = old,
            new = incoming,
            active = BbcodeDocument.StyleFlags(bold = true),
        )
        assertEquals("abc", merged.text)
        assertTrue(BbcodeDocument.flagsAt(merged.annotatedString, 0).bold)
        assertTrue(BbcodeDocument.flagsAt(merged.annotatedString, 2).bold)
    }

    @Test
    fun empty_identity() {
        assertEquals("", BbcodeDocument.annotatedToBbcode(BbcodeDocument.bbcodeToAnnotated("")))
    }

    @Test
    fun toggle_partial_selection_only_formats_range() {
        val tfv = TextFieldValue(
            annotatedString = BbcodeDocument.bbcodeToAnnotated("abcdef"),
            selection = TextRange(1, 4), // bcd
        )
        val toggled = BbcodeDocument.toggleStyle(tfv, BbcodeDocument.StyleKind.Bold)
        assertFalse(BbcodeDocument.flagsAt(toggled.annotatedString, 0).bold)
        assertTrue(BbcodeDocument.flagsAt(toggled.annotatedString, 1).bold)
        assertTrue(BbcodeDocument.flagsAt(toggled.annotatedString, 3).bold)
        assertFalse(BbcodeDocument.flagsAt(toggled.annotatedString, 4).bold)
        assertEquals("a[b]bcd[/b]ef", BbcodeDocument.annotatedToBbcode(toggled.annotatedString))
    }

    @Test
    fun collapsed_selection_toggle_is_noop_on_text() {
        val tfv = TextFieldValue(
            annotatedString = BbcodeDocument.bbcodeToAnnotated("hi"),
            selection = TextRange(1, 1),
        )
        val toggled = BbcodeDocument.toggleStyle(tfv, BbcodeDocument.StyleKind.Bold)
        assertEquals("hi", toggled.text)
        assertEquals("hi", BbcodeDocument.annotatedToBbcode(toggled.annotatedString))
    }
}
