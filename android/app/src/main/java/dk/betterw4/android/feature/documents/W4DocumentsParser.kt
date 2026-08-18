package dk.betterw4.android.feature.documents

import dk.betterw4.android.core.w4.W4Urls
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

enum class W4DocumentKind { FOLDER, PAGE }

data class W4DocumentNode(
    val id: String,
    val title: String,
    val kind: W4DocumentKind,
    val href: String,
    val route: String? = null,
)

data class W4DocumentListing(
    val title: String,
    val items: List<W4DocumentNode>,
    val bodyHtml: String? = null,
    val isPage: Boolean = false,
    val breadcrumb: List<W4DocumentNode> = emptyList(),
)

/**
 * Documents CMS parser matching iOS `W4DocumentsParser`.
 *
 * Bug B16: a page is `.page-content`. The old "no folder links ⇒ this is a page"
 * heuristic is a last resort, and an empty `ul.folder-list` is an empty folder.
 */
object W4DocumentsParser {
    private val FOLDER_ID = Regex("""folder_id=(\d+)""")
    private val PAGE_ID = Regex("""page_id=(\d+)""")

    fun parse(html: String): W4DocumentListing {
        val doc = Jsoup.parse(html)
        doc.outputSettings().prettyPrint(false)
        val inner = doc.getElementById("content_inner")
        val root = inner ?: doc.body()
        val items = parseItems(root)
        val title = parseTitle(root, doc)
        val page = parsePage(root, items, hasContentInner = inner != null)
        return W4DocumentListing(
            title = title.ifBlank { "Documents" },
            items = items,
            bodyHtml = page,
            isPage = page != null,
            breadcrumb = parseBreadcrumb(doc),
        )
    }

    private fun parseTitle(root: Element, document: Document): String {
        for (sel in listOf(".page-title", "h1", "h2", "h3")) {
            root.selectFirst(sel)?.text()?.trim()?.ifBlank { null }?.let { return it }
        }
        return document.title().trim()
    }

    private fun parseItems(root: Element): List<W4DocumentNode> {
        var anchors = root.select(".folder-list a[href]")
        if (anchors.isEmpty()) anchors = root.select("a.folder[href], a.page[href]")
        val nodes = mutableListOf<W4DocumentNode>()
        val indexByHref = mutableMapOf<String, Int>()
        for (anchor in anchors) {
            val node = documentNode(anchor) ?: continue
            val existing = indexByHref[node.href]
            if (existing != null) {
                if (nodes[existing].title.isEmpty() && node.title.isNotEmpty()) {
                    nodes[existing] = node
                }
                continue
            }
            indexByHref[node.href] = nodes.size
            nodes += node
        }
        return nodes
    }

    private fun documentNode(anchor: Element): W4DocumentNode? {
        val href = anchor.attr("href").trim()
        if (href.isEmpty()) return null
        val kind = when {
            anchor.hasClass("folder") -> W4DocumentKind.FOLDER
            anchor.hasClass("page") -> W4DocumentKind.PAGE
            PAGE_ID.containsMatchIn(href) -> W4DocumentKind.PAGE
            FOLDER_ID.containsMatchIn(href) -> W4DocumentKind.FOLDER
            else -> W4DocumentKind.FOLDER
        }
        val preferred = if (kind == W4DocumentKind.PAGE) PAGE_ID else FOLDER_ID
        val other = if (kind == W4DocumentKind.PAGE) FOLDER_ID else PAGE_ID
        val id = preferred.find(href)?.groupValues?.get(1)
            ?: other.find(href)?.groupValues?.get(1)
            ?: href
        val title = anchor.text().trim()
            .ifBlank { anchor.attr("title").trim() }
            .ifBlank { anchor.selectFirst("img[alt]")?.attr("alt")?.trim().orEmpty() }
        return W4DocumentNode(
            id = id,
            title = title,
            kind = kind,
            href = href,
            route = W4Urls.routeOf(href),
        )
    }

    private fun parsePage(
        root: Element,
        items: List<W4DocumentNode>,
        hasContentInner: Boolean,
    ): String? {
        val content = root.selectFirst(".page-content")
        if (content != null) return content.html().trim().ifBlank { null }

        if (!hasContentInner) return null
        if (items.isNotEmpty()) return null
        if (root.selectFirst(".folder-list") != null) return null

        val leftover = leftoverContent(root)
        if (leftover.isBlank()) return null
        return leftover
    }

    private fun leftoverContent(root: Element): String {
        val clone = root.clone()
        clone.select("h1, h2, h3").first()?.remove()
        clone.select("script, style, noscript, .up, .new, #breadcrumb").remove()
        return clone.html().trim()
    }

    private fun parseBreadcrumb(document: Document): List<W4DocumentNode> {
        var anchors = document.select("#breadcrumb .crumbs a[href]")
        if (anchors.isEmpty()) anchors = document.select(".crumbs a[href]")
        return anchors.mapNotNull { anchor ->
            if (anchor.hasClass("help")) return@mapNotNull null
            val href = anchor.attr("href")
            val title = anchor.text().trim()
            if (href.isEmpty() && title.isEmpty()) return@mapNotNull null
            W4DocumentNode(
                id = href,
                title = title,
                kind = W4DocumentKind.FOLDER,
                href = href,
                route = W4Urls.routeOf(href),
            )
        }
    }
}
