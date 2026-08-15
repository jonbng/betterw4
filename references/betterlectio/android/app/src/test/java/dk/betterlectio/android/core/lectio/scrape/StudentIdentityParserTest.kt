package dk.betterlectio.android.core.lectio.scrape

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StudentIdentityParserTest {

    @Test
    fun parses_student_header_fixture_flutter_meta() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/student_header.html")!!
            .bufferedReader()
            .readText()

        val identity = StudentIdentityParser.parse(html)
        assertEquals("72721770937", identity.studentId)
        assertEquals("Elliott Friedrich", identity.name)
        assertEquals("74096219865", identity.pictureId)
    }

    @Test
    fun parses_ios_style_elevid_links_without_meta() {
        // iOS StudentParser.parseStudentInfo: first a[href*=elevid]
        val html = """
            <html><body>
              <div id="s_m_HeaderContent_MainTitle">Eleven Ada Lovelace, 2a - Skema</div>
              <a href="/lectio/94/forside.aspx?elevid=99887766554">Forside</a>
              <a href="/lectio/94/SkemaNy.aspx?elevid=99887766554">Skema</a>
            </body></html>
        """.trimIndent()

        val identity = StudentIdentityParser.parse(html)
        assertEquals("99887766554", identity.studentId)
        assertEquals("Ada Lovelace", identity.name)
        assertNull(identity.teacherId)
    }

    @Test
    fun parses_laererid_from_meta() {
        val html = """
            <html><head>
              <meta name="msapplication-starturl" content="/lectio/94/forside.aspx?laererid=112233" />
            </head><body>
              <div id="s_m_HeaderContent_MainTitle">Lærer Bob Builder, matematik</div>
            </body></html>
        """.trimIndent()

        val identity = StudentIdentityParser.parse(html)
        assertEquals("112233", identity.teacherId)
        assertEquals("112233", identity.personId)
        assertNull(identity.studentId)
    }

    @Test
    fun parses_elevid_regex_fallback_in_script() {
        val html = """
            <html><body>
              <script>var currentElev = "elevid=44556677889";</script>
            </body></html>
        """.trimIndent()

        val identity = StudentIdentityParser.parse(html)
        assertEquals("44556677889", identity.studentId)
    }

    @Test
    fun parses_first_student_context_card_when_no_elevid_links_exist() {
        val html = """
            <html><body>
              <span data-lectioContextCard="S12345678901">Ada Lovelace</span>
              <span data-lectioContextCard="T222">Teacher</span>
              <span data-lectioContextCard="HE333">Math A</span>
            </body></html>
        """.trimIndent()

        val identity = StudentIdentityParser.parse(html)
        assertEquals("12345678901", identity.studentId)
        assertNull(identity.teacherId)
    }

    @Test
    fun empty_html_returns_null_ids() {
        val identity = StudentIdentityParser.parse("<html><body>login form</body></html>")
        assertNull(identity.personId)
    }
}
