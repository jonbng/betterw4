package dk.betterw4.android.feature.campus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CampusStatusParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/campus-chrome.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_off_campus_location_and_options() {
        val status = CampusStatusParser.parse(html)
        assertNotNull(status)
        assertFalse(status!!.onCampus)
        assertEquals("At Raudbua", status.location)
        assertTrue(status.options.any { it.label == "On a walk" && it.value == "On a walk" })
        assertTrue(status.options.any { it.isOnCampus })
        assertTrue(status.options.any { it.isFreeText })
        assertEquals("At Raudbua", status.label)
    }

    @Test
    fun on_campus_posts_status_on_with_no_location() {
        val option = CampusLocationOption.defaults.first { it.isOnCampus }
        val body = CampusStatusParser.setStatusBody(option)
        assertEquals(mapOf("status" to "on"), body)
    }

    @Test
    fun other_posts_free_text_capped_at_twenty() {
        val option = CampusLocationOption.defaults.first { it.isFreeText }
        val body = CampusStatusParser.setStatusBody(option, "x".repeat(30))
        assertEquals("off", body!!["status"])
        assertEquals("x".repeat(20), body["location"])
    }

    @Test
    fun other_with_empty_text_is_refused() {
        val option = CampusLocationOption.defaults.first { it.isFreeText }
        assertNull(CampusStatusParser.setStatusBody(option, "   "))
    }

    @Test
    fun wrapping_parentheses_are_stripped() {
        assertEquals("At Raudbua", CampusStatusParser.normalizedLocation("(At Raudbua)"))
    }
}
