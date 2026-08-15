package dk.betterlectio.android.core.lectio.scrape

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
     * True when the final URL indicates the user is no longer in an authenticated Lectio page.
     * Does not treat UniLogin integration callback as failure.
     */
    fun isLoginPageUrl(url: String): Boolean {
        val lower = url.lowercase()
        if (lower.contains("unilogin.aspx")) return false
        return lower.contains("login.aspx")
    }
}
