package dk.betterlectio.android.core.lectio.auth

/**
 * URL classification for the MitID / UniLogin WebView login flow.
 * Mirrors Flutter `uni_login_screen.dart` + iOS `AuthenticationService.isCallbackURL`.
 */
object MitIdAuthUrls {

    /**
     * Lectio callback after successful MitID (iOS + Flutter):
     * - `lectio.dk/lectio/integration/unilogin.aspx` without broker host
     * - any `/forside.aspx` on lectio.dk (already logged in)
     */
    fun isAuthSuccessUrl(url: String): Boolean {
        val lower = url.lowercase()
        if (lower.contains("broker.unilogin.dk")) return false
        if (!lower.contains("lectio.dk")) return false
        if (lower.contains("/forside.aspx")) return true
        // Flutter / iOS: only the Lectio integration callback, not arbitrary unilogin pages.
        return lower.contains("lectio.dk/lectio/integration/unilogin.aspx")
    }

    /**
     * True when this is the UniLogin→Lectio integration callback that still needs to load
     * (or be HTTP-replayed) so Lectio can mint session cookies. Cancelling navigation here
     * leaves the jar incomplete — that was the Android login parse failure root cause.
     */
    fun isUniloginIntegrationCallback(url: String): Boolean {
        val lower = url.lowercase()
        if (lower.contains("broker.unilogin.dk")) return false
        return lower.contains("lectio.dk/lectio/integration/unilogin.aspx")
    }

    /**
     * MitID app-switch deep link that must leave the WebView and open the MitID app
     * (or a chooser). Flutter: `https://appswitch.mitid.dk/` + AndroidIntent ACTION_VIEW.
     *
     * Real devices send both `…mitid.dk/?ticket=…` and `…mitid.dk/launch?…`.
     */
    fun isMitIdAppSwitchUrl(url: String): Boolean {
        val lower = url.lowercase()
        if (APP_SWITCH_HOST_REGEX.containsMatchIn(lower)) {
            return true
        }
        if (lower.startsWith("mitid://") || lower.startsWith("mitiddk://")) {
            return true
        }
        if (lower.startsWith("intent://") && lower.contains("mitid")) {
            return true
        }
        return false
    }

    fun isExternalAppUrl(url: String): Boolean {
        if (isMitIdAppSwitchUrl(url)) return true
        val scheme = url.substringBefore(':', missingDelimiterValue = "").lowercase()
        return when (scheme) {
            "http", "https", "about", "data", "javascript", "file", "" -> false
            else -> true
        }
    }

    /** Extract elev/lærer id from a URL query if present. */
    fun personIdFromUrl(url: String): String? {
        val elev = Regex("""[?&]elevid=(\d+)""", RegexOption.IGNORE_CASE).find(url)
            ?.groupValues?.getOrNull(1)
        if (!elev.isNullOrBlank()) return elev
        return Regex("""[?&]laererid=(\d+)""", RegexOption.IGNORE_CASE).find(url)
            ?.groupValues?.getOrNull(1)
    }

    private val APP_SWITCH_HOST_REGEX =
        Regex("""^https?://appswitch\.mitid\.dk(?:[/?#]|$)""")
}
