package dk.betterlectio.android.core.lectio.http

import okhttp3.HttpUrl

/**
 * iOS parity: isLectioUniLoginURL — host contains broker.unilogin.dk is definitive session death.
 */
object UniLoginDetector {
    fun isUniLoginBroker(url: HttpUrl): Boolean {
        val host = url.host.lowercase()
        return host.contains("broker.unilogin.dk") ||
            host == "unilogin.dk" ||
            host.endsWith(".unilogin.dk") && host.contains("broker")
    }

    fun isUniLoginBroker(urlString: String): Boolean {
        val host = urlString.substringAfter("://").substringBefore('/').lowercase()
        return host.contains("broker.unilogin.dk") ||
            (host.endsWith("unilogin.dk") && host.contains("broker"))
    }
}
