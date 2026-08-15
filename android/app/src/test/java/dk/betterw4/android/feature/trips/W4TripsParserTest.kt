package dk.betterw4.android.feature.trips

import org.junit.Assert.assertEquals
import org.junit.Test

class W4TripsParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/trips.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_trip_row() {
        val trips = W4TripsParser.parse(html)
        assertEquals(1, trips.size)
        assertEquals("Bergen weekend", trips[0].name)
        assertEquals("Planning", trips[0].status)
        assertEquals("Bergen", trips[0].destination)
    }
}
