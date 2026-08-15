package dk.betterw4.android.core.w4

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class YiiFormTest {

    private val loginHtml = """
        <form action="/index.php?r=site/login" method="post">
          <input name="LoginForm[username]" value="">
          <input name="LoginForm[password]" type="password">
          <input name="LoginForm[deviceId]" type="hidden" value="abc">
          <input name="yt0" type="submit" value="Login">
        </form>
    """.trimIndent()

    @Test
    fun parses_yii_login_without_csrf() {
        val parsed = YiiForm.parse(loginHtml)
        assertEquals("/index.php?r=site/login", parsed.action)
        assertEquals("", parsed.fields["LoginForm[username]"])
        assertEquals("abc", parsed.fields["LoginForm[deviceId]"])
        assertEquals("Login", parsed.submitButtons["yt0"])
        assertFalse(parsed.fields.keys.any { it.contains("csrf", ignoreCase = true) })
        assertFalse(parsed.fields.containsKey("yt0"))
    }

    @Test
    fun fields_for_submit_includes_clicked_yt0() {
        val fields = YiiForm.fieldsForSubmit(
            html = loginHtml,
            extra = mapOf("LoginForm[username]" to "nc26jban"),
        )
        assertEquals("nc26jban", fields["LoginForm[username]"])
        assertEquals("Login", fields["yt0"])
        assertEquals("abc", fields["LoginForm[deviceId]"])
        assertTrue(fields.containsKey("LoginForm[password]"))
    }
}
