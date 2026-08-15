package dk.betterw4.android.core.w4

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class W4HtmlTest {

    private val chrome = javaClass.classLoader!!
        .getResourceAsStream("w4/home-chrome.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun login_html_vs_authenticated_chrome() {
        val login = """<title>Login Site</title><input name="LoginForm[username]">"""
        assertTrue(W4Html.isLoginHtml(login))
        assertFalse(W4Html.isAuthenticatedHtml(login))
        assertTrue(W4Html.isAuthenticatedHtml(chrome))
        assertFalse(W4Html.isLoginHtml(chrome))
    }

    @Test
    fun display_name_from_user_panel() {
        assertEquals("Jonathan Bangert", W4Html.displayName(chrome))
    }

    @Test
    fun uwc_id_prefers_public_profile_link() {
        assertEquals("nc26jban", W4Html.uwcId(chrome))
    }

    @Test
    fun ajax_login_required_is_case_insensitive() {
        assertTrue(W4Html.isAjaxLoginRequired("Login Required"))
        assertTrue(W4Html.isAjaxLoginRequired("<p>login required</p>"))
        assertFalse(W4Html.isAjaxLoginRequired("not authorized"))
    }

    @Test
    fun content_inner_extracts_page_body() {
        assertTrue(W4Html.contentInner(chrome)!!.contains("W4 public profile"))
    }
}
