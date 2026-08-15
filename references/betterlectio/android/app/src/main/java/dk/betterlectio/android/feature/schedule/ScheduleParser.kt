package dk.betterlectio.android.feature.schedule

import dk.betterlectio.android.core.util.LectioDateUtils
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.security.MessageDigest
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Pure HTML → schedule models.
 *
 * Primary parity target: **iOS** `ScheduleParser` (table.s2skema / data-date / tooltip rules).
 * Secondary: Flutter `weeks/scraping` (legacy containers, icons, ProeveholdId).
 */
object ScheduleParser {

    private val dateAttrFmt = DateTimeFormatter.ofPattern("d/M-yyyy", Locale.ROOT)
    private val isoDateFmt = DateTimeFormatter.ISO_LOCAL_DATE

    fun parseWeek(html: String, year: Int, week: Int): ScheduleWeek {
        val doc = Jsoup.parse(html)
        val table = doc.selectFirst("table.s2skema")
            ?: return ScheduleWeek(year, week, emptyList())

        val dayColumns = table.select("td[data-date]")
        if (dayColumns.isEmpty()) {
            return parseLegacyWeek(html, year, week)
        }

        val days = mutableListOf<ScheduleDay>()
        val dateByCol = mutableMapOf<Int, LocalDate>()

        for (col in dayColumns) {
            val dateStr = col.attr("data-date")
            val date = parseDataDate(dateStr) ?: continue
            dateByCol[col.elementSiblingIndex()] = date
            val events = col.select("a.s2skemabrik.s2brik, a.s2skemabrik.s2bgbox, a.s2bgbox")
                .mapNotNull { parseBrick(it, date) }
            days += ScheduleDay(date = date, events = events)
        }

        // All-day info row (iOS) + non–Hele-dagen info chips → day.informations (Flutter)
        dayColumns.firstOrNull()?.parent()?.previousElementSibling()?.let { infoRow ->
            for (cell in infoRow.children()) {
                if (!cell.hasClass("s2infoHeader")) continue
                val date = dateByCol[cell.elementSiblingIndex()] ?: continue
                val informations = mutableListOf<String>()
                val allDay = mutableListOf<ScheduleEvent>()
                for (brick in cell.select("a.s2skemabrik")) {
                    val tip = brick.attr("data-tooltip")
                    if (tip.contains("Hele dagen", ignoreCase = true)) {
                        parseBrick(brick, date)?.copy(isAllDay = true)?.let { allDay += it }
                    } else {
                        val text = brick.text().trim()
                        if (text.isNotEmpty()) informations += text
                    }
                }
                val idx = days.indexOfFirst { it.date == date }
                if (idx >= 0) {
                    days[idx] = days[idx].copy(
                        events = allDay + days[idx].events,
                        informations = informations,
                    )
                }
            }
        }

        return ScheduleMultiDay.expandWeek(ScheduleWeek(year, week, days.sortedBy { it.date }))
    }

    /** Flutter-style tbody fallback when data-date columns missing. */
    private fun parseLegacyWeek(html: String, year: Int, week: Int): ScheduleWeek {
        val doc = Jsoup.parse(html)
        val containers = doc.select("div.s2skemabrikcontainer")
        if (containers.size < 2) return ScheduleWeek(year, week, emptyList())

        val titles = doc.select("tr.s2dayHeader td").drop(1).map { it.text() }
        val dayContainers = containers.drop(1)
        val days = mutableListOf<ScheduleDay>()
        for (i in dayContainers.indices) {
            val title = titles.getOrNull(i).orEmpty()
            val dm = Regex("""(\d{1,2})/(\d{1,2})""").find(title)
            val date = if (dm != null) {
                runCatching {
                    LocalDate.of(year, dm.groupValues[2].toInt(), dm.groupValues[1].toInt())
                }.getOrElse {
                    LectioDateUtils.weekStart(year, week).plusDays(i.toLong())
                }
            } else {
                LectioDateUtils.weekStart(year, week).plusDays(i.toLong())
            }
            val events = dayContainers[i].select("a.s2bgbox, a.s2skemabrik")
                .mapNotNull { parseBrick(it, date) }
            days += ScheduleDay(date, events)
        }
        return ScheduleMultiDay.expandWeek(ScheduleWeek(year, week, days))
    }

    fun parseBrick(brick: Element, date: LocalDate): ScheduleEvent? {
        val tooltip = brick.attr("data-tooltip")
        val href = brick.attr("href")
        val brikId = brick.attr("data-brikid").ifBlank {
            extractIdFromHref(href) ?: contentBasedId(date, tooltip)
        }

        // iOS: CSS classes; Flutter: exact tooltip lines — accept both
        val status = when {
            brick.hasClass("s2cancelled") ||
                tooltip.lineSequence().any { it.trim() == "Aflyst!" } ||
                tooltip.contains("Aflyst") -> EventStatus.CANCELLED
            brick.hasClass("s2changed") ||
                tooltip.lineSequence().any { it.trim() == "Ændret!" } ||
                tooltip.contains("Ændret") -> EventStatus.CHANGED
            else -> EventStatus.NORMAL
        }

        val parsed = parseTooltip(tooltip, date)
        val teacherId = extractTeacherId(brick)

        return ScheduleEvent(
            id = brikId,
            title = parsed.title,
            team = parsed.holdName.orEmpty(),
            teacher = parsed.teacher,
            teacherId = teacherId,
            room = parsed.room,
            status = status,
            start = parsed.start,
            end = parsed.end,
            date = date,
            notes = parsed.notes,
            homework = parsed.homework,
            isAllDay = parsed.isAllDay,
            href = href.ifBlank { null },
            hasHomeworkIcon = brick.selectFirst(".ls-lektier") != null,
            hasNoteIcon = brick.selectFirst(".ls-note") != null,
        )
    }

    /**
     * iOS [ScheduleParser.parseTooltip] — free title vs Hold digit-prefix rule,
     * multi-line Note / Lektier / Øvrigt sections.
     */
    internal fun parseTooltip(tooltip: String, date: LocalDate): TooltipFields {
        val lines = tooltip.lines().map { it.trim() }.filter { it.isNotEmpty() }
        var freeTitle: String? = null
        var holdName: String? = null
        var teacher: String? = null
        var room: String? = null
        var notes: String? = null
        var homework: String? = null
        var start: LocalDateTime? = null
        var end: LocalDateTime? = null
        var isAllDay = tooltip.contains("Hele dagen", ignoreCase = true)
        var currentSection: String? = null

        for (line in lines) {
            when {
                line == "Ændret!" || line == "Aflyst!" -> continue
                line.contains("Hele dagen", ignoreCase = true) -> {
                    isAllDay = true
                    continue
                }
                line.startsWith("Hold:", ignoreCase = true) -> {
                    currentSection = null
                    holdName = line.substringAfter(':').trim()
                }
                line.startsWith("Lærer:", ignoreCase = true) ||
                    line.startsWith("Lærere:", ignoreCase = true) -> {
                    currentSection = null
                    teacher = line.substringAfter(':').trim()
                }
                line.startsWith("Lokale:", ignoreCase = true) ||
                    line.startsWith("Lokaler:", ignoreCase = true) -> {
                    currentSection = null
                    room = line.substringAfter(':').trim()
                }
                line.startsWith("Note:", ignoreCase = true) -> {
                    currentSection = "note"
                    notes = ""
                }
                line.startsWith("Lektier:", ignoreCase = true) -> {
                    currentSection = "homework"
                    // iOS keeps content after the header on following lines; also take same-line rest
                    val rest = line.substringAfter(':', "").trim()
                    homework = if (rest.isNotEmpty()) "$rest\n" else ""
                }
                line.startsWith("Øvrigt indhold:", ignoreCase = true) ||
                    line.startsWith("Øvrigt", ignoreCase = true) -> {
                    currentSection = "other"
                    val rest = line.substringAfter(':', "").trim()
                    if (rest.isNotEmpty()) {
                        notes = ((notes ?: "") + rest + "\n")
                    }
                }
                currentSection == "note" -> notes = (notes ?: "") + line + "\n"
                currentSection == "homework" -> homework = (homework ?: "") + line + "\n"
                currentSection == "other" -> notes = (notes ?: "") + line + "\n"
                else -> {
                    val range = LectioDateUtils.parseTimeRange(line)
                    if (range != null && start == null) {
                        // Multi-date tooltips (Flutter): use dates embedded in the line when present
                        val dates = Regex("""(\d{1,2}/\d{1,2}-\d{4})""").findAll(line)
                            .mapNotNull { LectioDateUtils.parseLectioDate(it.groupValues[1])?.toLocalDate() }
                            .toList()
                        val startDate = dates.getOrNull(0) ?: date
                        val endDate = dates.getOrNull(1) ?: startDate
                        start = LocalDateTime.of(startDate, range.first)
                        end = LocalDateTime.of(endDate, range.second)
                    } else if (
                        freeTitle == null &&
                        currentSection == null &&
                        !line.contains('/') &&
                        !line.contains(':')
                    ) {
                        freeTitle = line
                    }
                }
            }
        }

        // iOS: Hold starting with digit (e.g. "1x Fy") preferred; else free title → hold → Ukendt
        val finalTitle = when {
            holdName != null && holdName.firstOrNull()?.isDigit() == true -> holdName
            freeTitle != null -> freeTitle
            holdName != null -> holdName
            else -> "Modul"
        }

        return TooltipFields(
            title = finalTitle,
            holdName = holdName,
            freeTitle = freeTitle,
            teacher = teacher,
            room = room,
            notes = notes?.trim()?.ifBlank { null },
            homework = homework?.trim()?.ifBlank { null },
            start = start,
            end = end,
            isAllDay = isAllDay,
        )
    }

    data class TooltipFields(
        val title: String,
        val holdName: String?,
        val freeTitle: String?,
        val teacher: String?,
        val room: String?,
        val notes: String?,
        val homework: String?,
        val start: LocalDateTime?,
        val end: LocalDateTime?,
        val isAllDay: Boolean,
    )

    /** iOS: SHA-256 of `yyyy-MM-dd|tooltip`, first 16 bytes hex, prefix `AD`. */
    internal fun contentBasedId(date: LocalDate, tooltip: String): String {
        val base = "${date.format(isoDateFmt)}|$tooltip"
        val digest = MessageDigest.getInstance("SHA-256").digest(base.toByteArray(Charsets.UTF_8))
        val hex = digest.take(16).joinToString("") { b -> "%02x".format(b) }
        return "AD$hex"
    }

    private fun extractTeacherId(brick: Element): String? {
        val card = brick.attr("data-lectiocontextcard")
        if (card.startsWith("T") && card.length > 1) return card.drop(1)
        brick.select("span[data-lectiocontextcard]").forEach { span ->
            val c = span.attr("data-lectiocontextcard")
            if (c.startsWith("T") && c.length > 1) return c.drop(1)
        }
        return null
    }

    private fun parseDataDate(raw: String): LocalDate? {
        // iOS primary: ISO yyyy-MM-dd; Android fixtures / some pages: d/M-yyyy
        runCatching { return LocalDate.parse(raw.take(10), isoDateFmt) }
        runCatching { return LocalDate.parse(raw, dateAttrFmt) }
        val m = Regex("""(\d{1,2})/(\d{1,2})-(\d{4})""").find(raw) ?: return null
        return runCatching {
            LocalDate.of(m.groupValues[3].toInt(), m.groupValues[2].toInt(), m.groupValues[1].toInt())
        }.getOrNull()
    }

    private fun extractIdFromHref(href: String): String? {
        Regex("""absid=(\d+)""").find(href)?.let { return "ABS${it.groupValues[1]}" }
        Regex("""aftaleid=(\d+)""").find(href)?.let { return "AFT${it.groupValues[1]}" }
        Regex("""ProeveholdId=(\d+)""").find(href)?.let { return "PRV${it.groupValues[1]}" }
        return null
    }
}
