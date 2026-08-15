package dk.betterlectio.android.core.lectio.scrape

import org.junit.Assert.assertEquals
import org.junit.Test

class AspNetFormTest {

    @Test
    fun extractAspData_from_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/asp_form.html")!!
            .bufferedReader()
            .readText()

        val data = AspNetForm.extractAspData(html, "m\$Content\$submitbtn2")
        assertEquals("m\$Content\$submitbtn2", data["__EVENTTARGET"])
        assertEquals("VIEWSTATE_VALUE", data["__VIEWSTATE"])
        assertEquals("VIEWSTATEX_VALUE", data["__VIEWSTATEX"])
        assertEquals("EVENTVAL_VALUE", data["__EVENTVALIDATION"])
        assertEquals("FOOTER", data["masterfootervalue"])
    }

    @Test
    fun queriesFromUrl_parses_params() {
        val q = AspNetForm.queriesFromUrl("/lectio/94/forside.aspx?elevid=123&x=1")
        assertEquals("123", q["elevid"])
        assertEquals("1", q["x"])
    }
}
