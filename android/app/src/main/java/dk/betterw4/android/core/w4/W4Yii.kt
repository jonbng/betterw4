package dk.betterw4.android.core.w4

import org.jsoup.nodes.Element

/**
 * Yii 1 grid empty-state detection (bug B9).
 *
 * Empty result rows are `td.empty`, `span.empty`, and/or the literal
 * "No results found." — not only `td.empty`.
 */
object W4Yii {
    fun isEmptyRow(row: Element): Boolean {
        if (row.selectFirst("td.empty, span.empty") != null) return true
        val text = row.text().trim()
        return text.equals("No results found.", ignoreCase = true)
    }
}
