package dk.betterlectio.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class HomeworkDetailLoaderTest {
    @Test
    fun mergeDetail_sets_html() {
        val item = HomeworkItem("h1", "note", "Ma", LocalDate.now(), "Ma A")
        val merged = HomeworkDetailLoader.mergeDetail(item, "<p>Hello</p>")
        assertEquals("<p>Hello</p>", merged.detailHtml)
    }

    @Test
    fun plainTextFromHtml_strips_tags() {
        val text = HomeworkDetailLoader.plainTextFromHtml("<p>Hello <b>world</b></p><br/>X")
        assertTrue(text.contains("Hello"))
        assertTrue(text.contains("world"))
        assertFalse(text.contains("<b>"))
    }

    @Test
    fun hasLinkedContent_detects_href_or_html() {
        val bare = HomeworkItem("1", "n", "t", null)
        assertFalse(HomeworkDetailLoader.hasLinkedContent(bare))
        assertTrue(HomeworkDetailLoader.hasLinkedContent(bare.copy(href = "x.aspx")))
        assertTrue(HomeworkDetailLoader.hasLinkedContent(bare.copy(detailHtml = "<p>x</p>")))
    }
}
