package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageParserTest {
    @Test
    fun parses_thread_list_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/messages_list.html")!!
            .bufferedReader().readText()
        val threads = MessageParser.parseThreadList(html)
        assertEquals(1, threads.size)
        assertEquals("Velkomst", threads[0].topic)
        assertTrue(threads[0].id.isNotBlank())
        assertEquals("-70", threads[0].folderId)
        // Prefer numeric id (iOS/extension); fixtures with `$ABC_$_42` still normalize to 42.
        assertEquals("42", threads[0].normalizedId)
        assertTrue(
            threads[0].id == "42" || threads[0].id.contains("$") || threads[0].id.contains("42"),
        )
    }

    @Test
    fun normalizeThreadId_flutter_parity() {
        assertEquals("42", MessageParser.normalizeThreadId("\$ABC_\$_42"))
        assertEquals("42", MessageParser.normalizeThreadId("\$ABC_\$_42"))
        assertEquals("plain", MessageParser.normalizeThreadId("plain"))
        // Offline store re-derives from full threadId the same way.
        assertEquals("99", MessageParser.normalizeThreadId("\$X_\$_99"))
    }

    @Test
    fun parseMessageTimestamp_strips_sender_name() {
        val ts = MessageParser.parseMessageTimestamp(
            "Anders Andersen (3.a), 04-03-2026 11:05:41",
            "Anders Andersen (3.a)",
        )
        assertEquals(2026, ts!!.year)
        assertEquals(3, ts.monthValue)
        assertEquals(4, ts.dayOfMonth)
        assertEquals(11, ts.hour)
    }
}

