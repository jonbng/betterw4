package dk.betterlectio.android.core.lectio.cookie

/**
 * Parses Set-Cookie header values into name/value pairs.
 * OkHttp's Headers can expose multiple Set-Cookie entries.
 */
object SetCookieParser {
    data class ParsedCookie(
        val name: String,
        val value: String,
        val domain: String?,
    )

    fun parse(setCookieHeaders: List<String>, responseHost: String?): List<ParsedCookie> {
        return setCookieHeaders.mapNotNull { header ->
            val head = header.substringBefore(';').trim()
            val eq = head.indexOf('=')
            if (eq <= 0) return@mapNotNull null
            val name = head.substring(0, eq).trim()
            val value = head.substring(eq + 1).trim()
            if (name.isEmpty()) return@mapNotNull null

            val domainAttr = header
                .split(';')
                .drop(1)
                .map { it.trim() }
                .firstOrNull { it.startsWith("domain=", ignoreCase = true) }
                ?.substringAfter('=')
                ?.trim()
                ?.removePrefix(".")

            ParsedCookie(
                name = name,
                value = value,
                domain = domainAttr ?: responseHost,
            )
        }
    }

    /** True if this cookie belongs to the Lectio realm (iOS: domain.contains("lectio.dk")). */
    fun isLectioDomain(domain: String?): Boolean {
        if (domain.isNullOrBlank()) return false
        return domain.contains("lectio.dk", ignoreCase = true)
    }
}
