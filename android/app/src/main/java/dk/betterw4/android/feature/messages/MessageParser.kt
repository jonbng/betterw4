package dk.betterw4.android.feature.messages

/**
 * Lectio leftover helpers still used by offline message rows.
 */
object MessageParser {
    fun normalizeThreadId(id: String): String {
        val marker = "_\$_"
        val idx = id.indexOf(marker)
        if (idx < 0) return id
        return id.substring(idx + marker.length).ifBlank { id }
    }

    internal fun stripAppSignatures(html: String?): String? {
        if (html.isNullOrBlank()) return html
        var out: String = html
        listOf(
            "sendt med betterlectio",
            "sendt med BetterLectio",
            "Sendt med BetterLectio",
            "Sendt fra BetterLectio",
        ).forEach { sig ->
            out = out.replace(sig, "", ignoreCase = true)
        }
        return out.trim().ifBlank { null }
    }
}
