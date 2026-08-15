package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageAttachmentParserTest {
    @Test
    fun parses_attachment_href_and_name_from_html() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/message_with_attachment.html")!!
            .bufferedReader().readText()
        val attachments = MessageParser.parseAttachmentsFromHtml(html)
        assertEquals(1, attachments.size)
        assertEquals("Skema.pdf", attachments[0].name)
        assertTrue(attachments[0].url.contains("GetFile") || attachments[0].url.contains("documentid"))
    }
}
