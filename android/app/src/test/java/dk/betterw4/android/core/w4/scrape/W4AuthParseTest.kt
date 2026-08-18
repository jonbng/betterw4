package dk.betterw4.android.core.w4.scrape

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LectioHtmlTest {

    @Test
    fun login_url_detects_yii_route() {
        assertTrue(LectioHtml.isLoginPageUrl("https://w4.uwcrcn.no/index.php?r=site/login"))
        assertTrue(LectioHtml.isLoginPageUrl("https://w4.uwcrcn.no/index.php?r=site%2Flogin"))
        assertFalse(LectioHtml.isLoginPageUrl("https://w4.uwcrcn.no/index.php?r=site/otp"))
        assertFalse(LectioHtml.isLoginPageUrl("https://w4.uwcrcn.no/index.php?r=site/verify2fa"))
        assertFalse(LectioHtml.isLoginPageUrl("https://w4.uwcrcn.no/index.php?r=site/index"))
    }

    @Test
    fun login_html_and_authenticated_chrome() {
        val login = """<title>Login Site</title><input name="LoginForm[username]">"""
        val home = """<div id="user-panel"><div class="right">Welcome, Ada</div></div>"""
        assertTrue(LectioHtml.isLoginHtml(login))
        assertFalse(LectioHtml.isAuthenticatedHtml(login))
        assertTrue(LectioHtml.isAuthenticatedHtml(home))
        assertFalse(LectioHtml.isLoginHtml(home))
    }
}

class W4FormTest {

    @Test
    fun parses_login_form_fields() {
        val html = """
            <form action="/index.php?r=site/login" method="post">
              <input name="LoginForm[username]" value="">
              <input name="LoginForm[password]" type="password">
              <input name="LoginForm[deviceId]" type="hidden" value="">
              <input name="yt0" type="submit" value="Login">
            </form>
        """.trimIndent()
        val parsed = W4Form.parse(html)!!
        assertEquals("/index.php?r=site/login", parsed.action)
        assertTrue(parsed.fields.containsKey("LoginForm[username]"))
        assertEquals("yt0", parsed.submitName)
        assertEquals("Login", parsed.submitValue)
    }

    @Test
    fun finds_otp_field_and_error_summary() {
        val html = """
            <div class="errorSummary"><ul><li>Incorrect code.</li></ul></div>
            <form action="/index.php?r=site/otp" method="post">
              <input name="OtpForm[code]" type="text" value="">
              <input name="yt0" type="submit" value="Verify">
            </form>
        """.trimIndent()
        val parsed = W4Form.parse(html)!!
        assertEquals("OtpForm[code]", parsed.otpFieldName)
        assertEquals("Incorrect code.", W4Form.loginError(html))
    }

    @Test
    fun finds_verify2fa_password_typed_code_field() {
        val html = """
            <form action="/index.php?r=site/verify2fa" method="post">
              <input name="YII_CSRF_TOKEN" type="hidden" value="abc">
              <input name="Verify2faForm[code]" type="password" value="" maxlength="8">
              <input name="yt0" type="submit" value="Verify">
            </form>
        """.trimIndent()
        val parsed = W4Form.parse(html)!!
        assertEquals("/index.php?r=site/verify2fa", parsed.action)
        assertEquals("Verify2faForm[code]", parsed.otpFieldName)
        assertEquals("yt0", parsed.submitName)
        assertEquals("Verify", parsed.submitValue)
    }

    @Test
    fun verify2fa_picks_lone_visible_input_when_name_is_generic() {
        val html = """
            <form action="/index.php?r=site/verify2fa" method="post">
              <input name="Verify2faForm[value]" type="text" value="">
              <input name="yt0" type="submit" value="Continue">
            </form>
        """.trimIndent()
        val parsed = W4Form.parse(html)!!
        assertEquals("Verify2faForm[value]", parsed.otpFieldName)
    }

    @Test
    fun parses_captured_verify2fa_form() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("w4/verify2fa.html")!!
            .bufferedReader()
            .readText()
        val parsed = W4Form.parse(html)!!
        assertEquals("/index.php?r=site/verify2fa", parsed.action)
        assertEquals("OtpModel[otp]", parsed.otpFieldName)
        assertEquals("0", parsed.fields["OtpModel[remember]"])
        assertEquals("", parsed.fields["OtpModel[deviceId]"])
        assertEquals("yt0", parsed.submitName)
        assertEquals("Submit", parsed.submitValue)
    }

    @Test
    fun encode_brackets_are_percent_encoded() {
        val bytes = W4Form.encode(mapOf("LoginForm[username]" to "nc26test"))
        val encoded = bytes.decodeToString()
        assertTrue(encoded.contains("LoginForm%5Busername%5D=nc26test"))
    }
}

class W4IdentityParserTest {

    @Test
    fun parses_welcome_and_self_profile_uwc_id() {
        val html = """
            <div id="user-panel">
              <div class="right">Welcome, Jonathan Bangert<br>
                <a href="https://w4.uwcrcn.no/index.php?r=site/logout">Logout</a>
              </div>
            </div>
            <p>Go to your <a href="https://w4.uwcrcn.no/index.php?r=people/students/student&amp;uwc_id=nc26jban">W4 public profile</a></p>
            <a href="https://w4.uwcrcn.no/index.php?r=people/students/student&amp;uwc_id=nc25eros">Someone else</a>
        """.trimIndent()
        val identity = W4IdentityParser.parse(html)
        assertEquals("nc26jban", identity.studentId)
        assertEquals("Jonathan Bangert", identity.name)
        assertNull(identity.teacherId)
    }

    @Test
    fun captured_chrome_strips_pipe_from_welcome() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("w4/home-chrome.html")!!
            .bufferedReader()
            .readText()
        val identity = W4IdentityParser.parse(html)
        assertEquals("Jonathan Bangert", identity.name)
        assertEquals("nc26jban", identity.studentId)
    }
}
