package dk.betterlectio.android.feature.messages

import android.graphics.Typeface
import android.text.Editable
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import android.text.style.UpdateAppearance
import android.widget.EditText

/**
 * BBCode ↔ Android [Spannable] for a stable [EditText] editor
 * (extension contentEditable parity — avoids Compose TextField span bugs).
 */
object BbcodeSpannable {

    enum class StyleKind { Bold, Italic, Underline }

    data class Flags(
        val bold: Boolean = false,
        val italic: Boolean = false,
        val underline: Boolean = false,
        val url: String? = null,
    ) {
        fun with(kind: StyleKind, on: Boolean) = when (kind) {
            StyleKind.Bold -> copy(bold = on)
            StyleKind.Italic -> copy(italic = on)
            StyleKind.Underline -> copy(underline = on)
        }

        fun has(kind: StyleKind) = when (kind) {
            StyleKind.Bold -> bold
            StyleKind.Italic -> italic
            StyleKind.Underline -> underline
        }
    }

    class LinkSpan(
        val url: String,
        val color: Int,
    ) : CharacterStyle(), UpdateAppearance {
        override fun updateDrawState(tp: TextPaint) {
            tp.color = color
            tp.isUnderlineText = true
        }
    }

    // ── BBCode → Spannable ──────────────────────────────────────────────

    fun bbcodeToSpannable(bbcode: String, linkColor: Int): SpannableStringBuilder {
        val out = SpannableStringBuilder()
        if (bbcode.isEmpty()) return out
        parseInto(out, bbcode, 0, Flags(), linkColor)
        return out
    }

    private fun parseInto(
        out: SpannableStringBuilder,
        src: String,
        start: Int,
        base: Flags,
        linkColor: Int,
        stopAtClose: String? = null,
    ): Int {
        var i = start
        while (i < src.length) {
            if (src[i] != '[') {
                val next = src.indexOf('[', i).let { if (it < 0) src.length else it }
                appendStyled(out, src.substring(i, next), base, linkColor)
                i = next
                continue
            }
            val close = src.indexOf(']', i)
            if (close < 0) {
                appendStyled(out, src.substring(i), base, linkColor)
                return src.length
            }
            val tagBody = src.substring(i + 1, close)
            val tagLower = tagBody.lowercase()
            if (tagBody.startsWith("/")) {
                val name = tagBody.drop(1).lowercase().substringBefore('=')
                if (stopAtClose != null && name == stopAtClose) return close + 1
                appendStyled(out, src.substring(i, close + 1), base, linkColor)
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
                    i = parseInto(out, src, close + 1, base.with(kind, true), linkColor, tagLower)
                }
                tagLower.startsWith("url=") -> {
                    val href = BbcodeEdit.sanitizeUrl(tagBody.substring(4))
                    i = parseInto(
                        out, src, close + 1,
                        base.copy(url = href.ifBlank { null }),
                        linkColor, "url",
                    )
                }
                tagLower == "url" -> i = appendBareUrl(out, src, close + 1, base, linkColor)
                else -> {
                    appendStyled(out, src.substring(i, close + 1), base, linkColor)
                    i = close + 1
                }
            }
        }
        return i
    }

    private fun appendBareUrl(
        out: SpannableStringBuilder,
        src: String,
        contentStart: Int,
        base: Flags,
        linkColor: Int,
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
            val body = src.substring(i + 1, c).lowercase()
            when {
                body == "url" || body.startsWith("url=") -> depth++
                body == "/url" -> {
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
            appendStyled(out, src.substring(contentStart), base, linkColor)
            return src.length
        }
        val inner = src.substring(contentStart, contentEnd)
        val href = BbcodeEdit.sanitizeUrl(inner.trim())
        appendStyled(out, inner, base.copy(url = href.ifBlank { null }), linkColor)
        return i
    }

    private fun appendStyled(
        out: SpannableStringBuilder,
        text: String,
        flags: Flags,
        linkColor: Int,
    ) {
        if (text.isEmpty()) return
        val start = out.length
        out.append(text)
        applyFlags(out, start, out.length, flags, linkColor)
    }

    private fun applyFlags(
        out: Spannable,
        start: Int,
        end: Int,
        flags: Flags,
        linkColor: Int,
    ) {
        if (start >= end) return
        val flag = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        when {
            flags.bold && flags.italic ->
                out.setSpan(StyleSpan(Typeface.BOLD_ITALIC), start, end, flag)
            flags.bold -> out.setSpan(StyleSpan(Typeface.BOLD), start, end, flag)
            flags.italic -> out.setSpan(StyleSpan(Typeface.ITALIC), start, end, flag)
        }
        if (flags.underline && flags.url == null) {
            out.setSpan(UnderlineSpan(), start, end, flag)
        }
        flags.url?.takeIf { it.isNotBlank() }?.let { url ->
            out.setSpan(LinkSpan(url, linkColor), start, end, flag)
        }
    }

    // ── Spannable → BBCode ──────────────────────────────────────────────

    fun spannableToBbcode(spanned: CharSequence): String {
        if (spanned.isEmpty()) return ""
        val len = spanned.length
        val sb = StringBuilder()
        var i = 0
        while (i < len) {
            val flags = flagsAt(spanned, i)
            var j = i + 1
            while (j < len && flagsAt(spanned, j) == flags) j++
            sb.append(wrapBbcode(spanned.subSequence(i, j).toString(), flags))
            i = j
        }
        return sb.toString()
    }

    fun flagsAt(spanned: CharSequence, index: Int): Flags {
        if (index < 0 || index >= spanned.length || spanned !is Spanned) return Flags()
        val styles = spanned.getSpans(index, index + 1, StyleSpan::class.java)
        var bold = false
        var italic = false
        for (s in styles) {
            when (s.style) {
                Typeface.BOLD -> bold = true
                Typeface.ITALIC -> italic = true
                Typeface.BOLD_ITALIC -> {
                    bold = true
                    italic = true
                }
            }
        }
        val under = spanned.getSpans(index, index + 1, UnderlineSpan::class.java).isNotEmpty()
        val link = spanned.getSpans(index, index + 1, LinkSpan::class.java).firstOrNull()?.url
        return Flags(
            bold = bold,
            italic = italic,
            underline = under || link != null,
            url = link,
        )
    }

    private fun wrapBbcode(chunk: String, flags: Flags): String {
        if (chunk.isEmpty()) return ""
        var s = chunk
        if (flags.bold) s = "[b]$s[/b]"
        if (flags.italic) s = "[i]$s[/i]"
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

    // ── EditText actions ────────────────────────────────────────────────

    fun rangeHasStyle(edit: EditText, kind: StyleKind): Boolean {
        val start = edit.selectionStart.coerceAtLeast(0)
        val end = edit.selectionEnd.coerceAtLeast(start)
        if (start >= end) return false
        val text = edit.text ?: return false
        for (i in start until end) {
            if (!flagsAt(text, i).has(kind)) return false
        }
        return true
    }

    /**
     * Toggle B/I/U on the current selection (must be non-empty).
     * @return whether the style is active on the selection after the toggle
     */
    fun toggleStyle(edit: EditText, kind: StyleKind, linkColor: Int): Boolean {
        val start = edit.selectionStart
        val end = edit.selectionEnd
        if (start < 0 || end <= start) return false
        val remove = rangeHasStyle(edit, kind)
        mapSelection(edit, linkColor) { it.with(kind, !remove) }
        return !remove
    }

    fun applyLink(edit: EditText, rawUrl: String, linkColor: Int): Boolean {
        val safe = BbcodeEdit.sanitizeUrl(rawUrl)
        if (safe.isEmpty()) return false
        val editable = edit.text ?: return false
        var start = edit.selectionStart.coerceIn(0, editable.length)
        var end = edit.selectionEnd.coerceIn(start, editable.length)
        if (start == end) {
            editable.insert(start, safe)
            end = start + safe.length
        }
        edit.setSelection(start, end)
        mapSelection(edit, linkColor) { it.copy(url = safe, underline = true) }
        edit.setSelection(end)
        return true
    }

    fun insertListPrefix(edit: EditText, ordered: Boolean) {
        val editable = edit.text ?: return
        val start = edit.selectionStart.coerceIn(0, editable.length)
        val end = edit.selectionEnd.coerceIn(start, editable.length)
        val selected = editable.subSequence(start, end).toString()
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
        val prefix = if (start > 0 && editable[start - 1] != '\n') "\n" else ""
        val suffix = if (end < editable.length && editable[end] != '\n') "\n" else ""
        val insert = prefix + listText + suffix
        editable.replace(start, end, insert)
        edit.setSelection(start + insert.length)
    }

    fun setFromBbcode(edit: EditText, bbcode: String, linkColor: Int) {
        edit.setText(bbcodeToSpannable(bbcode, linkColor))
        val len = edit.text?.length ?: 0
        edit.setSelection(len)
    }

    /**
     * Capture flags for each selected char, clear style spans in range, re-apply transformed flags.
     * Outside-range styles are preserved via span splitting.
     */
    fun mapSelection(
        edit: EditText,
        linkColor: Int,
        transform: (Flags) -> Flags,
    ) {
        val editable = edit.text ?: return
        val start = edit.selectionStart.coerceIn(0, editable.length)
        val end = edit.selectionEnd.coerceIn(start, editable.length)
        if (start >= end) return

        val newFlags = Array(end - start) { offset ->
            transform(flagsAt(editable, start + offset))
        }

        // Full rebuild of document styles is simpler and reliable for short messages.
        val plain = editable.toString()
        val allFlags = Array(plain.length) { idx ->
            when {
                idx in start until end -> newFlags[idx - start]
                else -> flagsAt(editable, idx)
            }
        }
        val rebuilt = SpannableStringBuilder(plain)
        var i = 0
        while (i < allFlags.size) {
            val f = allFlags[i]
            var j = i + 1
            while (j < allFlags.size && allFlags[j] == f) j++
            applyFlags(rebuilt, i, j, f, linkColor)
            i = j
        }
        edit.setText(rebuilt)
        edit.setSelection(start, end)
    }
}
