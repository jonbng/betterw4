package dk.betterw4.android.feature.directory

/** IB year as printed on W4 people rows (`1st year`, `Year 2`). */
object DirectoryYear {
    fun parse(text: String?): String? {
        if (text.isNullOrBlank()) return null
        val trimmed = text.trim()
        if (FIRST.containsMatchIn(trimmed)) return "1"
        if (SECOND.containsMatchIn(trimmed)) return "2"
        STATED.find(trimmed)?.groupValues?.get(1)?.let { return it }
        LABELED.find(trimmed)?.groupValues?.get(1)?.let { return it }
        if (trimmed == "1" || trimmed == "2") return trimmed
        return null
    }

    private val FIRST = Regex("""\bfirst\s+year\b""", RegexOption.IGNORE_CASE)
    private val SECOND = Regex("""\bsecond\s+year\b""", RegexOption.IGNORE_CASE)
    private val STATED = Regex("""\b([12])\s*(?:st|nd|rd|th)?\s*year\b""", RegexOption.IGNORE_CASE)
    private val LABELED = Regex("""\byears?\s*([12])\b""", RegexOption.IGNORE_CASE)
}
