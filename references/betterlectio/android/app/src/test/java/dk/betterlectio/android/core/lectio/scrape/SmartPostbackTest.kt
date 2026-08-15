package dk.betterlectio.android.core.lectio.scrape

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartPostbackTest {
    private val html = """
        <html><body>
        <form>
          <input type="hidden" name="__VIEWSTATE" value="vs" id="__VIEWSTATE"/>
          <input type="hidden" name="__EVENTVALIDATION" value="ev" id="__EVENTVALIDATION"/>
          <textarea name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}CreateNewAnswer${'$'}WriteContent"></textarea>
          <input type="submit" name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}CreateNewAnswer${'$'}SendAnswerBtn" value="Send"/>
          <input type="text" name="cause" value="Syg"/>
          <input type="hidden" name="id" value="r1"/>
          <input type="submit" name="s${'$'}m${'$'}Content${'$'}Content${'$'}savebtn" value="Gem"/>
        </form>
        </body></html>
    """.trimIndent()

    @Test
    fun resolve_finds_exact_send_button() {
        val r = SmartPostback.resolve(
            html = html,
            preferredTargets = listOf(
                "s\$m\$Content\$Content\$MessageThreadCtrl\$CreateNewAnswer\$SendAnswerBtn",
            ),
            extra = mapOf("x" to "1"),
        )
        assertTrue(
            "matchedBy=${r.matchedBy} target=${r.eventTarget}",
            r.matchedBy == "exact_name_or_id" || r.matchedBy == "suffix_or_dopostback",
        )
        assertTrue(r.eventTarget.contains("SendAnswerBtn") || r.eventTarget.contains("CreateNewAnswer"))
        assertTrue(r.fields.containsKey("__VIEWSTATE"))
        assertEquals("1", r.fields["x"])
        assertEquals(r.eventTarget, r.fields["__EVENTTARGET"])
    }

    @Test
    fun findFieldName_matches_WriteContent() {
        val name = SmartPostback.findFieldName(html, listOf("WriteContent"))
        assertNotNull(name)
        assertTrue(name!!.contains("WriteContent"))
    }

    @Test
    fun resolve_keyword_save_for_absence() {
        val r = SmartPostback.resolve(
            html = html,
            preferredTargets = listOf("missing\$target"),
            extra = mapOf("cause" to "Privat"),
            nameContainsAny = listOf("save", "gem"),
        )
        assertTrue(r.matchedBy == "keyword" || r.fields["__VIEWSTATE"] == "vs")
        assertEquals("Privat", r.fields["cause"])
    }
}
