package dk.betterlectio.android.feature.content

import dk.betterlectio.android.feature.attachments.AttachmentClassifier
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode

/**
 * Structured pieces of Lectio HTML bodies (messages, homework snippets, lesson articles).
 * Images are first-class so UI can load them with the cookie-aware Coil ImageLoader.
 */
sealed class LectioHtmlSegment {
    data class Text(val html: String) : LectioHtmlSegment()
    data class Image(val url: String, val alt: String) : LectioHtmlSegment()
    data object Divider : LectioHtmlSegment()
}

object LectioHtmlSegments {

    /**
     * Walk a Lectio HTML fragment and emit text chunks (as HTML for [androidx.core.text.HtmlCompat])
     * interleaved with images / horizontal rules.
     *
     * Skips Lectio chrome icons under `/lectio/img/` and empty alt-only spacers.
     */
    fun parse(html: String?): List<LectioHtmlSegment> {
        if (html.isNullOrBlank()) return emptyList()
        val body = Jsoup.parseBodyFragment(html).body() ?: return emptyList()
        // Drop attachment blocks — UI renders them via AttachmentChip separately.
        body.select(".message-attachements, .message-attachments").remove()
        val out = mutableListOf<LectioHtmlSegment>()
        val textBuf = StringBuilder()

        fun flushText() {
            val raw = textBuf.toString()
            textBuf.clear()
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) return
            // Avoid pure-whitespace / empty tags after trim of entity-only runs
            val plain = Jsoup.parseBodyFragment(trimmed).text().trim()
            if (plain.isEmpty()) return
            out += LectioHtmlSegment.Text(trimmed)
        }

        fun walk(node: Node) {
            when (node) {
                is TextNode -> {
                    val t = node.wholeText
                    if (t.isNotEmpty()) textBuf.append(escapeText(t))
                }
                is Element -> {
                    when (node.tagName().lowercase()) {
                        "img" -> {
                            flushText()
                            val src = node.attr("src").trim()
                            if (src.isNotEmpty() && !isChromeIcon(src)) {
                                out += LectioHtmlSegment.Image(
                                    url = AttachmentClassifier.absolutize(src),
                                    alt = node.attr("alt").ifBlank { "Billede" },
                                )
                            }
                        }
                        "hr" -> {
                            flushText()
                            out += LectioHtmlSegment.Divider
                        }
                        "br" -> textBuf.append("<br/>")
                        "script", "style", "noscript" -> Unit
                        else -> {
                            val tag = node.tagName().lowercase()
                            val isBlock = tag in blockTags
                            if (isBlock && textBuf.isNotEmpty()) textBuf.append("<br/>")
                            // Preserve common inline formatting as HTML for HtmlCompat.
                            val open = openTag(node)
                            val close = closeTag(node)
                            if (open != null) textBuf.append(open)
                            node.childNodes().forEach { walk(it) }
                            if (close != null) textBuf.append(close)
                            if (isBlock) textBuf.append("<br/>")
                        }
                    }
                }
            }
        }

        body.childNodes().forEach { walk(it) }
        flushText()
        return mergeAdjacentText(out)
    }

    /**
     * Collect image URLs only (absolute), for surfaces that already show plain text separately.
     */
    fun extractImageUrls(html: String?): List<String> =
        parse(html).mapNotNull { (it as? LectioHtmlSegment.Image)?.url }.distinct()

    private val blockTags = setOf(
        "p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6",
        "tr", "table", "blockquote", "section", "article", "header", "footer",
    )

    private fun isChromeIcon(src: String): Boolean =
        src.contains("/lectio/img/", ignoreCase = true) ||
            src.contains("spacer", ignoreCase = true) ||
            src.endsWith(".gif") && src.contains("pixel", ignoreCase = true)

    private fun openTag(el: Element): String? {
        val tag = el.tagName().lowercase()
        val classes = el.classNames()
        return when {
            tag == "b" || tag == "strong" || classes.contains("bb_b") -> "<b>"
            tag == "i" || tag == "em" || classes.contains("bb_i") -> "<i>"
            tag == "u" || classes.contains("bb_u") -> "<u>"
            tag == "a" && el.hasAttr("href") -> {
                val href = el.attr("href").trim()
                if (href.isEmpty()) null
                else """<a href="${escapeAttr(AttachmentClassifier.absolutize(href))}">"""
            }
            tag == "li" -> "• "
            else -> null
        }
    }

    private fun closeTag(el: Element): String? {
        val tag = el.tagName().lowercase()
        val classes = el.classNames()
        return when {
            tag == "b" || tag == "strong" || classes.contains("bb_b") -> "</b>"
            tag == "i" || tag == "em" || classes.contains("bb_i") -> "</i>"
            tag == "u" || classes.contains("bb_u") -> "</u>"
            tag == "a" && el.hasAttr("href") && el.attr("href").isNotBlank() -> "</a>"
            else -> null
        }
    }

    private fun escapeText(raw: String): String =
        raw.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")

    private fun escapeAttr(raw: String): String =
        raw.replace("&", "&amp;")
            .replace("\"", "&quot;")
            .replace("<", "&lt;")

    private fun mergeAdjacentText(segments: List<LectioHtmlSegment>): List<LectioHtmlSegment> {
        if (segments.isEmpty()) return segments
        val out = mutableListOf<LectioHtmlSegment>()
        val buf = StringBuilder()
        fun flush() {
            if (buf.isEmpty()) return
            out += LectioHtmlSegment.Text(buf.toString())
            buf.clear()
        }
        for (seg in segments) {
            when (seg) {
                is LectioHtmlSegment.Text -> {
                    if (buf.isNotEmpty()) buf.append("<br/>")
                    buf.append(seg.html)
                }
                else -> {
                    flush()
                    out += seg
                }
            }
        }
        flush()
        return out
    }
}
