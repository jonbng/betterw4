package dk.betterlectio.android.core.lectio.scrape

import org.jsoup.Jsoup

/**
 * Builds robust ASP.NET postback field maps from a live Lectio HTML page.
 * Prefer real form field names present on the page over hard-coded guesses.
 */
object SmartPostback {

    data class ResolvedPost(
        val eventTarget: String,
        val fields: Map<String, String>,
        val matchedBy: String,
    )

    /**
     * Resolve [preferredTargets] against buttons/links on the page; fall back to first preferred.
     * Merges all form fields + ASP.NET viewstate + [extra].
     */
    fun resolve(
        html: String,
        preferredTargets: List<String>,
        extra: Map<String, String> = emptyMap(),
        nameContainsAny: List<String> = emptyList(),
    ): ResolvedPost {
        val doc = Jsoup.parse(html)
        val allNamed = AspNetForm.parseAllFormFields(html).toMap().toMutableMap()

        // Prefer a target that actually exists as name/id on the page
        var matchedBy = "preferred_first"
        var eventTarget = preferredTargets.firstOrNull().orEmpty()

        val namedEls = doc.select("input[name], button[name], select[name], textarea[name], a[href]")
        for (pref in preferredTargets) {
            val exact = namedEls.firstOrNull { el ->
                el.attr("name") == pref || el.attr("id") == pref
            }
            if (exact != null) {
                eventTarget = pref
                matchedBy = "exact_name_or_id"
                break
            }
            // Suffix match: Lectio sometimes prefixes master content ids differently
            val short = pref.substringAfterLast('$')
            val hit = namedEls.firstOrNull { el ->
                val n = el.attr("name")
                val href = el.attr("href")
                (short.isNotBlank() && n.endsWith(short)) ||
                    n.contains(pref.takeLast(24)) ||
                    href.contains(pref) ||
                    (short.isNotBlank() && href.contains(short))
            }
            if (hit != null) {
                eventTarget = hit.attr("name").ifBlank {
                    Regex("""__doPostBack\('([^']+)'""").find(hit.attr("href"))
                        ?.groupValues?.get(1)
                        ?: pref
                }
                matchedBy = "suffix_or_dopostback"
                break
            }
        }

        if (matchedBy == "preferred_first" && nameContainsAny.isNotEmpty()) {
            val hit = doc.select("input[name], button[name], a[href*='__doPostBack']")
                .firstOrNull { el ->
                    val blob = (el.attr("name") + el.attr("href") + el.attr("id") + el.text())
                        .lowercase()
                    nameContainsAny.any { blob.contains(it.lowercase()) }
                }
            if (hit != null) {
                eventTarget = hit.attr("name").ifBlank {
                    Regex("""__doPostBack\('([^']+)'""").find(hit.attr("href"))
                        ?.groupValues?.get(1)
                        ?: eventTarget
                }
                matchedBy = "keyword"
            }
        }

        val asp = AspNetForm.extractAspData(html, eventTarget)
        allNamed.putAll(asp)
        allNamed.putAll(extra)
        allNamed["__EVENTTARGET"] = eventTarget
        return ResolvedPost(eventTarget = eventTarget, fields = allNamed, matchedBy = matchedBy)
    }

    /**
     * Find textarea/input whose name matches any of [patterns] (case-insensitive contains).
     */
    fun findFieldName(html: String, patterns: List<String>): String? {
        val fields = AspNetForm.parseAllFormFields(html)
        for (pattern in patterns) {
            val p = pattern.lowercase()
            fields.firstOrNull { it.first.lowercase().contains(p) }?.let { return it.first }
        }
        return null
    }

    /** Current value of a named form field if present on the page. */
    fun existingFieldValue(html: String, fieldName: String): String? {
        if (fieldName.isBlank()) return null
        return AspNetForm.parseAllFormFields(html)
            .firstOrNull { it.first == fieldName }
            ?.second
    }

    private fun cssEscape(name: String): String =
        // Jsoup attribute selector: escape $ as they are special in CSS
        name.replace("\\", "\\\\").replace("$", "\\$")
}
