package dk.betterlectio.android.feature.schedule

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import kotlin.math.max

/**
 * Multi-day schedule expansion and per-day layout clamping.
 *
 * Lectio often places a multi-day brick only on the start day (tooltip like
 * `5/5-2026 08:00 til 7/5-2026 16:00`). We expand those onto every covered day
 * and clamp timed layout to the visible day bounds.
 */
object ScheduleMultiDay {

    /**
     * Expand one event into one occurrence per calendar day it covers.
     * Single-day / no-range events return a single-element list.
     *
     * Full middle days of a timed multi-day range become [ScheduleEvent.isAllDay]
     * so they render in the all-day strip. First/last partial days stay timed;
     * [ScheduleEvent.start]/[ScheduleEvent.end] remain the true range.
     */
    fun expandEventAcrossDays(event: ScheduleEvent): List<ScheduleEvent> {
        val start = event.start
        val end = event.end
        if (start == null || end == null || !end.isAfter(start)) {
            return listOf(event)
        }

        val startDay = start.toLocalDate()
        // Exclusive end at midnight → last covered day is the previous calendar day.
        val lastDay = lastCoveredDay(start, end)
        if (lastDay == startDay) {
            return listOf(event.copy(date = startDay))
        }

        val out = ArrayList<ScheduleEvent>()
        var day = startDay
        while (!day.isAfter(lastDay)) {
            val dayStart = day.atStartOfDay()
            val dayEnd = day.plusDays(1).atStartOfDay()
            val coversFullDay = !start.isAfter(dayStart) && !end.isBefore(dayEnd)
            out += event.copy(
                date = day,
                isAllDay = event.isAllDay || coversFullDay,
            )
            day = day.plusDays(1)
        }
        return out
    }

    /**
     * Redistribute a week's events so multi-day items appear on every covered day
     * within the week. Dedupes by `(id, date)` so Lectio bricks that already
     * repeat per day are not doubled.
     */
    fun expandWeek(week: ScheduleWeek): ScheduleWeek {
        if (week.days.isEmpty()) return week

        val weekDates = week.days.map { it.date }.toSortedSet()
        val infoByDate = week.days.associate { it.date to it.informations }

        // Prefer the widest start/end when the same id appears multiple times.
        val byId = LinkedHashMap<String, ScheduleEvent>()
        val noId = mutableListOf<ScheduleEvent>()
        for (day in week.days) {
            for (event in day.events) {
                if (event.id.isBlank()) {
                    noId += event
                    continue
                }
                val existing = byId[event.id]
                byId[event.id] = if (existing == null) event else preferWider(existing, event)
            }
        }

        val expanded = (byId.values + noId).flatMap { expandEventAcrossDays(it) }

        // Only place occurrences on days that belong to this week view.
        val byDate = expanded
            .filter { it.date in weekDates }
            .groupBy { it.date }
            .mapValues { (_, list) ->
                list
                    .distinctBy { it.id.ifBlank { "${it.title}|${it.start}|${it.end}" } }
                    .sortedWith(
                        compareBy(
                            { !it.isAllDay },
                            { it.start ?: LocalDateTime.MIN },
                            { it.title },
                        ),
                    )
            }

        val days = weekDates.map { date ->
            ScheduleDay(
                date = date,
                events = byDate[date].orEmpty(),
                informations = infoByDate[date].orEmpty(),
            )
        }
        return week.copy(days = days)
    }

    /**
     * Minutes from [dayStartHour]:00 for the portion of [event] that falls on [date].
     * Returns null if the event does not intersect the day (or is all-day).
     */
    fun segmentMinutesOnDay(
        event: ScheduleEvent,
        date: LocalDate,
        dayStartHour: Int,
        minDurationMinutes: Int = 29,
    ): Pair<Int, Int>? {
        if (event.isAllDay) return null
        val start = event.start ?: return null
        val end = event.end ?: return null
        if (!end.isAfter(start)) return null

        val dayStart = date.atStartOfDay()
        val dayEnd = date.plusDays(1).atStartOfDay()
        val segStart = maxDateTime(start, dayStart)
        val segEnd = minDateTime(end, dayEnd)
        if (!segStart.isBefore(segEnd)) return null

        val startMin = max(0, minutesFromDayStartHour(segStart, date, dayStartHour))
        val endMinRaw = if (segEnd >= dayEnd) {
            (24 * 60) - dayStartHour * 60
        } else {
            minutesFromDayStartHour(segEnd, date, dayStartHour)
        }
        val endMin = max(startMin + minDurationMinutes, endMinRaw)
        return startMin to endMin
    }

    /** True when start and end fall on different calendar days (after midnight normalisation). */
    fun isMultiDay(event: ScheduleEvent): Boolean {
        val start = event.start ?: return false
        val end = event.end ?: return false
        if (!end.isAfter(start)) return false
        return start.toLocalDate() != lastCoveredDay(start, end)
    }

    private fun lastCoveredDay(start: LocalDateTime, end: LocalDateTime): LocalDate {
        val endDay = end.toLocalDate()
        return if (end.toLocalTime() == LocalTime.MIDNIGHT && endDay.isAfter(start.toLocalDate())) {
            endDay.minusDays(1)
        } else {
            endDay
        }
    }

    private fun preferWider(a: ScheduleEvent, b: ScheduleEvent): ScheduleEvent {
        val aStart = a.start
        val aEnd = a.end
        val bStart = b.start
        val bEnd = b.end
        if (aStart == null || aEnd == null) return if (bStart != null && bEnd != null) b else a
        if (bStart == null || bEnd == null) return a
        val start = if (bStart.isBefore(aStart)) bStart else aStart
        val end = if (bEnd.isAfter(aEnd)) bEnd else aEnd
        // Prefer non-blank metadata from either side.
        return a.copy(
            start = start,
            end = end,
            title = a.title.ifBlank { b.title },
            teacher = a.teacher ?: b.teacher,
            room = a.room ?: b.room,
            notes = a.notes ?: b.notes,
            homework = a.homework ?: b.homework,
            isAllDay = a.isAllDay || b.isAllDay,
            href = a.href ?: b.href,
        )
    }

    private fun minutesFromDayStartHour(
        dt: LocalDateTime,
        date: LocalDate,
        dayStartHour: Int,
    ): Int {
        return when {
            dt.toLocalDate() == date ->
                (dt.hour * 60 + dt.minute) - dayStartHour * 60
            dt.toLocalDate() == date.plusDays(1) ->
                (24 * 60) - dayStartHour * 60 + (dt.hour * 60 + dt.minute)
            dt.toLocalDate().isBefore(date) ->
                0 - dayStartHour * 60
            else ->
                (24 * 60) - dayStartHour * 60
        }
    }

    private fun maxDateTime(a: LocalDateTime, b: LocalDateTime): LocalDateTime =
        if (a.isAfter(b)) a else b

    private fun minDateTime(a: LocalDateTime, b: LocalDateTime): LocalDateTime =
        if (a.isBefore(b)) a else b
}
