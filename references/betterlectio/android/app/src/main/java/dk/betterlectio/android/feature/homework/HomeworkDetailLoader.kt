package dk.betterlectio.android.feature.homework

/**
 * Pure merge of list homework item with fetched lesson HTML / detail content.
 */
object HomeworkDetailLoader {
    fun mergeDetail(item: HomeworkItem, htmlOrText: String?): HomeworkItem {
        if (htmlOrText.isNullOrBlank()) return item
        return item.copy(detailHtml = htmlOrText)
    }

    fun plainTextFromHtml(html: String): String =
        html
            .replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), "\n")
            .replace(Regex("</p>", RegexOption.IGNORE_CASE), "\n\n")
            .replace(Regex("<[^>]+>"), "")
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .trim()

    fun hasLinkedContent(item: HomeworkItem): Boolean =
        !item.href.isNullOrBlank() || !item.detailHtml.isNullOrBlank()
}
