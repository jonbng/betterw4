package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class W4ClassIdTest {

    @Test
    fun parsesCapturedAcademicCodes() {
        val math = W4ClassId.parse("1DA13HMTAA")!!
        assertEquals(1, math.year)
        assertEquals("D", math.block)
        assertEquals("A13", math.roomCode)
        assertEquals('H', math.level)
        assertEquals("MTAA", math.subjectCode)
        assertEquals("HL", math.levelLabel)

        val econ = W4ClassId.parse("1EA16CECOX")!!
        assertEquals("E", econ.block)
        assertEquals("A16", econ.roomCode)
        assertEquals('C', econ.level)
        assertEquals("ECOX", econ.subjectCode)

        val core = W4ClassId.parse("1ZAUDXCORE")!!
        assertEquals("Z", core.block)
        assertEquals("AUD", core.roomCode)
        assertEquals('X', core.level)
        assertEquals("CORE", core.subjectCode)

        val danish = W4ClassId.parse("2AA24CDALI")!!
        assertEquals(2, danish.year)
        assertEquals("DALI", danish.subjectCode)

        val theatre = W4ClassId.parse("1CMUSCTHEX")!!
        assertEquals("C", theatre.block)
        assertEquals("MUS", theatre.roomCode)
        assertEquals("THEX", theatre.subjectCode)

        val tok = W4ClassId.parse("2DA14XTHOK")!!
        assertEquals('X', tok.level)
        assertEquals("THOK", tok.subjectCode)

        val french = W4ClassId.parse("2YK11SFRAB")!!
        assertEquals("Y", french.block)
        assertEquals("K11", french.roomCode)
        assertEquals("FRAB", french.subjectCode)
    }

    @Test
    fun rejectsAdvisorFirstNamesAndFurniture() {
        assertNull(W4ClassId.parse("Dona"))
        assertNull(W4ClassId.parse("Breakfast"))
        assertNull(W4ClassId.parse("Economics"))
        assertNull(W4ClassId.parse(""))
    }
}
