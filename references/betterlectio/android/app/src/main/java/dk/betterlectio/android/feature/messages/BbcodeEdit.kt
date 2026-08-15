package dk.betterlectio.android.feature.messages

/**
 * Pure BBCode edit helpers for the compose/reply toolbar (extension textarea mode parity).
 */
object BbcodeEdit {

    data class EditResult(
        val text: String,
        val selectionStart: Int,
        val selectionEnd: Int,
    )

    fun sanitizeUrl(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""
        if (trimmed.contains(Regex("""^(https?://|//|mailto:)""", RegexOption.IGNORE_CASE))) {
            return trimmed
        }
        // Dangerous / other schemes → strip and force https
        val scheme = Regex("""^([a-z][a-z0-9+.-]*:)\s*""", RegexOption.IGNORE_CASE)
        if (scheme.containsMatchIn(trimmed)) {
            val stripped = trimmed.replace(scheme, "")
            return "https://$stripped"
        }
        return "https://$trimmed"
    }

    fun wrapSelection(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        before: String,
        after: String,
    ): EditResult {
        val start = selectionStart.coerceIn(0, text.length)
        val end = selectionEnd.coerceIn(start, text.length)
        val selected = text.substring(start, end)
        val newText = text.substring(0, start) + before + selected + after + text.substring(end)
        return if (selected.isEmpty()) {
            val cursor = start + before.length
            EditResult(newText, cursor, cursor)
        } else {
            EditResult(
                newText,
                start + before.length,
                start + before.length + selected.length,
            )
        }
    }

    fun bold(text: String, start: Int, end: Int): EditResult =
        wrapSelection(text, start, end, "[b]", "[/b]")

    fun italic(text: String, start: Int, end: Int): EditResult =
        wrapSelection(text, start, end, "[i]", "[/i]")

    fun underline(text: String, start: Int, end: Int): EditResult =
        wrapSelection(text, start, end, "[u]", "[/u]")

    fun insertLink(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        url: String,
        linkText: String? = null,
    ): EditResult? {
        val safe = sanitizeUrl(url)
        if (safe.isEmpty()) return null
        val start = selectionStart.coerceIn(0, text.length)
        val end = selectionEnd.coerceIn(start, text.length)
        val selected = text.substring(start, end)
        val label = selected.ifBlank { linkText?.takeIf { it.isNotBlank() } ?: safe }
        val bbcode = "[url=$safe]$label[/url]"
        val newText = text.substring(0, start) + bbcode + text.substring(end)
        val cursor = start + bbcode.length
        return EditResult(newText, cursor, cursor)
    }

    fun insertList(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        ordered: Boolean,
    ): EditResult {
        val start = selectionStart.coerceIn(0, text.length)
        val end = selectionEnd.coerceIn(start, text.length)
        val selected = text.substring(start, end)
        val listText = if (selected.isBlank()) {
            if (ordered) "1. " else "• "
        } else {
            val lines = selected.split('\n').map { it.trim() }.filter { it.isNotEmpty() }
            if (ordered) {
                lines.mapIndexed { i, line -> "${i + 1}. $line" }.joinToString("\n")
            } else {
                lines.joinToString("\n") { "• $it" }
            }
        }
        val prefix = if (start > 0 && text[start - 1] != '\n') "\n" else ""
        val suffix = if (end < text.length && text[end] != '\n') "\n" else ""
        val insert = prefix + listText + suffix
        val newText = text.substring(0, start) + insert + text.substring(end)
        val cursor = start + insert.length
        return EditResult(newText, cursor, cursor)
    }
}
