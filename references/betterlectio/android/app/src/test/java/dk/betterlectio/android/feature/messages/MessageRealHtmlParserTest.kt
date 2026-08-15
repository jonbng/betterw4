package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageRealHtmlParserTest {
    @Test
    fun parses_real_lectio_list_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/beskeder2_real_list.html")!!
            .bufferedReader().readText()
        val threads = MessageParser.parseThreadList(html, "-70")
        println("threads=${threads.size}")
        threads.forEach { println("  id=${it.id} norm=${it.normalizedId} topic=${it.topic} unread=${it.unread}") }
        assertTrue("expected threads from real HTML, got ${threads.size}", threads.size >= 3)
        assertTrue(threads.all { it.normalizedId.matches(Regex("\\d+")) })
        // Latest sender should use full title, not initials-only "MPS"
        assertTrue(
            "sender should be full title, was: ${threads[0].sender}",
            threads[0].sender.contains("Mikkel", ignoreCase = true) ||
                threads[0].sender.length > 4,
        )
        assertEquals("TEACHER", threads[0].senderKind)
        // open arg must match lectio
        val open = MessageRepository.openThreadEventArgument(threads[0])
        println("openArg=$open sender=${threads[0].sender} kind=${threads[0].senderKind}")
        assertTrue(open.contains("MC_\$_") || open.contains("LB2"))
        assertEquals(
            MessagePostbackFields.openThreadArg(threads[0].normalizedId).let {
                if (threads[0].id.contains("LB2")) threads[0].id else it
            },
            open,
        )
    }

    @Test
    fun smartPostback_includes_viewstate_from_real_html() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/beskeder2_real_list.html")!!
            .bufferedReader().readText()
        val resolved = dk.betterlectio.android.core.lectio.scrape.SmartPostback.resolve(
            html = html,
            preferredTargets = listOf("__Page"),
            extra = mapOf(
                "__EVENTARGUMENT" to "",
                MessagePostbackFields.FOLDERS_FIELD to "-70",
            ),
        )
        val vs = resolved.fields["__VIEWSTATEX"].orEmpty()
        println("VIEWSTATEX len=${vs.length} fieldCount=${resolved.fields.size}")
        assertTrue("VIEWSTATEX must be present", vs.length > 100)
        assertEquals("__Page", resolved.fields["__EVENTTARGET"])
        assertEquals("-70", resolved.fields[MessagePostbackFields.FOLDERS_FIELD])
    }

    @Test
    fun parse_thread_detail_from_real_thread_fixture() {
        val stream = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/beskeder2_real_thread.html")
        if (stream == null) {
            println("skip no thread fixture")
            return
        }
        val html = stream.bufferedReader().readText()
        val ref = MessageThread(
            id = "\$LB2\$_MC_\$_1",
            topic = "t",
            sender = "s",
            dateChanged = null,
            folderId = "-70",
            normalizedId = "1",
        )
        val detail = MessageParser.parseThreadDetail(html, ref)
        println("entries=${detail.entries.size} receivers=${detail.receivers}")
        assertTrue(detail.entries.isNotEmpty())
    }
}
