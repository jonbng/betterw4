package dk.betterlectio.android.feature.messages

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle

/**
 * BBCode ↔ [AnnotatedString] conversion and style mutations for the rich message editor.
 * Wire format stays Lectio BBCode; UI shows real bold/italic/underline/links.
 */
object BbcodeDocument {

    const val URL_TAG = "URL"

    enum class StyleKind { Bold, Italic, Underline }

    data class StyleFlags(
        val bold: Boolean = false,
        val italic: Boolean = false,
        val underline: Boolean = false,
        val url: String? = null,
    ) {
        fun with(kind: StyleKind, on: Boolean): StyleFlags = when (kind) {
            StyleKind.Bold -> copy(bold = on)
            StyleKind.Italic -> copy(italic = on)
            StyleKind.Underline -> copy(underline = on)
        }

        fun has(kind: StyleKind): Boolean = when (kind) {
            StyleKind.Bold -> bold
            StyleKind.Italic -> italic
            StyleKind.Underline -> underline
        }
    }

    private val defaultLinkColor = Color(0xFF3362E1)

    fun spanStyle(
        flags: StyleFlags,
        linkColor: Color = defaultLinkColor,
    ): SpanStyle {
        // Always set weight/style explicitly so toggles off don't "inherit" stale spans.
        return SpanStyle(
            fontWeight = if (flags.bold) FontWeight.Bold else FontWeight.Normal,
            fontStyle = if (flags.italic) FontStyle.Italic else FontStyle.Normal,
            textDecoration = when {
                flags.underline || flags.url != null -> TextDecoration.Underline
                else -> TextDecoration.None
            },
            color = if (flags.url != null) linkColor else Color.Unspecified,
        )
    }

    // ── Parse BBCode → AnnotatedString ──────────────────────────────────

    fun bbcodeToAnnotated(
        bbcode: String,
        linkColor: Color = defaultLinkColor,
    ): AnnotatedString {
        if (bbcode.isEmpty()) return AnnotatedString("")
        return buildAnnotatedString {
            parseBbcode(bbcode, 0, StyleFlags(), linkColor)
        }
    }

    /**
     * Recursive BBCode parser. Returns index just after the consumed region
     * (or after matching close tag when [stopAtClose] is set).
     */
    private fun AnnotatedString.Builder.parseBbcode(
        src: String,
        start: Int,
        base: StyleFlags,
        linkColor: Color,
        stopAtClose: String? = null,
    ): Int {
        var i = start
        while (i < src.length) {
            if (src[i] != '[') {
                val next = src.indexOf('[', i).let { if (it < 0) src.length else it }
                val plain = src.substring(i, next)
                appendStyled(plain, base, linkColor)
                i = next
                continue
            }
            val close = src.indexOf(']', i)
            if (close < 0) {
                appendStyled(src.substring(i), base, linkColor)
                return src.length
            }
            val tagBody = src.substring(i + 1, close)
            val tagLower = tagBody.lowercase()

            // Closing tag
            if (tagBody.startsWith("/")) {
                val name = tagBody.drop(1).lowercase().substringBefore('=')
                if (stopAtClose != null && name == stopAtClose) {
                    return close + 1
                }
                // Unmatched close — emit literally
                appendStyled(src.substring(i, close + 1), base, linkColor)
                i = close + 1
                continue
            }

            when {
                tagLower == "b" || tagLower == "i" || tagLower == "u" -> {
                    val kind = when (tagLower) {
                        "b" -> StyleKind.Bold
                        "i" -> StyleKind.Italic
                        else -> StyleKind.Underline
                    }
                    val nextFlags = base.with(kind, true)
                    i = parseBbcode(src, close + 1, nextFlags, linkColor, stopAtClose = tagLower)
                }
                tagLower.startsWith("url=") -> {
                    val href = BbcodeEdit.sanitizeUrl(tagBody.substring(4))
                    val nextFlags = base.copy(url = href.ifBlank { null })
                    i = parseBbcode(src, close + 1, nextFlags, linkColor, stopAtClose = "url")
                }
                tagLower == "url" -> {
                    // [url]href[/url] — content is the URL (and the link label)
                    i = appendBareUrlTag(src, close + 1, base, linkColor)
                }
                else -> {
                    // Unknown tag — keep as text
                    appendStyled(src.substring(i, close + 1), base, linkColor)
                    i = close + 1
                }
            }
        }
        return i
    }

    /** Consume [url]…[/url] content starting at [contentStart]; append as a single link span. */
    private fun AnnotatedString.Builder.appendBareUrlTag(
        src: String,
        contentStart: Int,
        base: StyleFlags,
        linkColor: Color,
    ): Int {
        var i = contentStart
        var depth = 1
        var contentEnd = contentStart
        while (i < src.length && depth > 0) {
            if (src[i] != '[') {
                i++
                continue
            }
            val c = src.indexOf(']', i)
            if (c < 0) break
            val body = src.substring(i + 1, c)
            val lower = body.lowercase()
            when {
                lower == "url" || lower.startsWith("url=") -> depth++
                lower == "/url" -> {
                    depth--
                    if (depth == 0) {
                        contentEnd = i
                        i = c + 1
                        break
                    }
                }
            }
            i = c + 1
        }
        if (depth != 0) {
            appendStyled(src.substring(contentStart), base, linkColor)
            return src.length
        }
        val inner = src.substring(contentStart, contentEnd)
        val href = BbcodeEdit.sanitizeUrl(inner.trim())
        appendStyled(inner, base.copy(url = href.ifBlank { null }), linkColor)
        return i
    }

    private fun AnnotatedString.Builder.appendStyled(
        text: String,
        flags: StyleFlags,
        linkColor: Color,
    ) {
        if (text.isEmpty()) return
        val style = spanStyle(flags, linkColor)
        val hasStyle = flags.bold || flags.italic || flags.underline || flags.url != null
        if (!hasStyle) {
            append(text)
            return
        }
        val start = length
        withStyle(style) { append(text) }
        flags.url?.let { url ->
            if (url.isNotBlank()) {
                addStringAnnotation(URL_TAG, url, start, length)
            }
        }
    }

    // ── Export AnnotatedString → BBCode ─────────────────────────────────

    fun annotatedToBbcode(annotated: AnnotatedString): String {
        if (annotated.isEmpty()) return ""
        val text = annotated.text
        if (text.isEmpty()) return ""

        val sb = StringBuilder()
        var i = 0
        while (i < text.length) {
            val flags = flagsAt(annotated, i)
            var j = i + 1
            while (j < text.length && flagsAt(annotated, j) == flags) j++
            val chunk = text.substring(i, j)
            sb.append(wrapBbcode(chunk, flags))
            i = j
        }
        return sb.toString()
    }

    fun flagsAt(annotated: AnnotatedString, index: Int): StyleFlags {
        if (index < 0 || index >= annotated.length) return StyleFlags()
        // Prefer innermost (last) span that covers this index — more reliable when spans nest.
        val styles = annotated.spanStyles.filter { index >= it.start && index < it.end }
        var bold = false
        var italic = false
        var underline = false
        for (r in styles) {
            val s = r.item
            val w = s.fontWeight
            if (w != null) {
                bold = w.weight >= FontWeight.Bold.weight
            }
            when (s.fontStyle) {
                FontStyle.Italic -> italic = true
                FontStyle.Normal -> italic = false
                else -> Unit
            }
            val dec = s.textDecoration
            if (dec != null) {
                underline = dec.contains(TextDecoration.Underline) && dec != TextDecoration.None
            }
        }
        val url = annotated.getStringAnnotations(URL_TAG, index, index + 1)
            .firstOrNull()?.item
        if (url != null) underline = true
        return StyleFlags(bold = bold, italic = italic, underline = underline, url = url)
    }

    private fun wrapBbcode(chunk: String, flags: StyleFlags): String {
        if (chunk.isEmpty()) return ""
        var s = chunk
        // Escape nothing — BBCode is the wire format; raw [ in text stays as-is
        if (flags.bold) s = "[b]$s[/b]"
        if (flags.italic) s = "[i]$s[/i]"
        // Underline without link
        if (flags.underline && flags.url == null) s = "[u]$s[/u]"
        if (flags.url != null) {
            val href = flags.url
            s = if (chunk == href || chunk.trim() == href) {
                "[url]$href[/url]"
            } else {
                "[url=$href]$s[/url]"
            }
        }
        return s
    }

    // ── Style queries / toggles ─────────────────────────────────────────

    fun rangeHasStyle(
        annotated: AnnotatedString,
        start: Int,
        end: Int,
        kind: StyleKind,
    ): Boolean {
        if (start >= end) return false
        var i = start
        while (i < end) {
            if (!flagsAt(annotated, i).has(kind)) return false
            i++
        }
        return true
    }

    fun toggleStyle(
        value: TextFieldValue,
        kind: StyleKind,
        linkColor: Color = defaultLinkColor,
    ): TextFieldValue {
        val start = value.selection.min.coerceIn(0, value.text.length)
        val end = value.selection.max.coerceIn(start, value.text.length)
        if (start == end) return value
        val remove = rangeHasStyle(value.annotatedString, start, end, kind)
        val rebuilt = mapRangeFlags(value.annotatedString, start, end, linkColor) { flags ->
            flags.with(kind, !remove)
        }
        return TextFieldValue(rebuilt, TextRange(start, end), value.composition)
    }

    fun applyLink(
        value: TextFieldValue,
        url: String,
        linkColor: Color = defaultLinkColor,
    ): TextFieldValue? {
        val safe = BbcodeEdit.sanitizeUrl(url)
        if (safe.isEmpty()) return null
        val start = value.selection.min.coerceIn(0, value.text.length)
        val end = value.selection.max.coerceIn(start, value.text.length)
        if (start == end) {
            // Insert URL text as link
            val builder = AnnotatedString.Builder()
            builder.append(value.annotatedString.subSequence(0, start))
            val linkStart = builder.length
            with(builder) {
                appendStyled(safe, StyleFlags(url = safe, underline = true), linkColor)
            }
            builder.append(value.annotatedString.subSequence(end, value.text.length))
            val ann = builder.toAnnotatedString()
            val caret = linkStart + safe.length
            return TextFieldValue(ann, TextRange(caret, caret), value.composition)
        }
        val rebuilt = mapRangeFlags(value.annotatedString, start, end, linkColor) { flags ->
            flags.copy(url = safe, underline = true)
        }
        return TextFieldValue(rebuilt, TextRange(start, end), value.composition)
    }

    fun insertListPrefix(
        value: TextFieldValue,
        ordered: Boolean,
    ): TextFieldValue {
        val text = value.text
        val start = value.selection.min.coerceIn(0, text.length)
        val end = value.selection.max.coerceIn(start, text.length)
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

        val builder = AnnotatedString.Builder()
        builder.append(value.annotatedString.subSequence(0, start))
        builder.append(insert)
        builder.append(value.annotatedString.subSequence(end, text.length))
        val ann = builder.toAnnotatedString()
        val caret = start + insert.length
        return TextFieldValue(ann, TextRange(caret, caret), value.composition)
    }

    private fun mapRangeFlags(
        annotated: AnnotatedString,
        start: Int,
        end: Int,
        linkColor: Color,
        transform: (StyleFlags) -> StyleFlags,
    ): AnnotatedString {
        if (start >= end) return annotated
        return buildAnnotatedString {
            append(annotated.subSequence(0, start))
            var i = start
            while (i < end) {
                val flags = transform(flagsAt(annotated, i))
                var j = i + 1
                while (j < end && transform(flagsAt(annotated, j)) == flags) j++
                appendStyled(annotated.text.substring(i, j), flags, linkColor)
                i = j
            }
            append(annotated.subSequence(end, annotated.length))
        }
    }

    /**
     * Merge IME/text edits into styled text: preserve styles on common prefix/suffix,
     * style inserted middle with [active] or style to the left of the caret.
     */
    fun mergeEdit(
        old: TextFieldValue,
        new: TextFieldValue,
        active: StyleFlags,
        linkColor: Color = defaultLinkColor,
    ): TextFieldValue {
        if (old.text == new.text) {
            return TextFieldValue(old.annotatedString, new.selection, new.composition)
        }
        val oldText = old.text
        val newText = new.text
        var prefix = 0
        val minLen = minOf(oldText.length, newText.length)
        while (prefix < minLen && oldText[prefix] == newText[prefix]) prefix++

        var oldEnd = oldText.length
        var newEnd = newText.length
        while (oldEnd > prefix && newEnd > prefix &&
            oldText[oldEnd - 1] == newText[newEnd - 1]
        ) {
            oldEnd--
            newEnd--
        }

        val mid = newText.substring(prefix, newEnd)
        val midFlags = when {
            mid.isEmpty() -> StyleFlags()
            active.bold || active.italic || active.underline || active.url != null -> active
            prefix > 0 -> flagsAt(old.annotatedString, prefix - 1)
            else -> StyleFlags()
        }

        val builder = AnnotatedString.Builder()
        if (prefix > 0) {
            builder.append(old.annotatedString.subSequence(0, prefix))
        }
        if (mid.isNotEmpty()) {
            builder.appendStyled(mid, midFlags, linkColor)
        }
        if (oldEnd < oldText.length) {
            builder.append(old.annotatedString.subSequence(oldEnd, oldText.length))
        }
        return TextFieldValue(builder.toAnnotatedString(), new.selection, new.composition)
    }

    fun fromBbcodeField(
        bbcode: String,
        selection: TextRange = TextRange(0, 0),
        linkColor: Color = defaultLinkColor,
    ): TextFieldValue {
        val ann = bbcodeToAnnotated(bbcode, linkColor)
        val sel = TextRange(
            selection.min.coerceIn(0, ann.length),
            selection.max.coerceIn(0, ann.length),
        )
        return TextFieldValue(ann, sel)
    }
}
