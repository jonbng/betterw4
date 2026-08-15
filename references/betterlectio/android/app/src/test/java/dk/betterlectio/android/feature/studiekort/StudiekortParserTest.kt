package dk.betterlectio.android.feature.studiekort

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StudiekortParserTest {
    @Test
    fun parse_extracts_photo_and_qr_from_fixture_html() {
        val html = """
            <html><body>
            <h1 id="s_m_HeaderContent_MainTitle">Demo Elev - 3.x</h1>
            <div class="ls-master-header-institutionname">Demo Gymnasium</div>
            <img src="/lectio/517/GetImage.aspx?pictureid=99887&fullsize=1" alt="foto"/>
            <img src="/lectio/517/GetImage.aspx?type=studiekortqr&studentid=12345" alt="qr"/>
            </body></html>
        """.trimIndent()
        val parsed = StudiekortParser.parse(html, gymId = 517, studentId = "12345")
        assertEquals("Demo Elev - 3.x", parsed.name)
        assertEquals("3.x", parsed.classLabel)
        assertNotNull(parsed.photoUrl)
        assertTrue(parsed.photoUrl!!.contains("pictureid=99887"))
        assertTrue(parsed.photoUrl!!.contains("fullsize=1"))
        assertNotNull(parsed.qrUrl)
        assertTrue(parsed.qrUrl!!.contains("studiekortqr"))
        assertEquals("99887", parsed.pictureId)
    }

    @Test
    fun parse_upgrades_thumbnail_photo_to_fullsize() {
        val html = """
            <html><body>
            <img id="s_m_Content_Content_StudPic"
                 src="/lectio/517/GetImage.aspx?pictureid=99887" alt="foto"/>
            </body></html>
        """.trimIndent()
        val parsed = StudiekortParser.parse(html, gymId = 517, studentId = "12345")
        assertEquals("99887", parsed.pictureId)
        assertEquals(
            "https://www.lectio.dk/lectio/517/GetImage.aspx?pictureid=99887&fullsize=1",
            parsed.photoUrl,
        )
    }

    @Test
    fun parse_constructs_qr_fallback_when_missing() {
        val html = "<html><body><h1>Elev</h1></body></html>"
        val parsed = StudiekortParser.parse(html, 94, "999")
        assertNotNull(parsed.qrUrl)
        assertTrue(parsed.qrUrl!!.contains("studentid=999"))
        assertTrue(parsed.qrUrl!!.contains("studiekortqr"))
    }

    @Test
    fun parseBirthday_extracts_from_lectio_span() {
        val html = """
            <html><body>
            <span id="s_m_Content_Content_StudentBirthday">Fødselsdag: 15. marts 2007</span>
            </body></html>
        """.trimIndent()
        assertEquals("15. marts 2007", StudiekortParser.parseBirthday(html))
        val full = StudiekortParser.parse(html, 517, "1")
        assertEquals("15. marts 2007", full.birthday)
    }

    @Test
    fun parseBirthday_returns_null_when_absent() {
        assertEquals(null, StudiekortParser.parseBirthday("<html><body>nope</body></html>"))
    }
}
