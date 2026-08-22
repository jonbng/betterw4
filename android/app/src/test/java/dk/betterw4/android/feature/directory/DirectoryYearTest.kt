package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DirectoryYearTest {
    @Test
    fun parses_w4_year_labels() {
        assertEquals("1", DirectoryYear.parse("1st year"))
        assertEquals("1", DirectoryYear.parse("Denmark 1st year"))
        assertEquals("2", DirectoryYear.parse("2nd year"))
        assertEquals("2", DirectoryYear.parse("Year 2 · Fjaera"))
        assertEquals("1", DirectoryYear.parse("1"))
        assertEquals("1", DirectoryYear.parse("First year"))
        assertEquals("2", DirectoryYear.parse("Second year"))
        assertNull(DirectoryYear.parse("Haugland"))
        assertNull(DirectoryYear.parse(null))
    }
}
