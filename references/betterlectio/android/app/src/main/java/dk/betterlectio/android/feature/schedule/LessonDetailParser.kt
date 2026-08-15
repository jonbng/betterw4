package dk.betterlectio.android.feature.schedule

import dk.betterlectio.android.core.lectio.scrape.AspNetForm
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Lesson detail page (aktivitetforside2.aspx).
 * iOS: [ScheduleParser.parseLessonContent] — homeworkContentContainer, ACH articles, sections.
 * Extension: [activity-detail.ts] — holdActLink / HE* for members.aspx.
 *
 * Participants are **not** on this page — load via [DirectoryRepository.loadMembers] using [LessonDetail.holdId].
 */
object LessonDetailParser {

    fun parse(html: String, eventId: String, fallbackTitle: String = ""): LessonDetail {
        val doc = Jsoup.parse(html)

        val homeworkContainer = doc.selectFirst("#homeworkContentContainer")
        // iOS: textarea.activity-note inside container (before empty-content early return)
        val note = homeworkContainer?.selectFirst("textarea.activity-note")
            ?.text()?.trim()?.ifBlank { null }
            ?: doc.getElementById("s_m_Content_Content_tocAndToolbar_ActNoteTB_tb")
                ?.text()?.trim()?.ifBlank { null }
            ?: doc.selectFirst("textarea[id*=ActNote], #m_Content_commentTextBox_tb")
                ?.text()?.trim()?.ifBlank { null }

        val holdId = parseHoldId(doc)
        val title = doc.selectFirst("#s_m_Content_Content_ActivityTitle, .ls-activity-title, h1")
            ?.text()?.trim()?.ifBlank { fallbackTitle } ?: fallbackTitle

        val inlineDiv = homeworkContainer
            ?.selectFirst("#s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv")
            ?: doc.getElementById("s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv")
            ?: homeworkContainer?.selectFirst("[id*=inlineHomework]")
            ?: doc.selectFirst("[id*=inlineHomework]")

        val blocks = mutableListOf<LessonContentBlock>()
        val resources = mutableListOf<LessonResource>()

        if (inlineDiv != null) {
            val empty = inlineDiv.text().contains("ikke noget indhold", ignoreCase = true)
            if (!empty) {
                parseInlineContent(inlineDiv, blocks, resources)
            }
        }

        val homework = blocks
            .filter { it.isHomework && it.kind != "heading" && it.kind != "divider" }
            .joinToString("\n") { it.text }
            .ifBlank { null }

        return LessonDetail(
            eventId = eventId,
            title = title,
            note = note,
            homework = homework,
            contentBlocks = blocks.distinctBy { it.kind + it.text + (it.url ?: "") },
            participants = emptyList(),
            resources = resources.distinctBy { it.url },
            holdId = holdId,
        )
    }

    /**
     * Extension: `#s_m_Content_Content_holdActLink` → holdelementid;
     * fallback: `data-lectiocontextcard="HE…"`.
     */
    fun parseHoldId(doc: org.jsoup.nodes.Document): String? {
        val holdHref = doc.selectFirst("#s_m_Content_Content_holdActLink")?.attr("href")
        val fromQuery = AspNetForm.queriesFromUrl(holdHref)["holdelementid"]
            ?.takeIf { it.isNotBlank() }
            ?.let { id -> if (id.startsWith("HE", ignoreCase = true)) id else "HE$id" }
        if (fromQuery != null) return fromQuery

        val card = doc.selectFirst("[data-lectiocontextcard^=HE], [data-lectiocontextcard^=he]")
            ?.attr("data-lectiocontextcard")
            ?.trim()
            ?.ifBlank { null }
        return card
    }

    private fun parseInlineContent(
        inlineDiv: Element,
        blocks: MutableList<LessonContentBlock>,
        resources: MutableList<LessonResource>,
    ) {
        var sectionIsHomework = true // iOS default before first heading
        var sawAch = false

        for (child in inlineDiv.children()) {
            val sectionHeading = child.selectFirst("h1.ls-paper-section-heading")
            if (sectionHeading != null) {
                val headingText = sectionHeading.text().trim()
                when {
                    headingText.equals("Lektier", ignoreCase = true) -> sectionIsHomework = true
                    headingText.equals("Øvrigt indhold", ignoreCase = true) -> sectionIsHomework = false
                    headingText.contains("Lektier", ignoreCase = true) -> sectionIsHomework = true
                    headingText.contains("Øvrigt", ignoreCase = true) -> sectionIsHomework = false
                }
                continue
            }

            val childId = child.id()
            if (childId.startsWith("ACH")) {
                val article = child.selectFirst("article.lc-display-fragment")
                    ?: child.selectFirst("article")
                if (article != null) {
                    sawAch = true
                    parseArticle(article, blocks, resources, sectionIsHomework)
                }
                continue
            }

            // ACP presentations (extension) — treat as other content
            if (childId.startsWith("ACP")) {
                val article = child.selectFirst("article.lc-display-fragment")
                    ?: child.selectFirst("article")
                if (article != null) {
                    sawAch = true
                    parseArticle(article, blocks, resources, isHomework = false)
                }
            }
        }

        // Fallback for fixtures / older markup without ACH wrappers
        if (!sawAch && blocks.isEmpty()) {
            for (child in inlineDiv.children()) {
                val tag = child.tagName().lowercase()
                val text = child.text().trim()
                when {
                    tag.matches(Regex("h[1-6]")) || child.hasClass("section-header") ||
                        child.hasClass("ls-paper-section-heading") -> {
                        when {
                            text.contains("Lektier", ignoreCase = true) -> sectionIsHomework = true
                            text.contains("Øvrigt", ignoreCase = true) -> sectionIsHomework = false
                        }
                    }
                    tag == "article" || child.hasClass("ls-paper") || child.hasClass("activity-content") ||
                        child.hasClass("lc-display-fragment") -> {
                        parseArticle(child, blocks, resources, sectionIsHomework)
                    }
                }
            }
            if (blocks.isEmpty()) {
                inlineDiv.select("article, .ls-paper, .activity-content, [id^=ACH]").forEach { article ->
                    val root = if (article.tagName().equals("article", ignoreCase = true)) {
                        article
                    } else {
                        article.selectFirst("article") ?: article
                    }
                    parseArticle(root, blocks, resources, sectionIsHomework)
                }
            }
        }
    }

    private fun parseArticle(
        article: Element,
        blocks: MutableList<LessonContentBlock>,
        resources: MutableList<LessonResource>,
        isHomework: Boolean = false,
    ) {
        val hasHwStyle = article.selectFirst("[style*=doc-homework]") != null
        val hasNotHwStyle = article.selectFirst("[style*=doc-not-homework]") != null
        val articleHw = when {
            article.className().contains("doc-not-homework") || hasNotHwStyle -> false
            article.className().contains("doc-homework") || (hasHwStyle && !hasNotHwStyle) -> true
            else -> isHomework
        }

        // Prefer title header (iOS: h2[id*=titleHeader] or first h1 with homework icon)
        val titleEl = article.selectFirst("h2[id*=titleHeader]")
            ?: article.selectFirst("h1[id], h1")
        titleEl?.text()?.trim()?.takeIf { it.isNotEmpty() }?.let { t ->
            blocks += LessonContentBlock("heading", t, isHomework = articleHw)
        }

        article.select("h1, h2, h3, h4, .ls-paper-header").forEach { h ->
            if (h === titleEl) return@forEach
            val t = h.text().trim()
            if (t.isNotEmpty()) blocks += LessonContentBlock("heading", t, isHomework = articleHw)
        }
        article.select("p, .ls-paper-content, li").forEach { p ->
            val t = p.text().trim()
            if (t.isNotEmpty()) blocks += LessonContentBlock("paragraph", t, isHomework = articleHw)
        }
        article.select("blockquote, [data-lc-role=note]").forEach { b ->
            val t = b.text().trim()
            if (t.isNotEmpty()) blocks += LessonContentBlock("note", t, isHomework = articleHw)
        }
        article.select("a[href]").forEach { a ->
            val href = a.attr("href")
            if (href.isBlank()) return@forEach
            resources += LessonResource(
                title = a.text().trim().ifBlank { href },
                url = absoluteUrl(href),
                isFile = a.attr("data-lc-display-linktype") == "file" ||
                    href.contains("GetFile", ignoreCase = true) ||
                    href.contains("document", ignoreCase = true),
            )
        }
        article.select("img[src]").forEach { img ->
            val src = img.attr("src")
            if (src.isBlank() || src.contains("/lectio/img/", ignoreCase = true)) return@forEach
            blocks += LessonContentBlock(
                kind = "image",
                text = img.attr("alt").ifBlank { "Billede" },
                url = absoluteUrl(src),
                isHomework = articleHw,
            )
        }
        article.select("hr").forEach {
            blocks += LessonContentBlock("divider", "", isHomework = articleHw)
        }
    }

    private fun absoluteUrl(href: String): String = when {
        href.startsWith("http") -> href
        href.startsWith("//") -> "https:$href"
        href.startsWith("/") -> "https://www.lectio.dk$href"
        else -> "https://www.lectio.dk/$href"
    }
}
