package dk.betterlectio.android.feature.messages

import org.jsoup.Jsoup

internal object MessageEditProtocol {
    data class Fields(
        val titleField: String,
        val bodyField: String,
        val saveTarget: String,
        val title: String,
        val body: String,
    )

    fun parseFields(html: String, editTarget: String): Fields? {
        val prefix = editTarget.removeSuffix("\$EditModeToggleBtn")
        if (prefix == editTarget) return null
        val doc = Jsoup.parse(html)
        val body = doc.select("textarea[name*=EditModeContentBBTB]")
            .firstOrNull { it.attr("name").startsWith("$prefix\$") } ?: return null
        val title = doc.select("input[name*=EditModeHeaderTitleTB]")
            .firstOrNull { it.attr("name").startsWith("$prefix\$") } ?: return null
        val row = body.closest("tr") ?: body.parent()
        val targets = row?.select("a[onclick*=__doPostBack], a[href*=__doPostBack]")
            .orEmpty()
            .mapNotNull { element ->
                Regex("""__doPostBack\('([^']+)'""")
                    .find(element.attr("onclick") + element.attr("href"))
                    ?.groupValues?.get(1)
            }
        val saveTarget = targets.firstOrNull {
            it.startsWith("$prefix\$") && Regex("\\$(Send|Save|Update)MessageBtn$", RegexOption.IGNORE_CASE).containsMatchIn(it)
        } ?: return null
        return Fields(
            titleField = title.attr("name"),
            bodyField = body.attr("name"),
            saveTarget = saveTarget,
            title = title.attr("value"),
            body = body.`val`(),
        )
    }

    fun formAction(html: String, fallback: String): String =
        Jsoup.parse(html).selectFirst("form[action]")
            ?.attr("action")
            ?.takeIf { it.isNotBlank() }
            ?: fallback

    fun splitSignature(body: String): Pair<String, String> {
        val pattern = Regex(
            """(\n\n\[url=https://betterlectio\.dk/download]Sendt med BetterLectio\[/url])\s*$""",
            RegexOption.IGNORE_CASE,
        )
        val match = pattern.find(body) ?: return body to ""
        return body.substring(0, match.range.first) to match.groupValues[1]
    }
}
