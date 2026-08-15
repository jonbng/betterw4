package dk.betterlectio.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivateEventResponseTest {

    @Test
    fun isAccepted_false_when_form_rerendered_with_validation_error() {
        val html = """
            <html><body>
            <input id="m_Content_titelTextBox_tb" name="m${'$'}Content${'$'}titelTextBox${'$'}tb" value=""/>
            <span class="field-validation-error">Titel er påkrævet</span>
            </body></html>
        """.trimIndent()
        assertFalse(PrivateEventResponse.isAccepted(html))
    }

    @Test
    fun isAccepted_true_when_redirected_away_from_form() {
        val html = """
            <html><body>
            <div id="s_m_Content_Content_skemaWrapper">Skema</div>
            </body></html>
        """.trimIndent()
        assertTrue(PrivateEventResponse.isAccepted(html))
    }

    @Test
    fun isAccepted_true_when_still_on_form_without_error() {
        val html = """
            <html><body>
            <input id="m_Content_titelTextBox_tb" name="m${'$'}Content${'$'}titelTextBox${'$'}tb" value="Møde"/>
            </body></html>
        """.trimIndent()
        assertTrue(PrivateEventResponse.isAccepted(html))
    }

    @Test
    fun fieldOverrides_maps_all_draft_fields() {
        val map = PrivateEventResponse.fieldOverrides(
            title = "Læge",
            startDate = "10/03-2026",
            startTime = "09:00",
            endDate = "10/03-2026",
            endTime = "10:00",
            note = "Checkup",
        )
        assertEquals("Læge", map["m\$Content\$titelTextBox\$tb"])
        assertEquals("10/03-2026", map["m\$Content\$startdateCtrl\$_date\$tb"])
        assertEquals("09:00", map["m\$Content\$startdateCtrl\$startdateCtrl_time\$tb"])
        assertEquals("10/03-2026", map["m\$Content\$enddateCtrl\$_date\$tb"])
        assertEquals("10:00", map["m\$Content\$enddateCtrl\$enddateCtrl_time\$tb"])
        assertEquals("Checkup", map["m\$Content\$commentTextBox\$tb"])
    }
}
