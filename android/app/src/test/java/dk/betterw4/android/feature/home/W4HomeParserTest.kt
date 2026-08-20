package dk.betterw4.android.feature.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class W4HomeParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/home.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun captured_greeting_and_uwc_id_come_from_hello() {
        val page = W4HomeParser.parse(html)
        assertEquals("Hello Alex Andersen", page.greetingText)
        assertEquals("Alex Andersen", page.greetingName)
        assertEquals("nc26abcd", page.uwcId)
        assertFalse(page.isEmpty)
    }

    @Test
    fun captured_announcements_are_empty_and_links_are_present() {
        val page = W4HomeParser.parse(html)
        assertTrue(page.announcements.isEmpty())
        assertTrue(page.announcementsEmptyText!!.startsWith("No announcements"))
        assertEquals(10, page.links.size)
        assertEquals("25.9.1", page.serverVersion)
    }
}
