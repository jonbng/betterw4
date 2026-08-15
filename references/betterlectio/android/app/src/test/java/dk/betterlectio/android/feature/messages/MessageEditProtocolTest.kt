package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MessageEditProtocolTest {
    @Test
    fun `edit fields stay scoped to the selected dynamic row`() {
        val prefix = "s_m_Content_Content_MessageThreadCtrl_ThreadGrid_ctl17"
        val other = "s_m_Content_Content_MessageThreadCtrl_ThreadGrid_ctl04"
        val d = '$'
        val html = """
            <form>
              <tr>
                <td><input name="$other${d}EditModeHeaderTitleTB${d}tb" value="Wrong" /></td>
                <td><textarea name="$other${d}EditModeContentBBTB${d}TbxNAME${d}tb">wrong</textarea></td>
                <td><a href="javascript:__doPostBack('$other${d}SaveMessageBtn','')">Save</a></td>
              </tr>
              <tr>
                <td><input name="$prefix${d}EditModeHeaderTitleTB${d}tb" value="Right &amp; exact" /></td>
                <td><textarea name="$prefix${d}EditModeContentBBTB${d}TbxNAME${d}tb">first line
second line</textarea></td>
                <td><a onclick="__doPostBack('$prefix${d}UpdateMessageBtn','')">Save</a></td>
              </tr>
            </form>
        """.trimIndent()

        val fields = MessageEditProtocol.parseFields(html, "$prefix\$EditModeToggleBtn")!!

        assertEquals("$prefix\$EditModeHeaderTitleTB\$tb", fields.titleField)
        assertEquals("$prefix\$EditModeContentBBTB\$TbxNAME\$tb", fields.bodyField)
        assertEquals("$prefix\$UpdateMessageBtn", fields.saveTarget)
        assertEquals("Right & exact", fields.title)
        assertEquals("first line\nsecond line", fields.body)
    }

    @Test
    fun `unrelated edit target cannot borrow another row fields`() {
        val html = """
            <tr><td><textarea name="row1${'$'}EditModeContentBBTB${'$'}TbxNAME${'$'}tb">body</textarea>
            <input name="row1${'$'}EditModeHeaderTitleTB${'$'}tb" value="title" />
            <a href="javascript:__doPostBack('row1${'$'}SaveMessageBtn','')">Save</a></td></tr>
        """.trimIndent()

        assertNull(MessageEditProtocol.parseFields(html, "row2\$EditModeToggleBtn"))
    }

    @Test
    fun `generated signature is removed and preserved byte for byte`() {
        val signature = "\n\n[url=https://betterlectio.dk/download]Sendt med BetterLectio[/url]"

        assertEquals("Hej\nigen" to signature, MessageEditProtocol.splitSignature("Hej\nigen$signature"))
        assertEquals("Hej\nigen" to "", MessageEditProtocol.splitSignature("Hej\nigen"))
    }

    @Test
    fun `uses the form action returned with each fresh viewstate`() {
        val action = "/lectio/94/beskeder2.aspx?mappeid=-70&amp;phase=edit"
        val html = "<form action=\"$action\"><input name=\"__VIEWSTATEX\" value=\"fresh\"></form>"

        assertEquals(
            "/lectio/94/beskeder2.aspx?mappeid=-70&phase=edit",
            MessageEditProtocol.formAction(html, "beskeder2.aspx"),
        )
        assertEquals("beskeder2.aspx", MessageEditProtocol.formAction("<html></html>", "beskeder2.aspx"))
    }
}
