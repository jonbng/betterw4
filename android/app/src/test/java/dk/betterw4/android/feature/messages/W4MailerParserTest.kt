package dk.betterw4.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Test

class W4MailerParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/mailer-inbox.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_inbox_rows() {
        val threads = W4MailerParser.parseInbox(html, MessageFolder.INBOX.id)
        assertEquals(2, threads.size)
        assertEquals("Welcome to term 1", threads[0].topic)
        assertEquals("House Leader", threads[0].sender)
        assertEquals("12", threads[0].id)
        assertEquals("Kitchen booking", threads[1].topic)
    }

    @Test
    fun empty_grid_is_empty_list() {
        val empty = """
            <div id="content_inner"><div class="grid-view"><table class="items">
            <thead><tr><th>Received</th><th>From</th><th>Subject</th></tr></thead>
            <tbody><tr><td colspan="3" class="empty"><span class="empty">No results found.</span></td></tr></tbody>
            </table></div></div>
        """.trimIndent()
        assertEquals(0, W4MailerParser.parseInbox(empty, MessageFolder.INBOX.id).size)
    }
}
