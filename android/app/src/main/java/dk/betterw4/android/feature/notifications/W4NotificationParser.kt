package dk.betterw4.android.feature.notifications

import dk.betterw4.android.core.FeatureFlags
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

enum class W4NotificationSeverity { NEW, OVERDUE, NORMAL }

enum class W4NotificationSection { TASK, EMAIL }

data class W4NotificationItem(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val href: String? = null,
    val type: String? = null,
    val section: W4NotificationSection,
    val severity: W4NotificationSeverity = W4NotificationSeverity.NORMAL,
)

data class W4NotificationGroup(
    val type: String?,
    val title: String,
    val severity: W4NotificationSeverity,
    val items: List<W4NotificationItem>,
)

data class W4NotificationSnapshot(
    val count: Int = 0,
    val severity: W4NotificationSeverity = W4NotificationSeverity.NORMAL,
    val taskGroups: List<W4NotificationGroup> = emptyList(),
    val emailGroups: List<W4NotificationGroup> = emptyList(),
) {
    val items: List<W4NotificationItem>
        get() = taskGroups.flatMap { it.items } + emailGroups.flatMap { it.items }

    val isEmpty: Boolean get() = items.isEmpty() && count <= 0

    /** Drops W4 mailer items when [FeatureFlags.MAIL_ENABLED] is off. */
    fun forDisplay(): W4NotificationSnapshot {
        if (FeatureFlags.MAIL_ENABLED) return this
        val hidden = emailGroups.sumOf { it.items.size }
        return copy(
            emailGroups = emptyList(),
            count = (count - hidden).coerceAtLeast(0),
        )
    }
}

/**
 * Parses chrome `div.notifications` and the AJAX fragment from `notifications/refresh`.
 *
 * Refresh replaces `$('#header div.notifications').html($(data).children())`, so the
 * payload may be a wrapper whose children are `.btn-group` / dropdown markup.
 */
object W4NotificationParser {

    fun parse(html: String): W4NotificationSnapshot {
        val doc = Jsoup.parse(html)
        val root = doc.selectFirst("div.notifications")
            ?: doc.selectFirst(".btn-group")?.parent()
            ?: doc.body()
        val alert = root.selectFirst(".btn-group .alert, .alert")
        val count = alert?.text()?.trim()?.toIntOrNull()
            ?: root.select("dd li a[data-notification-id], a.read[data-notification-id]")
                .mapNotNull { it.attr("data-notification-id").ifBlank { null } }
                .distinct()
                .size
        val severity = severityOf(alert)

        val taskGroups = parseSection(root, "h3.tasks", W4NotificationSection.TASK)
        val emailGroups = parseSection(root, "h3.emails", W4NotificationSection.EMAIL)
            .ifEmpty { parseEmailList(root) }

        return W4NotificationSnapshot(
            count = count,
            severity = severity,
            taskGroups = taskGroups,
            emailGroups = emailGroups,
        )
    }

    private fun parseSection(
        root: Element,
        headingSelector: String,
        section: W4NotificationSection,
    ): List<W4NotificationGroup> {
        val heading = root.selectFirst(headingSelector) ?: return emptyList()
        val dl = heading.nextElementSiblings().firstOrNull { it.tagName() == "dl" }
            ?: heading.parent()?.selectFirst("dl")
            ?: return emptyList()
        return parseDefinitionList(dl, section)
    }

    private fun parseEmailList(root: Element): List<W4NotificationGroup> {
        val dl = root.selectFirst("dl.email-list") ?: return emptyList()
        return parseDefinitionList(dl, W4NotificationSection.EMAIL)
    }

    private fun parseDefinitionList(
        dl: Element,
        section: W4NotificationSection,
    ): List<W4NotificationGroup> {
        val groups = mutableListOf<W4NotificationGroup>()
        var currentDt: Element? = null
        val pendingItems = mutableListOf<W4NotificationItem>()

        fun flush() {
            val dt = currentDt ?: return
            val type = dt.selectFirst("a.read[data-notification-type], a.clear[data-notification-type]")
                ?.attr("data-notification-type")
                ?.ifBlank { null }
                ?: dt.attr("data-notification-type").ifBlank { null }
            val title = dt.ownText().ifBlank { dt.text() }
                .replace(Regex("""\b(read|clear)\b""", RegexOption.IGNORE_CASE), "")
                .trim()
                .ifBlank { if (section == W4NotificationSection.EMAIL) "Emails" else "Tasks" }
            groups += W4NotificationGroup(
                type = type,
                title = title,
                severity = severityOf(dt),
                items = pendingItems.toList(),
            )
            pendingItems.clear()
            currentDt = null
        }

        for (child in dl.children()) {
            when (child.tagName()) {
                "dt" -> {
                    flush()
                    currentDt = child
                }
                "dd" -> {
                    for (li in child.select("li")) {
                        parseItem(li, section, currentDt)?.let { pendingItems += it }
                    }
                }
            }
        }
        flush()
        return groups
    }

    private fun parseItem(
        li: Element,
        section: W4NotificationSection,
        dt: Element?,
    ): W4NotificationItem? {
        val read = li.selectFirst("a.read[data-notification-id]")
        val id = read?.attr("data-notification-id")?.ifBlank { null }
            ?: li.selectFirst("[data-notification-id]")?.attr("data-notification-id")?.ifBlank { null }
            ?: return null
        val titleLink = li.select("a[href]")
            .firstOrNull { !it.hasClass("read") && !it.hasClass("clear") }
            ?: li.selectFirst("a")
        val title = titleLink?.ownText()?.ifBlank { titleLink.text() }
            ?.trim()
            .orEmpty()
            .ifBlank { id }
        val href = titleLink?.attr("href")?.ifBlank { null }
        val type = read?.attr("data-notification-type")?.ifBlank { null }
            ?: dt?.selectFirst("[data-notification-type]")?.attr("data-notification-type")?.ifBlank { null }
            ?: dt?.attr("data-notification-type")?.ifBlank { null }
        val subtitle = li.selectFirst(".deadline, .date, span")?.text()?.trim()?.takeIf { it.isNotBlank() && it != title }
        return W4NotificationItem(
            id = id,
            title = title,
            subtitle = subtitle,
            href = href,
            type = type,
            section = section,
            severity = severityOf(li),
        )
    }

    private fun severityOf(el: Element?): W4NotificationSeverity = when {
        el == null -> W4NotificationSeverity.NORMAL
        el.hasClass("overdue") -> W4NotificationSeverity.OVERDUE
        el.hasClass("new") -> W4NotificationSeverity.NEW
        else -> W4NotificationSeverity.NORMAL
    }
}
