package dk.betterw4.android.core.w4

import org.jsoup.Jsoup
import java.nio.charset.Charset
import kotlin.text.Charsets

/**
 * Decode + classify W4 HTML. Session rules: README §4.5 / §5.6.
 */
object W4Html {
    val UWC_ID = Regex("""\b(nc\d{2}[a-z]+)\b""", RegexOption.IGNORE_CASE)

    fun decode(bytes: ByteArray): String {
        val utf8 = String(bytes, Charsets.UTF_8)
        if (!utf8.contains('\uFFFD')) return utf8
        return try {
            String(bytes, Charset.forName("ISO-8859-1"))
        } catch (_: Exception) {
            utf8
        }
    }

    fun isLoginHtml(html: String): Boolean =
        html.contains("LoginForm[username]", ignoreCase = true) ||
            html.contains("Login Site", ignoreCase = true)

    /**
     * Logged-in chrome. Mid-login 2FA pages can also include this — callers must
     * check [W4Session.isOtpUrl] first.
     */
    fun isAuthenticatedHtml(html: String): Boolean {
        val hasWelcome = html.contains("Welcome,", ignoreCase = true)
        val hasPanel = html.contains("id=\"user-panel\"", ignoreCase = true) ||
            html.contains("id='user-panel'", ignoreCase = true)
        return (hasWelcome || hasPanel) && !isLoginHtml(html)
    }

    fun isAjaxLoginRequired(body: String): Boolean =
        body.contains("Login Required", ignoreCase = true)

    fun displayName(html: String): String? {
        val doc = Jsoup.parse(html)
        val right = doc.selectFirst("#user-panel .right")?.ownText().orEmpty()
        WELCOME.find(right)?.groupValues?.get(1)?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val panel = doc.getElementById("user-panel") ?: return null
        val text = panel.ownText().ifBlank { panel.text() }
        return WELCOME.find(text)
            ?.groupValues?.get(1)
            ?.substringBefore("Logout")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    /**
     * Prefer the signed-in student's own profile link.
     *
     * Bug B17: a document-wide `nc\\d{2}[a-z]+` sweep on Home hits a birthday
     * classmate first. `#hello` (and then `#user-panel`) is the only honest source.
     */
    fun uwcId(html: String): String? {
        val doc = Jsoup.parse(html)
        val hello = doc.getElementById("hello")
        hello?.select("a[href*=uwc_id]")?.firstOrNull()?.attr("href")
            ?.let { UWC_ID.find(it)?.groupValues?.get(1)?.lowercase() }
            ?.let { return it }
        val profile = doc.select("#hello a[href*=uwc_id], #user-panel a[href*=uwc_id]")
            .firstOrNull()
            ?: doc.select("a[href*=people/students/student][href*=uwc_id]")
                .firstOrNull { it.text().contains("profile", ignoreCase = true) }
        val href = profile?.attr("href").orEmpty()
        UWC_ID.find(href)?.groupValues?.get(1)?.lowercase()?.let { return it }
        return null
    }

    fun contentInner(html: String): String? =
        Jsoup.parse(html).getElementById("content_inner")?.html()

    private val WELCOME = Regex("""Welcome,\s*([^|<]+)""", RegexOption.IGNORE_CASE)
}
