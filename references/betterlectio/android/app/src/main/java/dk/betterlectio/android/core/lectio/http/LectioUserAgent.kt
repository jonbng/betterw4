package dk.betterlectio.android.core.lectio.http

object LectioUserAgent {
    /** Browser-like UA; matches iOS LectioHTTPClient. */
    const val VALUE =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/120.0.0.0 Mobile Safari/537.36 BetterLectio/1.0"

    const val REFERER = "https://www.lectio.dk"
}
