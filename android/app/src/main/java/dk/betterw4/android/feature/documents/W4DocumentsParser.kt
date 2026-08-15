package dk.betterw4.android.feature.documents

import org.jsoup.Jsoup

enum class W4DocumentKind { FOLDER, PAGE }

data class W4DocumentNode(
    val id: String,
    val title: String,
    val kind: W4DocumentKind,
    val href: String,
)

data class W4DocumentListing(
    val title: String,
    val items: List<W4DocumentNode>,
    val bodyHtml: String? = null,
    val isPage: Boolean = false,
)

object W4DocumentsParser {
    private val FOLDER_ID = Regex("""folder_id=(\d+)""")
    private val PAGE_ID = Regex("""page_id=(\d+)""")

    fun parse(html: String): W4DocumentListing {
        val doc = Jsoup.parse(html)
        val inner = doc.getElementById("content_inner") ?: doc.body()
        val heading = inner.selectFirst("h1, h2")?.text()?.trim().orEmpty()
        val folders = inner.select("a.folder").mapNotNull { a ->
            val href = a.attr("href")
            val id = FOLDER_ID.find(href)?.groupValues?.get(1) ?: return@mapNotNull null
            W4DocumentNode(id = id, title = a.text().trim(), kind = W4DocumentKind.FOLDER, href = href)
        }
        val pages = inner.select("a.page").mapNotNull { a ->
            val href = a.attr("href")
            val id = PAGE_ID.find(href)?.groupValues?.get(1) ?: return@mapNotNull null
            W4DocumentNode(id = id, title = a.text().trim(), kind = W4DocumentKind.PAGE, href = href)
        }
        val isPage = folders.isEmpty() && pages.isEmpty() && heading.isNotBlank()
        val body = if (isPage) {
            inner.clone().apply {
                select("h1, h2").first()?.remove()
            }.html().trim().ifBlank { null }
        } else {
            null
        }
        return W4DocumentListing(
            title = heading.ifBlank { "Documents" },
            items = folders + pages,
            bodyHtml = body,
            isPage = isPage,
        )
    }
}
