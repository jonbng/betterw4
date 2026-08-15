package dk.betterlectio.android.core.lectio.scrape

import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/**
 * ASP.NET WebForms helpers for Lectio postbacks.
 * Dart parity: lectio_wrapper utils/scraping.extractASPData
 * iOS parity: BaseParser.parseAllFormFields
 */
object AspNetForm {

    private val aspFieldIds = listOf(
        "__VIEWSTATEX",
        "__EVENTVALIDATION",
        "__EVENTARGUMENT",
        "__SCROLLPOSITION",
        "__VIEWSTATEY_KEY",
        "__VIEWSTATE",
        "masterfootervalue",
    )

    /**
     * Builds the standard ASP.NET postback field map for [eventTarget].
     */
    fun extractAspData(html: String, eventTarget: String): Map<String, String> {
        val doc = Jsoup.parse(html)
        return extractAspData(doc, eventTarget)
    }

    fun extractAspData(doc: Document, eventTarget: String): Map<String, String> {
        val data = linkedMapOf<String, String>()
        data["__EVENTTARGET"] = eventTarget
        for (name in aspFieldIds) {
            val el = doc.getElementById(name) ?: doc.selectFirst("[name=$name]")
            data[name] = el?.attr("value").orEmpty()
        }
        return data
    }

    /**
     * All named form fields (inputs/selects/textareas), excluding checkboxes and submits.
     */
    fun parseAllFormFields(html: String): List<Pair<String, String>> {
        val doc = Jsoup.parse(html)
        val fields = mutableListOf<Pair<String, String>>()

        for (input in doc.select("input[name]")) {
            val type = input.attr("type").lowercase()
            if (type == "checkbox" || type == "submit") continue
            fields += input.attr("name") to input.attr("value")
        }

        for (select in doc.select("select[name]")) {
            val name = select.attr("name")
            val selected = select.selectFirst("option[selected]")
                ?: select.selectFirst("option")
            fields += name to (selected?.attr("value").orEmpty())
        }

        for (textarea in doc.select("textarea[name]")) {
            fields += textarea.attr("name") to textarea.text()
        }

        return fields
    }

    fun queriesFromUrl(url: String?): Map<String, String> {
        if (url.isNullOrBlank()) return emptyMap()
        val qIndex = url.indexOf('?')
        if (qIndex < 0 || qIndex >= url.lastIndex) return emptyMap()
        val query = url.substring(qIndex + 1).removeSuffix("#")
        return query.split('&')
            .mapNotNull { part ->
                val eq = part.indexOf('=')
                if (eq <= 0) null
                else part.substring(0, eq) to part.substring(eq + 1)
            }
            .toMap()
    }
}
