package dk.betterw4.android.core.w4

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

class W4DatesTest {

    @Test
    fun formats_en_gb_dd_mmm_yyyy() {
        assertEquals("14-Aug-2026", W4Dates.format(LocalDate.of(2026, 8, 14)))
    }

    @Test
    fun parses_captured_datepicker_shapes() {
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("14-Aug-2026"))
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("14-Aug-26"))
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("2026-08-14"))
        assertEquals(LocalDate.of(2026, 8, 14), W4Dates.parse("14/8/2026"))
        assertNull(W4Dates.parse(""))
    }
}
