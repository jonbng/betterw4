package dk.betterw4.android.core.w4.auth

/**
 * W4 emails an 8-character mixed-case code (`5Z4IccMB`, `w3RSqC6f`).
 *
 * The clipboard helper only accepts the whole copied string so a username
 * (`nc` + two-digit year, e.g. `nc26abcd`) or a longer password is never
 * treated as a code.
 */
internal object W4OtpCode {
    const val LENGTH = 8

    fun extract(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        val candidate = trimmed.unquote().trim().trim { !it.isAsciiLetterOrDigit() }
        return candidate.takeIf { looksLike(it) }
    }

    fun looksLike(code: String): Boolean {
        if (code.length != LENGTH) return false
        if (code.any { !it.isAsciiLetterOrDigit() }) return false
        if (looksLikeUsername(code)) return false
        return code.any { it in 'A'..'Z' }
    }

    /** W4 ids are `nc` + two-digit year + letters (`nc26abcd`). Never treat those as a code. */
    private fun looksLikeUsername(code: String): Boolean {
        if (code.length < 4) return false
        val n = code[0]
        val c = code[1]
        return (n == 'n' || n == 'N') && (c == 'c' || c == 'C') &&
            code[2] in '0'..'9' && code[3] in '0'..'9'
    }

    fun sanitizeInput(value: String): String =
        value.filter { !it.isWhitespace() }.take(LENGTH)

    private fun String.unquote(): String {
        if (length >= 2) {
            val first = first()
            val last = last()
            if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
                return substring(1, length - 1)
            }
        }
        return this
    }

    private fun Char.isAsciiLetterOrDigit(): Boolean =
        this in '0'..'9' || this in 'A'..'Z' || this in 'a'..'z'
}
