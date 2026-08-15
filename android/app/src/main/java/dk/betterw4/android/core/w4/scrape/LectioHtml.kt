package dk.betterw4.android.core.w4.scrape

import dk.betterw4.android.core.w4.W4Html
import java.nio.charset.Charset
import kotlin.text.Charsets

/**
 * HTML decode + page classification helpers.
 * iOS parity: LectioHTTPClient.decodeHTML / isRobotDetectionPage
 */
object LectioHtml {

    fun decode(bytes: ByteArray): String {
        // Prefer UTF-8; Lectio sometimes serves windows-1252 / ISO-8859-1.
        val utf8 = String(bytes, Charsets.UTF_8)
        if (!utf8.contains('\uFFFD')) return utf8
        return try {
            String(bytes, Charset.forName("ISO-8859-1"))
        } catch (_: Exception) {
            utf8
        }
    }

    fun isRobotDetectionPage(html: String): Boolean {
        return html.contains("ikke er en robot", ignoreCase = true) ||
            html.contains("Af hensyn til sikkerheden", ignoreCase = true) ||
            html.contains("RobotDetection.aspx", ignoreCase = true) ||
            html.contains("RobotDetection", ignoreCase = true)
    }

    /**
     * True when the final URL indicates the login page.
     */
    fun isLoginPageUrl(url: String): Boolean {
        val lower = url.lowercase()
        return lower.contains("login.aspx") ||
            lower.contains("r=site/login") ||
            lower.contains("r=site%2flogin")
    }

    fun isLoginHtml(html: String): Boolean = W4Html.isLoginHtml(html)

    fun isAuthenticatedHtml(html: String): Boolean = W4Html.isAuthenticatedHtml(html)
}
