package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageNoReplyFieldsTest {

    @Test
    fun findNoReply_from_name_attribute() {
        val html = """
            <input type="checkbox" name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}RepliesNotAllowedChkBox"
                   id="s_m_Content_Content_MessageThreadCtrl_RepliesNotAllowedChkBox" />
        """.trimIndent()
        assertEquals(
            "s\$m\$Content\$Content\$MessageThreadCtrl\$RepliesNotAllowedChkBox",
            MessagePostbackFields.findNoReplyCheckboxName(html),
        )
    }

    @Test
    fun findAttachTargets_from_name() {
        val html = """
            <input type="hidden"
              name="s${'$'}m${'$'}Content${'$'}Content${'$'}MessageThreadCtrl${'$'}MessagesGV${'$'}ctl02${'$'}AttachmentDocChooser${'$'}selectedDocumentId"
              id="s_m_Content_Content_MessageThreadCtrl_MessagesGV_ctl02_AttachmentDocChooser_selectedDocumentId" />
        """.trimIndent()
        val t = MessagePostbackFields.findAttachTargets(html)!!
        assertTrue(t.docIdFieldName.endsWith("selectedDocumentId"))
        assertTrue(t.postbackTarget.endsWith("AttachmentDocChooser"))
        assertFalse(t.postbackTarget.contains("selectedDocumentId"))
    }

    @Test
    fun withNoReply_only_when_checked() {
        val base = mapOf("a" to "1")
        assertEquals(base, MessagePostbackFields.withNoReply(base, false, "chk"))
        val on = MessagePostbackFields.withNoReply(base, true, "chk")
        assertEquals("on", on["chk"])
        assertEquals("1", on["a"])
    }
}
