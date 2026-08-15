package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Dates
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

/**
 * W4 `#timetable` grid (Home, AC mytimetable, EA mytimetable).
 *
 * Layout: hour column of `.cell` labels, then one `.column` per day.
 * Lessons are absolutely positioned `.period` blocks (1px ≈ 1 minute from `tt_start_hour`).
 */
object W4TimetableParser {
    private val TIME_RANGE = Regex(
        """(\d{1,2}):(\d{2})\s*[—–\-]\s*(\d{1,2}):(\d{2})""",
    )
    private val PX = Regex("""(-?\d+(?:\.\d+)?)px""")
    private val START_HOUR = Regex("""tt_start_hour\s*=\s*(\d+)""")

    fun parseWeek(
        html: String,
        year: Int,
        week: Int,
        source: String = "ac",
    ): ScheduleWeek {
        val doc = Jsoup.parse(html)
        val monday = IsoDateUtils.weekStart(year, week)
        val dates = parseHeaderDates(doc) ?: (0..6).map { monday.plusDays(it.toLong()) }
        val startHour = START_HOUR.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: 7

        val grid = doc.select("#timetable").last()
        val dayColumns = grid?.children()
            ?.filter { col -> col.hasClass("column") && col.selectFirst(".cell") == null }
            .orEmpty()

        val days = dates.mapIndexed { index, date ->
            val column = dayColumns.getOrNull(index)
            val events = column
                ?.select(".period")
                ?.mapIndexedNotNull { i, period ->
                    parsePeriod(period, date, startHour, "$source-$date-$i")
                }
                .orEmpty()
                .sortedWith(compareBy({ it.start }, { it.title }))
            ScheduleDay(date = date, events = events)
        }

        return ScheduleWeek(year = year, week = week, days = days)
    }

    fun mergeWeeks(primary: ScheduleWeek, extra: ScheduleWeek): ScheduleWeek {
        val extraByDate = extra.days.associateBy { it.date }
        val days = primary.days.map { day ->
            val more = extraByDate[day.date]?.events.orEmpty()
            day.copy(events = (day.events + more).sortedWith(compareBy({ it.start }, { it.title })))
        }
        return primary.copy(days = days)
    }

    private fun parseHeaderDates(doc: org.jsoup.nodes.Document): List<LocalDate>? {
        val cells = doc.select("#timetable-header .header-cell")
            .filter { it.selectFirst(".day-name") != null }
        if (cells.size < 5) return null
        val dates = cells.mapNotNull { cell ->
            cell.children()
                .map { it.text().trim() }
                .firstNotNullOfOrNull { W4Dates.parse(it) }
        }
        return dates.takeIf { it.size == cells.size }
    }

    private fun parsePeriod(
        period: Element,
        date: LocalDate,
        startHour: Int,
        fallbackId: String,
    ): ScheduleEvent? {
        val inner = period.selectFirst(".inner") ?: period
        val datetime = inner.selectFirst(".datetime")?.text()?.trim().orEmpty()
        val room = inner.selectFirst(".room")?.text()?.trim()?.ifBlank { null }
        val range = TIME_RANGE.find(datetime) ?: TIME_RANGE.find(inner.text())
        val (start, end) = if (range != null) {
            val s = LocalTime.of(range.groupValues[1].toInt(), range.groupValues[2].toInt())
            val e = LocalTime.of(range.groupValues[3].toInt(), range.groupValues[4].toInt())
            LocalDateTime.of(date, s) to LocalDateTime.of(date, e)
        } else {
            val top = stylePx(period.attr("style"), "top") ?: return null
            val height = stylePx(period.attr("style"), "height") ?: 60.0
            val startMin = startHour * 60 + top.toInt()
            val endMin = startMin + height.toInt().coerceAtLeast(15)
            ofMinutes(date, startMin) to ofMinutes(date, endMin)
        }

        val title = inner.clone().apply {
            select(".datetime, .room, .absence, .present, .normal, .prearranged, .close").remove()
        }.text().trim().ifBlank { inner.text().trim() }
        if (title.isBlank() || title.equals("No-Classes", ignoreCase = true)) return null

        val href = period.selectFirst("a[href]")?.attr("href")?.ifBlank { null }
        return ScheduleEvent(
            id = href?.let { W4UrlsRouteId(it) } ?: fallbackId,
            title = title,
            team = title,
            room = room,
            start = start,
            end = end,
            date = date,
            href = href,
        )
    }

    private fun stylePx(style: String, prop: String): Double? {
        val match = Regex("""$prop\s*:\s*([^;]+)""", RegexOption.IGNORE_CASE).find(style) ?: return null
        return PX.find(match.groupValues[1])?.groupValues?.get(1)?.toDoubleOrNull()
    }

    private fun ofMinutes(date: LocalDate, minutes: Int): LocalDateTime {
        val clamped = minutes.coerceIn(0, 24 * 60 - 1)
        return LocalDateTime.of(date, LocalTime.of(clamped / 60, clamped % 60))
    }

    private fun W4UrlsRouteId(href: String): String {
        val id = Regex("""(?:id|class_id|group_id)=(\d+)""").find(href)?.groupValues?.get(1)
        return id?.let { "w4-$it" } ?: href
    }
}
