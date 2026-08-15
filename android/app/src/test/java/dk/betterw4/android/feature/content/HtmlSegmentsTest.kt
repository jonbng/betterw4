package dk.betterw4.android.feature.content

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HtmlSegmentsTest {

    @Test
    fun parse_interleaves_text_and_images() {
        val html = """
            <p>Hello <span class="bb_b">bold</span></p>
            <img src="/lectio/94/GetFile.aspx?documentid=1" alt="Diagram"/>
            <p>After image</p>
        """.trimIndent()
        val segments = HtmlSegments.parse(html)
        assertTrue(segments.any { it is HtmlSegment.Text })
        val images = segments.filterIsInstance<HtmlSegment.Image>()
        assertEquals(1, images.size)
        assertTrue(images[0].url.startsWith("https://w4.uwcrcn.no/"))
        assertEquals("Diagram", images[0].alt)
    }

    @Test
    fun parse_skips_lectio_chrome_icons() {
        val html = """
            <img src="/lectio/img/icon_attachment.gif" alt=""/>
            <img src="/lectio/94/GetImage.aspx?pictureid=9" alt="Photo"/>
        """.trimIndent()
        val images = HtmlSegments.parse(html).filterIsInstance<HtmlSegment.Image>()
        assertEquals(1, images.size)
        assertTrue(images[0].url.contains("GetImage"))
    }

    @Test
    fun parse_strips_message_attachment_blocks() {
        val html = """
            <p>Body</p>
            <div class="message-attachements">
              <a href="/lectio/94/GetFile.aspx?documentid=2">file.pdf</a>
              <img src="/lectio/94/GetFile.aspx?documentid=3" alt="att"/>
            </div>
        """.trimIndent()
        val images = HtmlSegments.parse(html).filterIsInstance<HtmlSegment.Image>()
        assertTrue(images.isEmpty())
        assertTrue(segmentsHasText(html, "Body"))
    }

    @Test
    fun parse_empty_returns_empty() {
        assertTrue(HtmlSegments.parse(null).isEmpty())
        assertTrue(HtmlSegments.parse("   ").isEmpty())
    }

    @Test
    fun extractImageUrls_distinct() {
        val html = """
            <img src="/a.png"/><img src="/a.png"/><img src="/b.png"/>
        """.trimIndent()
        val urls = HtmlSegments.extractImageUrls(html)
        assertEquals(2, urls.size)
    }

    private fun segmentsHasText(html: String, needle: String): Boolean =
        HtmlSegments.parse(html)
            .filterIsInstance<HtmlSegment.Text>()
            .any { it.html.contains(needle, ignoreCase = true) }
}
