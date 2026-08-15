package dk.betterlectio.android.core.lectio.scrape

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

object LectioUrls {
    const val HOST = "www.lectio.dk"
    const val ORIGIN = "https://www.lectio.dk"

    fun baseUrl(gymId: Int): HttpUrl =
        "https://www.lectio.dk/lectio/$gymId/".toHttpUrl()

    fun buildUrl(gymId: Int, path: String): HttpUrl {
        if (path.startsWith("http://") || path.startsWith("https://")) {
            return path.toHttpUrl()
        }
        val trimmed = path.removePrefix("/")
        return baseUrl(gymId).newBuilder()
            .addPathSegments(trimmed.substringBefore('?'))
            .apply {
                val query = trimmed.substringAfter('?', missingDelimiterValue = "")
                if (query.isNotEmpty()) {
                    // Preserve raw query (ASP.NET uses special keys)
                    // rebuild from encoded query string
                }
            }
            .build()
            .let { built ->
                val q = trimmed.substringAfter('?', missingDelimiterValue = "")
                if (q.isEmpty()) built
                else "$built?$q".toHttpUrl()
            }
    }

    fun resolve(pathOrUrl: String, gymId: Int?): HttpUrl {
        pathOrUrl.toHttpUrlOrNull()?.let { return it }
        // Absolute site path from Lectio scripts, e.g. /lectio/94/cache/DropDown.aspx?…
        // Must not be resolved relative to the gym base (would double-prefix /lectio/{id}/).
        if (pathOrUrl.startsWith("/lectio/")) {
            return "$ORIGIN$pathOrUrl".toHttpUrl()
        }
        requireNotNull(gymId) { "gymId required for relative Lectio path: $pathOrUrl" }
        return buildUrl(gymId, pathOrUrl)
    }

    fun loginUrl(gymId: Int): HttpUrl = buildUrl(gymId, "login.aspx")

    fun forsideUrl(gymId: Int): HttpUrl = buildUrl(gymId, "forside.aspx")

    fun skemaUrl(gymId: Int, studentId: String): HttpUrl =
        buildUrl(gymId, "SkemaNy.aspx?type=elev&elevid=$studentId")
}
