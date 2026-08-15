package dk.betterlectio.android.feature.homework

import dk.betterlectio.android.core.util.LectioDateUtils
import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleParser
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.TextNode

/**
 * Homework overview — iOS [ScheduleParser.parseHomeworkOverview] + Flutter absid ids.
 */
object HomeworkParser {
    fun parse(html: String): List<HomeworkItem> {
        val doc = Jsoup.parse(html)
        val table = doc.getElementById("s_m_Content_Content_MaterialLektieOverblikGV")
            ?: doc.selectFirst("table[id*=Lektie]")
            ?: return emptyList()
        val rows = table.select("tr")
        return rows.mapNotNull { row ->
            // Skip header
            if (row.select("th").isNotEmpty()) return@mapNotNull null

            // iOS: desktop columns only (mobile duplicates shift indices)
            val cells = desktopCells(row)
            if (cells.size < 3) return@mapNotNull null

            val dateRaw = cells[0].text().trim()
            val date = LectioDateUtils.parseLectioDate(dateRaw)?.toLocalDate()
                ?: LectioDateUtils.parseWeekdayPrefixedDate(dateRaw)

            val activity = cells[1].selectFirst("a.s2skemabrik, a.s2bgbox")
                ?: row.selectFirst("a.s2skemabrik, a.s2bgbox")
                ?: return@mapNotNull null

            val href = activity.attr("href").ifBlank { null }
            val tooltip = activity.attr("data-tooltip")
            val tip = if (tooltip.isNotBlank()) {
                ScheduleParser.parseTooltip(tooltip, date ?: java.time.LocalDate.now())
            } else {
                null
            }

            val brikId = activity.attr("data-brikid")
                .removePrefix("ABS")
                .takeIf { it.isNotBlank() }
            val absid = href?.let { h ->
                Regex("""absid=(\d+)""").find(h)?.groupValues?.get(1)
            }
            val id = absid ?: brikId ?: return@mapNotNull null

            val status = when {
                activity.hasClass("s2cancelled") -> EventStatus.CANCELLED
                activity.hasClass("s2changed") -> EventStatus.CHANGED
                else -> EventStatus.NORMAL
            }

            val (note, tasks) = parseContentCell(cells[2], id)
            val linkTitle = activity.text().trim()
            val title = tip?.title?.takeIf { it.isNotBlank() && it != "Modul" }
                ?: tip?.freeTitle
                ?: linkTitle
                ?: "Lektie"
            val team = tip?.holdName.orEmpty()

            if (note.isBlank() && tasks.isEmpty() && title.isBlank()) return@mapNotNull null

            HomeworkItem(
                id = id,
                note = note.ifBlank { tasks.joinToString("\n") { it.text } },
                activityTitle = title,
                date = date,
                team = team,
                teacher = tip?.teacher,
                room = tip?.room,
                status = status,
                href = href,
                tasks = tasks,
            )
        }
    }

    /** Prefer `td.OnlyDesktop`, else non-mobile, else all `td` (fixtures). */
    internal fun desktopCells(row: Element): List<Element> {
        val desktop = row.select("td.OnlyDesktop")
        if (desktop.isNotEmpty()) return desktop
        val nonMobile = row.select("td:not(.OnlyMobile)")
        if (nonMobile.isNotEmpty()) return nonMobile
        return row.select("td")
    }

    /**
     * iOS parseHomeworkContentCell — note text + doc-homework items.
     * Falls back to plain cell text for simple fixtures.
     */
    internal fun parseContentCell(cell: Element, absId: String): Pair<String, List<HomeworkTask>> {
        val hasHomeworkIcon = cell.select("img[src*=doc-homework]").isNotEmpty()
        if (!hasHomeworkIcon && cell.select("a").isEmpty() && cell.select("div.ls-homework-note").isEmpty()) {
            return cell.text().trim() to emptyList()
        }

        val items = mutableListOf<HomeworkTask>()
        val noteParts = mutableListOf<String>()
        var currentText = StringBuilder()
        var itemIndex = 0

        fun flushNote() {
            val t = currentText.toString().trim()
            if (t.isNotEmpty() && items.isEmpty()) noteParts += t
            currentText = StringBuilder()
        }

        for (child in cell.childNodes()) {
            when (child) {
                is Element -> when (child.tagName().lowercase()) {
                    "br" -> flushNote()
                    "img" -> {
                        // Marker for following homework text/link
                    }
                    "a" -> {
                        val text = child.text().trim()
                        if (text.isEmpty()) continue
                        val href = child.attr("href")
                        val prev = child.previousSibling()
                        val prevIsHw = prev is Element &&
                            prev.tagName().equals("img", true) &&
                            prev.attr("src").contains("doc-homework")
                        val isHw = prevIsHw || hasHomeworkIcon
                        if (isHw) {
                            flushNote()
                            val url = when {
                                href.isBlank() -> null
                                href.startsWith("http") -> href
                                else -> href
                            }
                            items += HomeworkTask(id = "${absId}_$itemIndex", text = text, url = url)
                            itemIndex++
                        } else {
                            noteParts += text
                        }
                    }
                    "div" -> {
                        if (child.hasClass("ls-homework-note")) {
                            val noteText = child.text().trim()
                            if (noteText.isNotEmpty() && items.isNotEmpty()) {
                                val last = items.last()
                                items[items.lastIndex] = last.copy(text = "${last.text} ($noteText)")
                            }
                        } else {
                            val text = child.text().trim()
                            if (text.isNotEmpty()) currentText.append(text)
                        }
                    }
                    else -> {
                        val text = child.text().trim()
                        if (text.isNotEmpty()) currentText.append(text)
                    }
                }
                is TextNode -> {
                    val text = child.wholeText.trim()
                    if (text.isEmpty()) continue
                    val prev = child.previousSibling()
                    val prevIsHw = prev is Element &&
                        prev.tagName().equals("img", true) &&
                        prev.attr("src").contains("doc-homework")
                    if (prevIsHw) {
                        flushNote()
                        items += HomeworkTask(id = "${absId}_$itemIndex", text = text, url = null)
                        itemIndex++
                    } else if (items.isEmpty()) {
                        currentText.append(text)
                    }
                }
            }
        }
        flushNote()

        val note = noteParts.joinToString("\n").ifBlank {
            if (items.isEmpty()) cell.text().trim() else ""
        }
        return note to items
    }
}
