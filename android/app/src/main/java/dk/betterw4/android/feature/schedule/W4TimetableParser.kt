package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Dates
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

enum class EventSource(val idPrefix: String) {
    ACADEMICS("ac"),
    EXTRA_ACADEMICS("ea"),
    SCHOOL_CALENDAR("gcal"),
    LOCAL("local"),
}

/**
 * W4 `#timetable` grid (Home, AC mytimetable, EA mytimetable).
 *
 * Lesson bricks (`div.period`) print the compact class id (`1EA16CECOX`) in
 * `.title` and the real subject in `title="… Class: <b>Economics</b> …"`.
 * The parser keeps the class id on [ScheduleEvent.team] and the subject name
 * on [ScheduleEvent.title] so the schedule can show "Economics" instead of
 * the code, while colours still key off the subject.
 */
object W4TimetableParser {
    /** Passing-time slop: W4 doubles usually touch (09:05–09:05). */
    internal const val MAX_DOUBLE_BLOCK_GAP_MINUTES = 5L

    private val TIME_RANGE = Regex(
        """(\d{1,2}):(\d{2})\s*[—–\-]\s*(\d{1,2}):(\d{2})""",
    )
    private val PX = Regex("""(-?\d+(?:\.\d+)?)px""")
    private val START_HOUR = Regex("""tt_start_hour\s*=\s*(\d+)""")
    private val END_HOUR = Regex("""tt_end_hour\s*=\s*(\d+)""")
    private val CHROME_CLASSES = setOf(
        "datetime", "room", "absence", "present", "normal", "prearranged", "close",
    )
    private val ATTENDANCE_PHRASE = Regex("""\(([^)]*absence[^)]*)\)""", RegexOption.IGNORE_CASE)

    fun parseWeek(
        html: String,
        year: Int,
        week: Int,
        source: String = "ac",
    ): ScheduleWeek {
        val eventSource = when (source.lowercase()) {
            "ea", "extra", "extraacademics" -> EventSource.EXTRA_ACADEMICS
            "gcal", "school" -> EventSource.SCHOOL_CALENDAR
            "local" -> EventSource.LOCAL
            else -> EventSource.ACADEMICS
        }
        return parseWeek(html, eventSource, year, week)
    }

    fun parseWeek(
        html: String,
        source: EventSource,
        fallbackYear: Int? = null,
        fallbackWeek: Int? = null,
    ): ScheduleWeek {
        val doc = Jsoup.parse(html)
        val startHour = START_HOUR.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: 7
        val endHour = END_HOUR.find(html)?.groupValues?.get(1)?.toIntOrNull() ?: 22

        var days = doc.select("#timetable-header .header-cell").mapNotNull { parseHeaderCell(it) }

        val grid = doc.select("div#timetable").last()
        val dayColumns = grid?.let { dayColumns(it) }.orEmpty()

        if (days.isEmpty() && dayColumns.isNotEmpty()) {
            days = fallbackDays(dayColumns.size, fallbackYear, fallbackWeek)
        }

        days = days.mapIndexed { index, day ->
            val column = dayColumns.getOrNull(index) ?: return@mapIndexed day
            val events = parseColumn(column, day, source, startHour)
            val isToday = column.hasClass("current")
            day.copy(events = events, isToday = isToday)
        }

        val title = doc.select("#timetable h3").first()?.text()?.trim()?.ifBlank { null }
        val isoDate = days.firstOrNull()?.date
        val resolvedYear = isoDate?.let { IsoDateUtils.isoWeekYear(it) } ?: fallbackYear ?: 0
        val resolvedWeek = isoDate?.let { IsoDateUtils.isoWeek(it) } ?: fallbackWeek ?: 0

        return ScheduleWeek(
            year = resolvedYear,
            week = resolvedWeek,
            days = days,
            title = title,
            source = source.idPrefix,
            startHour = startHour,
            endHour = endHour,
        )
    }

    fun mergeWeeks(primary: ScheduleWeek, extra: ScheduleWeek): ScheduleWeek {
        val extraByDate = extra.days.associateBy { it.date }
        val days = primary.days.map { day ->
            val more = extraByDate[day.date]?.events.orEmpty()
            day.copy(
                events = (day.events + more).sortedWith(
                    compareBy({ it.start ?: LocalDateTime.MIN }, { it.title }),
                ),
            )
        }
        return primary.copy(
            days = days,
            startHour = minOf(primary.startHour, extra.startHour),
            endHour = maxOf(primary.endHour, extra.endHour),
        )
    }

    private val HEADER_DATE = Regex("""\d{1,2}-[A-Za-z]{3}-\d{2,4}""")

    private fun parseHeaderCell(cell: Element): ScheduleDay? {
        if (cell.hasClass("first")) return null
        val dayName = cell.selectFirst(".day-name")?.text()?.trim().orEmpty()
        val date = cell.children()
            .map { it.text().trim() }
            .firstNotNullOfOrNull { W4Dates.parse(it) }
            ?: HEADER_DATE.find(cell.text())?.value?.let { W4Dates.parse(it) }
            ?: return null
        val rotationEl = cell.selectFirst(".rotation-day")
        val rotationDay = rotationEl?.text()?.trim()?.ifBlank { null }
        val isNoClasses = rotationEl?.hasClass("no-classes") == true
        val eaNote = cell.children()
            .filter { it.className().isBlank() }
            .map { it.text().trim() }
            .lastOrNull { it.isNotEmpty() && W4Dates.parse(it) == null }
        return ScheduleDay(
            date = date,
            events = emptyList(),
            dayName = dayName.ifBlank { null },
            rotationDay = rotationDay,
            isNoClasses = isNoClasses,
            eaNote = eaNote,
        )
    }

    private fun fallbackDays(count: Int, year: Int?, week: Int?): List<ScheduleDay> {
        if (year == null || week == null) return emptyList()
        val monday = IsoDateUtils.weekStart(year, week)
        return (0 until count).map { offset ->
            ScheduleDay(date = monday.plusDays(offset.toLong()), events = emptyList())
        }
    }

    private fun dayColumns(grid: Element): List<Element> =
        grid.children().filter { col ->
            col.hasClass("column") && col.selectFirst(".cell") == null
        }

    private fun parseColumn(
        column: Element,
        day: ScheduleDay,
        source: EventSource,
        startHour: Int,
    ): List<ScheduleEvent> {
        val parsed = column.select(".period").mapIndexedNotNull { index, period ->
            parsePeriod(period, day, source, startHour, index)
        }
        return mergeConsecutiveSameClass(parsed)
    }

    /**
     * W4 paints a double (or triple) as stacked `.period` bricks of the same
     * class. Fold those into one block spanning the first start to the last end.
     */
    internal fun mergeConsecutiveSameClass(
        events: List<ScheduleEvent>,
        maxGapMinutes: Long = MAX_DOUBLE_BLOCK_GAP_MINUTES,
    ): List<ScheduleEvent> {
        if (events.size < 2) return events
        val sorted = events.sortedWith(
            compareBy({ it.start ?: LocalDateTime.MIN }, { it.title }, { it.id }),
        )
        val merged = ArrayList<ScheduleEvent>(sorted.size)
        for (event in sorted) {
            val last = merged.lastOrNull()
            if (last != null && canMergeConsecutive(last, event, maxGapMinutes)) {
                merged[merged.lastIndex] = mergeConsecutive(last, event)
            } else {
                merged += event
            }
        }
        return uniquifyIds(merged)
    }

    private fun canMergeConsecutive(
        first: ScheduleEvent,
        second: ScheduleEvent,
        maxGapMinutes: Long,
    ): Boolean {
        if (first.isAllDay || second.isAllDay) return false
        if (first.source != second.source) return false
        if (first.status != second.status) return false
        if (SchoolCalendar.isSchoolCalendarEvent(first) ||
            SchoolCalendar.isSchoolCalendarEvent(second)
        ) {
            return false
        }
        if (first.source == EventSource.LOCAL.idPrefix ||
            second.source == EventSource.LOCAL.idPrefix
        ) {
            return false
        }
        if (mergeKey(first) != mergeKey(second)) return false
        val firstEnd = first.end ?: return false
        val secondStart = second.start ?: return false
        val gap = java.time.Duration.between(firstEnd, secondStart).toMinutes()
        return gap <= maxGapMinutes
    }

    private fun mergeKey(event: ScheduleEvent): String {
        val team = event.team.trim()
        if (team.isNotEmpty()) return team.lowercase()
        return event.title.trim().lowercase()
    }

    private fun mergeConsecutive(first: ScheduleEvent, second: ScheduleEvent): ScheduleEvent {
        val room = when {
            first.room.isNullOrBlank() -> second.room
            second.room.isNullOrBlank() || first.room == second.room -> first.room
            else -> "${first.room} / ${second.room}"
        }
        val teacher = first.teacher?.takeIf { it.isNotBlank() } ?: second.teacher
        val teacherId = first.teacherId?.takeIf { it.isNotBlank() } ?: second.teacherId
        val notes = when {
            first.notes.isNullOrBlank() -> second.notes
            second.notes.isNullOrBlank() || first.notes == second.notes -> first.notes
            else -> "${first.notes}\n${second.notes}"
        }
        val homework = first.homework?.takeIf { it.isNotBlank() } ?: second.homework
        val end = listOfNotNull(first.end, second.end).maxOrNull() ?: first.end
        return first.copy(
            teacher = teacher,
            teacherId = teacherId,
            room = room,
            end = end,
            notes = notes,
            homework = homework,
            hasHomeworkIcon = first.hasHomeworkIcon || second.hasHomeworkIcon,
            hasNoteIcon = first.hasNoteIcon || second.hasNoteIcon,
        )
    }

    private fun uniquifyIds(events: List<ScheduleEvent>): List<ScheduleEvent> {
        val seen = HashSet<String>()
        return events.map { event ->
            if (seen.add(event.id)) {
                event
            } else {
                val stamp = event.start?.let { "%02d%02d".format(it.hour, it.minute) }
                    ?: seen.size.toString()
                val next = "${event.id}-$stamp"
                seen.add(next)
                event.copy(id = next)
            }
        }
    }

    private fun parsePeriod(
        period: Element,
        day: ScheduleDay,
        source: EventSource,
        startHour: Int,
        index: Int,
    ): ScheduleEvent? {
        val inner = period.selectFirst(".inner") ?: period
        val datetime = inner.selectFirst(".datetime")?.text()?.trim().orEmpty()
        val href = period.selectFirst("a[href]")?.attr("href")?.ifBlank { null }
        val rawTooltip = period.attr("title").trim().ifBlank { null }
        val tooltip = rawTooltip?.let { PeriodTooltip.parse(it) }

        val brickTitle = blockTitle(inner)
        if (brickTitle.isBlank() || brickTitle.equals("No-Classes", ignoreCase = true)) return null

        val classId = href?.let { CLASS_ID_QUERY.find(it)?.groupValues?.get(1) }
            ?: brickTitle.takeIf { W4ClassId.looksLike(it) }
        val title = tooltip?.className
            ?: tooltip?.blockName?.let { "Block $it" }
            ?: brickTitle.takeUnless { W4ClassId.looksLike(it) }
            ?: brickTitle
        if (title.isBlank()) return null
        val notes = tooltip?.extraNotes
            ?.takeUnless { it.equals(title, ignoreCase = true) }
            ?.takeUnless { it.equals(brickTitle, ignoreCase = true) }

        val range = TIME_RANGE.find(datetime) ?: TIME_RANGE.find(inner.text())
        val (start, end) = if (range != null) {
            val s = LocalTime.of(range.groupValues[1].toInt(), range.groupValues[2].toInt())
            val e = LocalTime.of(range.groupValues[3].toInt(), range.groupValues[4].toInt())
            LocalDateTime.of(day.date, s) to LocalDateTime.of(day.date, e)
        } else {
            pixelPlacement(period, day.date, startHour) ?: return null
        }

        val room = tooltip?.room
            ?: stripRoomPrefix(inner.selectFirst(".room")?.text()?.trim())
        val teacherId = href?.let { UWC_ID.find(it)?.groupValues?.get(1)?.lowercase() }

        val attendanceMark = attendanceOf(inner, rawTooltip)
        return ScheduleEvent(
            id = eventId(href, classId, source, day.date, index),
            title = title,
            team = classId ?: title,
            teacher = tooltip?.teacher,
            teacherId = teacherId,
            room = room,
            status = statusOf(period, inner),
            start = start,
            end = end,
            date = day.date,
            notes = notes,
            isAllDay = start == null,
            href = href,
            source = source.idPrefix,
            attendance = attendanceMark?.first,
            attendanceLabel = attendanceMark?.second?.first,
            attendanceTooltip = attendanceMark?.second?.second,
        )
    }

    /**
     * Absences week grids stamp `.absence.not-checked` / `.present` / `.prearranged`
     * on class blocks. Breakfast and break have no marker.
     */
    private fun attendanceOf(
        inner: Element,
        tooltip: String?,
    ): Pair<LessonAttendance, Pair<String?, String?>>? {
        val marker = inner.selectFirst(".absence, .present, .normal, .prearranged, .attendance") ?: return null
        val classes = marker.classNames().map { it.lowercase() }.toSet()
        val badge = marker.text().trim().ifBlank { null }
        val phrase = tooltip
            ?.let { ATTENDANCE_PHRASE.find(it)?.groupValues?.get(1)?.trim() }
            ?.ifBlank { null }
        val kind = when {
            "not-checked" in classes -> LessonAttendance.UNCHECKED
            "prearranged" in classes -> LessonAttendance.PREARRANGED
            "present" in classes -> LessonAttendance.PRESENT
            "absence" in classes || "normal" in classes -> LessonAttendance.ABSENT
            else -> LessonAttendance.UNKNOWN
        }
        return kind to (badge to phrase)
    }

    private fun blockTitle(inner: Element): String {
        inner.selectFirst(".title")?.text()?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val clone = inner.clone()
        clone.select(CHROME_CLASSES.joinToString(",") { ".$it" }).remove()
        return clone.text().trim().ifBlank { inner.text().trim() }
    }

    private fun stripRoomPrefix(raw: String?): String? {
        val trimmed = raw?.trim()?.ifBlank { null } ?: return null
        return ROOM_PREFIX.replace(trimmed, "").ifBlank { trimmed }
    }

    private fun statusOf(block: Element, inner: Element): EventStatus {
        val classes = (block.classNames() + inner.classNames()).map { it.lowercase() }.toSet()
        if ("cancelled" in classes || "canceled" in classes) return EventStatus.CANCELLED
        if ("changed" in classes || "moved" in classes) return EventStatus.CHANGED
        return EventStatus.NORMAL
    }

    private fun pixelPlacement(
        block: Element,
        date: LocalDate,
        startHour: Int,
    ): Pair<LocalDateTime, LocalDateTime>? {
        val top = stylePx(block.attr("style"), "top") ?: return null
        val height = stylePx(block.attr("style"), "height") ?: 60.0
        val startMin = startHour * 60 + top.toInt()
        val endMin = startMin + height.toInt().coerceAtLeast(15)
        return ofMinutes(date, startMin) to ofMinutes(date, endMin)
    }

    private fun eventId(
        href: String?,
        classId: String?,
        source: EventSource,
        date: LocalDate,
        index: Int,
    ): String {
        if (!classId.isNullOrBlank()) return "${source.idPrefix}-w4-$classId"
        val numeric = href?.let { ID_QUERY.find(it)?.groupValues?.get(1) }
        if (numeric != null) return "${source.idPrefix}-w4-$numeric"
        return "${source.idPrefix}-${W4Dates.format(date)}-$index"
    }

    private fun stylePx(style: String, prop: String): Double? {
        val match = Regex("""$prop\s*:\s*([^;]+)""", RegexOption.IGNORE_CASE).find(style) ?: return null
        return PX.find(match.groupValues[1])?.groupValues?.get(1)?.toDoubleOrNull()
    }

    private fun ofMinutes(date: LocalDate, minutes: Int): LocalDateTime {
        val clamped = minutes.coerceIn(0, 24 * 60 - 1)
        return LocalDateTime.of(date, LocalTime.of(clamped / 60, clamped % 60))
    }

    private val ID_QUERY = Regex("""(?:id|group_id)=(\d+)""")
    private val CLASS_ID_QUERY = Regex("""(?:class_id|group_id)=([^&]+)""", RegexOption.IGNORE_CASE)
    private val UWC_ID = Regex("""\b(nc\d{2}[a-z]+)\b""", RegexOption.IGNORE_CASE)
    private val ROOM_PREFIX = Regex("""^(?i)room\s+""")
}

/**
 * W4 `div.period[title]` tooltip, captured live Aug 2026:
 * `Monday 08:15 - 09:05<br /> Class: <b>Economics</b><br />Teacher: <b>…</b><br />Room: <b>A 1.6</b>`
 *
 * Structured fields are pulled out for the card. Anything left after stripping
 * `<br>` / tags becomes [extraNotes] so the lesson sheet never shows raw HTML.
 */
internal data class PeriodTooltip(
    val className: String? = null,
    val teacher: String? = null,
    val room: String? = null,
    val blockName: String? = null,
    val extraNotes: String? = null,
) {
    companion object {
        private val CLASS = Regex("""(?i)^Class:\s*(.+)$""")
        private val TEACHER = Regex("""(?i)^Teacher:\s*(.+)$""")
        private val ROOM = Regex("""(?i)^Room:\s*(.+)$""")
        private val BLOCK = Regex("""(?i)^Block:\s*(.+)$""")
        private val TIME_HEADING = Regex(
            """(?i)^(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b.*\d{1,2}:\d{2}""",
        )
        private val TAG = Regex("""<[^>]+>""")
        private val BREAK = Regex("""(?i)<br\s*/?>""")
        private val CLOSE_BLOCK = Regex("""(?i)</(?:p|div|li|h[1-6])>""")
        private val ENTITIES = listOf(
            "&nbsp;" to " ",
            "&#39;" to "'",
            "&quot;" to "\"",
            "&lt;" to "<",
            "&gt;" to ">",
            "&amp;" to "&",
        )

        fun parse(raw: String): PeriodTooltip {
            val lines = plainLines(raw)
            var className: String? = null
            var teacher: String? = null
            var room: String? = null
            var blockName: String? = null
            val leftover = ArrayList<String>()
            for (line in lines) {
                val classMatch = CLASS.find(line)
                if (classMatch != null) {
                    className = classMatch.groupValues[1].trim().ifBlank { null }
                    continue
                }
                val teacherMatch = TEACHER.find(line)
                if (teacherMatch != null) {
                    teacher = teacherMatch.groupValues[1].trim().ifBlank { null }
                    continue
                }
                val roomMatch = ROOM.find(line)
                if (roomMatch != null) {
                    room = roomMatch.groupValues[1].trim().ifBlank { null }
                    continue
                }
                val blockMatch = BLOCK.find(line)
                if (blockMatch != null) {
                    blockName = blockMatch.groupValues[1].trim().ifBlank { null }
                    continue
                }
                if (TIME_HEADING.containsMatchIn(line)) continue
                leftover += line
            }
            val shown = listOfNotNull(className, teacher, room, blockName, blockName?.let { "Block $it" })
                .map { it.trim().lowercase() }
                .toSet()
            val extra = leftover.filter { it.lowercase() !in shown }
            return PeriodTooltip(
                className = className,
                teacher = teacher,
                room = room,
                blockName = blockName,
                extraNotes = extra.joinToString("\n").ifBlank { null },
            )
        }

        fun plainText(raw: String): String = plainLines(raw).joinToString("\n")

        private fun plainLines(raw: String): List<String> {
            var text = raw
            for ((entity, replacement) in ENTITIES.dropLast(1)) {
                text = text.replace(entity, replacement, ignoreCase = true)
            }
            text = text.replace("&amp;", "&", ignoreCase = true)
            text = BREAK.replace(text, "\n")
            text = CLOSE_BLOCK.replace(text, "\n")
            text = TAG.replace(text, "")
            return text.lineSequence().map { it.replace('\u00A0', ' ').trim() }.filter { it.isNotEmpty() }.toList()
        }
    }
}
