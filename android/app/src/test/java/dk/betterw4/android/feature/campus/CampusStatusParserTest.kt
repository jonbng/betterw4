package dk.betterw4.android.feature.campus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        assertFalse(status.onCampus)
        assertEquals("At Raudbua", status.location)
        assertTrue(status.options.contains("On a walk"))
        assertEquals("At Raudbua", status.label)
    }
}
