package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageSearchTest {

    private fun thread(id: String, topic: String, sender: String) = MessageThread(
        id = id,
        topic = topic,
        sender = sender,
        dateChanged = null,
        folderId = MessageFolder.NEWEST.id,
    )

    private val threads = listOf(
        thread("1", "Lektier i matematik", "Anders Jensen"),
        thread("2", "Skolefest", "Elevråd"),
        thread("3", "Fravær", "anders jensen"),
    )

    @Test
    fun emptyQuery_returnsAll() {
        assertEquals(3, MessageSearch.filter(threads, "").size)
        assertEquals(3, MessageSearch.filter(threads, "   ").size)
    }

    @Test
    fun matchesSenderCaseInsensitive() {
        val result = MessageSearch.filter(threads, "ANDERS")
        assertEquals(2, result.size)
        assertTrue(result.all { it.sender.contains("anders", ignoreCase = true) })
    }

    @Test
    fun matchesTopic() {
        val result = MessageSearch.filter(threads, "matematik")
        assertEquals(1, result.size)
        assertEquals("1", result.single().id)
    }

    @Test
    fun noMatch_returnsEmpty() {
        assertTrue(MessageSearch.filter(threads, "xyz-not-found").isEmpty())
    }
}
