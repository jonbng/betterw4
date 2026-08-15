package dk.betterw4.android.feature.schedule

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

/**
 * Minimal iCalendar parser for Google Calendar public `basic.ics` feeds.
 *
 * Handles folded lines, DATE / UTC / TZID datetimes, exclusive all-day DTEND,
 * and the RRULE frequencies that show up on the UWCRCN school calendar
 * (DAILY / WEEKLY / MONTHLY / YEARLY plus INTERVAL, UNTIL, COUNT, BYDAY, EXDATE).
 */
object IcsCalendarParser {
    val ZONE_OSLO: ZoneId = ZoneId.of("Europe/Oslo")

    private val DATE = DateTimeFormatter.ofPattern("yyyyMMdd")
    private val DATE_TIME = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss")
    private val WEEKDAYS = mapOf(
        "MO" to DayOfWeek.MONDAY,
        "TU" to DayOfWeek.TUESDAY,
        "WE" to DayOfWeek.WEDNESDAY,
        "TH" to DayOfWeek.THURSDAY,
        "FR" to DayOfWeek.FRIDAY,
        "SA" to DayOfWeek.SATURDAY,
        "SU" to DayOfWeek.SUNDAY,
    )

    fun eventsOverlapping(
        ics: String,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
        zone: ZoneId = ZONE_OSLO,
        idPrefix: String = SCHOOL_CALENDAR_ID_PREFIX,
        team: String = SCHOOL_CALENDAR_TEAM_TOKEN,
    ): List<ScheduleEvent> {
        if (rangeEndExclusive.isBefore(rangeStart)) return emptyList()
        val out = ArrayList<ScheduleEvent>()
        for (raw in parseVevents(ics)) {
            val parsed = parseEvent(raw, zone) ?: continue
            if (parsed.status == EventStatus.CANCELLED) continue
            for (occ in expand(parsed, rangeStart, rangeEndExclusive)) {
                out += occ.toScheduleEvent(idPrefix, team)
            }
        }
        return out.sortedWith(compareBy({ it.start }, { it.title }))
    }

    internal fun parseVevents(ics: String): List<Map<String, List<IcsProperty>>> {
        val events = ArrayList<Map<String, List<IcsProperty>>>()
        var current: MutableMap<String, MutableList<IcsProperty>>? = null
        for (line in unfold(ics)) {
            when {
                line.equals("BEGIN:VEVENT", ignoreCase = true) -> {
                    current = linkedMapOf()
                }
                line.equals("END:VEVENT", ignoreCase = true) -> {
                    current?.let { events += it }
                    current = null
                }
                current != null -> {
                    val prop = parseProperty(line) ?: continue
                    current.getOrPut(prop.name) { mutableListOf() }.add(prop)
                }
            }
        }
        return events
    }

    internal fun unfold(ics: String): List<String> {
        val out = ArrayList<String>()
        val buf = StringBuilder()
        fun flush() {
            if (buf.isNotEmpty()) {
                out += buf.toString()
                buf.setLength(0)
            }
        }
        for (raw in ics.lineSequence()) {
            val line = if (raw.endsWith('\r')) raw.dropLast(1) else raw
            if (line.startsWith(" ") || line.startsWith("\t")) {
                if (buf.isNotEmpty()) buf.append(line.substring(1))
            } else {
                flush()
                if (line.isNotEmpty()) buf.append(line)
            }
        }
        flush()
        return out
    }

    private fun parseEvent(props: Map<String, List<IcsProperty>>, zone: ZoneId): ParsedEvent? {
        val startProp = props["DTSTART"]?.firstOrNull() ?: return null
        val start = parseTemporal(startProp, zone) ?: return null
        val endProp = props["DTEND"]?.firstOrNull()
        val end = endProp?.let { parseTemporal(it, zone) }
            ?: props["DURATION"]?.firstOrNull()?.let { durationEnd(start, it.value) }
            ?: if (start.allDay) {
                Temporal(start.dateTime.plusDays(1), allDay = true)
            } else {
                Temporal(start.dateTime.plusHours(1), allDay = false)
            }
        val uid = unescape(props["UID"]?.firstOrNull()?.value.orEmpty()).ifBlank { startProp.value }
        val summary = unescape(props["SUMMARY"]?.firstOrNull()?.value.orEmpty()).ifBlank { return null }
        val location = unescape(props["LOCATION"]?.firstOrNull()?.value.orEmpty()).ifBlank { null }
        val description = unescape(props["DESCRIPTION"]?.firstOrNull()?.value.orEmpty())
            .let { stripHtml(it) }
            .trim()
            .ifBlank { null }
        val status = when (props["STATUS"]?.firstOrNull()?.value?.uppercase()) {
            "CANCELLED" -> EventStatus.CANCELLED
            else -> EventStatus.NORMAL
        }
        val rrule = props["RRULE"]?.firstOrNull()?.value
        val exDates = props["EXDATE"].orEmpty().flatMap { parseExdates(it, zone) }.toSet()
        return ParsedEvent(
            uid = uid,
            title = summary,
            location = location,
            description = description,
            start = start,
            end = end,
            status = status,
            rrule = rrule,
            exDates = exDates,
        )
    }

    private fun expand(
        event: ParsedEvent,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
    ): List<Occurrence> {
        val duration = java.time.Duration.between(event.start.dateTime, event.end.dateTime)
            .takeIf { !it.isNegative && !it.isZero }
            ?: java.time.Duration.ofHours(1)
        val rrule = event.rrule
        if (rrule.isNullOrBlank()) {
            return listOfNotNull(
                occurrenceIfOverlaps(event, event.start.dateTime, duration, rangeStart, rangeEndExclusive),
            )
        }
        val rule = parseRrule(rrule)
        if (rule.count != null) {
            return expandCounted(event, rule, duration, rangeStart, rangeEndExclusive)
        }
        val until = rule.until
        val out = ArrayList<Occurrence>()
        fun consider(start: LocalDateTime): Boolean {
            if (start.isBefore(event.start.dateTime)) return true
            if (until != null && start.isAfter(until)) return false
            if (isExcluded(event, start)) return true
            occurrenceIfOverlaps(event, start, duration, rangeStart, rangeEndExclusive)?.let { out += it }
            return true
        }
        when (rule.freq) {
            Freq.DAILY -> {
                var cursor = skipDailyTo(event.start.dateTime, rangeStart, rule.interval)
                var i = 0
                while (i++ < 400 && consider(cursor)) {
                    if (cursor.toLocalDate() >= rangeEndExclusive) break
                    cursor = cursor.plusDays(rule.interval.toLong())
                }
            }
            Freq.WEEKLY -> {
                val days = rule.byDays.ifEmpty { listOf(event.start.dateTime.dayOfWeek) }
                var weekStart = skipWeeklyTo(
                    event.start.dateTime.toLocalDate()
                        .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)),
                    rangeStart,
                    rule.interval,
                )
                var i = 0
                while (i++ < 80) {
                    for (dow in days.sorted()) {
                        val start = LocalDateTime.of(
                            weekStart.with(dow),
                            event.start.dateTime.toLocalTime(),
                        )
                        if (!consider(start)) return out
                    }
                    if (weekStart.isAfter(rangeEndExclusive)) break
                    weekStart = weekStart.plusWeeks(rule.interval.toLong())
                }
            }
            Freq.MONTHLY -> {
                var cursor = skipMonthlyTo(event.start.dateTime, rangeStart, rule.interval)
                var i = 0
                while (i++ < 36 && consider(cursor)) {
                    if (cursor.toLocalDate() >= rangeEndExclusive) break
                    cursor = cursor.plusMonths(rule.interval.toLong())
                }
            }
            Freq.YEARLY -> {
                var cursor = skipYearlyTo(event.start.dateTime, rangeStart, rule.interval)
                var i = 0
                while (i++ < 8 && consider(cursor)) {
                    if (cursor.toLocalDate() >= rangeEndExclusive) break
                    cursor = cursor.plusYears(rule.interval.toLong())
                }
            }
        }
        return out
    }

    /**
     * COUNT includes DTSTART, so walk from the start instead of jumping to [rangeStart].
     */
    private fun expandCounted(
        event: ParsedEvent,
        rule: Rrule,
        duration: java.time.Duration,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
    ): List<Occurrence> {
        val out = ArrayList<Occurrence>()
        var emitted = 0
        val limit = rule.count ?: return out
        fun consider(start: LocalDateTime): Boolean {
            if (start.isBefore(event.start.dateTime)) return true
            if (isExcluded(event, start)) return emitted < limit
            occurrenceIfOverlaps(event, start, duration, rangeStart, rangeEndExclusive)?.let { out += it }
            emitted++
            return emitted < limit
        }
        val cap = limit.coerceAtMost(800)
        when (rule.freq) {
            Freq.DAILY -> {
                var cursor = event.start.dateTime
                var i = 0
                while (i++ < cap && consider(cursor)) {
                    cursor = cursor.plusDays(rule.interval.toLong())
                }
            }
            Freq.WEEKLY -> {
                val days = rule.byDays.ifEmpty { listOf(event.start.dateTime.dayOfWeek) }
                var weekStart = event.start.dateTime.toLocalDate()
                    .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                var i = 0
                while (i++ < cap) {
                    for (dow in days.sorted()) {
                        val start = LocalDateTime.of(
                            weekStart.with(dow),
                            event.start.dateTime.toLocalTime(),
                        )
                        if (!consider(start)) return out
                    }
                    weekStart = weekStart.plusWeeks(rule.interval.toLong())
                }
            }
            Freq.MONTHLY -> {
                var cursor = event.start.dateTime
                var i = 0
                while (i++ < cap && consider(cursor)) {
                    cursor = cursor.plusMonths(rule.interval.toLong())
                }
            }
            Freq.YEARLY -> {
                var cursor = event.start.dateTime
                var i = 0
                while (i++ < cap && consider(cursor)) {
                    cursor = cursor.plusYears(rule.interval.toLong())
                }
            }
        }
        return out
    }

    private fun isExcluded(event: ParsedEvent, start: LocalDateTime): Boolean =
        start in event.exDates || start.toLocalDate().atStartOfDay() in event.exDates

    private fun skipDailyTo(start: LocalDateTime, rangeStart: LocalDate, interval: Int): LocalDateTime {
        val days = java.time.temporal.ChronoUnit.DAYS.between(start.toLocalDate(), rangeStart)
        if (days <= 0) return start
        val steps = (days + interval - 1) / interval
        return start.plusDays(steps * interval)
    }

    private fun skipWeeklyTo(weekStart: LocalDate, rangeStart: LocalDate, interval: Int): LocalDate {
        val rangeWeek = rangeStart.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val weeks = java.time.temporal.ChronoUnit.WEEKS.between(weekStart, rangeWeek)
        if (weeks <= 0) return weekStart
        val steps = (weeks + interval - 1) / interval
        return weekStart.plusWeeks(steps * interval)
    }

    private fun skipMonthlyTo(start: LocalDateTime, rangeStart: LocalDate, interval: Int): LocalDateTime {
        val months = java.time.temporal.ChronoUnit.MONTHS.between(
            start.toLocalDate().withDayOfMonth(1),
            rangeStart.withDayOfMonth(1),
        )
        if (months <= 0) return start
        val steps = (months + interval - 1) / interval
        return start.plusMonths(steps * interval)
    }

    private fun skipYearlyTo(start: LocalDateTime, rangeStart: LocalDate, interval: Int): LocalDateTime {
        val years = (rangeStart.year - start.year).toLong()
        if (years <= 0) return start
        val steps = (years + interval - 1) / interval
        return start.plusYears(steps * interval)
    }

    private fun occurrenceIfOverlaps(
        event: ParsedEvent,
        start: LocalDateTime,
        duration: java.time.Duration,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
    ): Occurrence? {
        val end = start.plus(duration)
        if (!overlaps(start, end, event.start.allDay, rangeStart, rangeEndExclusive)) return null
        return Occurrence(
            uid = event.uid,
            title = event.title,
            location = event.location,
            description = event.description,
            start = start,
            end = end,
            allDay = event.start.allDay,
            status = event.status,
        )
    }

    private fun overlaps(
        start: LocalDateTime,
        end: LocalDateTime,
        allDay: Boolean,
        rangeStart: LocalDate,
        rangeEndExclusive: LocalDate,
    ): Boolean {
        val lastDay = if (allDay && end.toLocalTime() == LocalTime.MIDNIGHT &&
            end.toLocalDate().isAfter(start.toLocalDate())
        ) {
            end.toLocalDate().minusDays(1)
        } else {
            end.toLocalDate()
        }
        val first = start.toLocalDate()
        return !first.isAfter(rangeEndExclusive.minusDays(1)) && !lastDay.isBefore(rangeStart)
    }

    private fun parseRrule(raw: String): Rrule {
        val parts = raw.split(';').mapNotNull { piece ->
            val eq = piece.indexOf('=')
            if (eq < 0) null
            else piece.substring(0, eq).uppercase() to piece.substring(eq + 1)
        }.toMap()
        val freq = when (parts["FREQ"]?.uppercase()) {
            "DAILY" -> Freq.DAILY
            "WEEKLY" -> Freq.WEEKLY
            "MONTHLY" -> Freq.MONTHLY
            "YEARLY" -> Freq.YEARLY
            else -> Freq.WEEKLY
        }
        val interval = parts["INTERVAL"]?.toIntOrNull()?.coerceAtLeast(1) ?: 1
        val count = parts["COUNT"]?.toIntOrNull()?.coerceAtLeast(1)
        val until = parts["UNTIL"]?.let { parseUntil(it) }
        val byDays = parts["BYDAY"]
            ?.split(',')
            ?.mapNotNull { token ->
                val code = token.takeLast(2).uppercase()
                WEEKDAYS[code]
            }
            .orEmpty()
        return Rrule(freq, interval, count, until, byDays)
    }

    private fun parseUntil(raw: String): LocalDateTime? {
        val t = raw.trim()
        parseUtcDateTime(t)?.let { return it }
        parseFloatingDateTime(t)?.let { return it }
        return runCatching { LocalDate.parse(t.take(8), DATE).atTime(LocalTime.MAX) }.getOrNull()
    }

    private fun parseExdates(prop: IcsProperty, zone: ZoneId): List<LocalDateTime> {
        return prop.value.split(',').mapNotNull { token ->
            parseTemporal(IcsProperty(prop.name, prop.params, token.trim()), zone)?.dateTime
        }
    }

    private fun parseTemporal(prop: IcsProperty, zone: ZoneId): Temporal? {
        val value = prop.value.trim()
        val isDate = prop.params["VALUE"].equals("DATE", ignoreCase = true) ||
            (value.length == 8 && 'T' !in value)
        if (isDate) {
            val date = runCatching { LocalDate.parse(value.take(8), DATE) }.getOrNull() ?: return null
            return Temporal(date.atStartOfDay(), allDay = true)
        }
        if (value.endsWith("Z", ignoreCase = true)) {
            val utc = parseUtcDateTime(value) ?: return null
            return Temporal(utc, allDay = false)
        }
        val tzid = prop.params["TZID"]?.trim()?.trim('"')
        val local = parseFloatingDateTime(value) ?: return null
        if (tzid.isNullOrBlank()) return Temporal(local, allDay = false)
        val zoned = runCatching { ZoneId.of(tzid) }.getOrDefault(zone)
        return Temporal(
            ZonedDateTime.of(local, zoned).withZoneSameInstant(zone).toLocalDateTime(),
            allDay = false,
        )
    }

    private fun parseUtcDateTime(value: String): LocalDateTime? {
        val trimmed = value.trim().uppercase().removeSuffix("Z")
        val local = runCatching { LocalDateTime.parse(trimmed, DATE_TIME) }.getOrNull() ?: return null
        return local.atOffset(java.time.ZoneOffset.UTC)
            .atZoneSameInstant(ZONE_OSLO)
            .toLocalDateTime()
    }

    private fun parseFloatingDateTime(value: String): LocalDateTime? {
        val trimmed = value.removeSuffix("Z").uppercase()
        return runCatching { LocalDateTime.parse(trimmed, DATE_TIME) }.getOrNull()
    }

    private fun durationEnd(start: Temporal, duration: String): Temporal? {
        // Google rarely uses DURATION on this feed; support PT#H / PT#M / P#D.
        val m = Regex(
            """^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$""",
            RegexOption.IGNORE_CASE,
        ).find(duration.trim()) ?: return null
        var dt = start.dateTime
        m.groupValues[1].toLongOrNull()?.let { dt = dt.plusDays(it) }
        m.groupValues[2].toLongOrNull()?.let { dt = dt.plusHours(it) }
        m.groupValues[3].toLongOrNull()?.let { dt = dt.plusMinutes(it) }
        m.groupValues[4].toLongOrNull()?.let { dt = dt.plusSeconds(it) }
        return Temporal(dt, allDay = start.allDay)
    }

    private fun parseProperty(line: String): IcsProperty? {
        val colon = line.indexOf(':')
        if (colon < 0) return null
        val head = line.substring(0, colon)
        val value = line.substring(colon + 1)
        val bits = head.split(';')
        val name = bits.first().uppercase()
        val params = linkedMapOf<String, String>()
        for (bit in bits.drop(1)) {
            val eq = bit.indexOf('=')
            if (eq < 0) params[bit.uppercase()] = ""
            else params[bit.substring(0, eq).uppercase()] = bit.substring(eq + 1)
        }
        return IcsProperty(name, params, value)
    }

    internal fun unescape(value: String): String {
        val out = StringBuilder(value.length)
        var i = 0
        while (i < value.length) {
            val c = value[i]
            if (c == '\\' && i + 1 < value.length) {
                when (val n = value[i + 1]) {
                    'n', 'N' -> out.append('\n')
                    ',', ';', '\\' -> out.append(n)
                    else -> out.append(n)
                }
                i += 2
            } else {
                out.append(c)
                i++
            }
        }
        return out.toString()
    }

    private fun stripHtml(value: String): String {
        if ('<' !in value && '&' !in value) return value
        return value
            .replace(Regex("(?i)<br\\s*/?>"), "\n")
            .replace(Regex("<[^>]+>"), "")
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
    }

    internal data class IcsProperty(
        val name: String,
        val params: Map<String, String>,
        val value: String,
    )

    private data class Temporal(val dateTime: LocalDateTime, val allDay: Boolean)

    private data class ParsedEvent(
        val uid: String,
        val title: String,
        val location: String?,
        val description: String?,
        val start: Temporal,
        val end: Temporal,
        val status: EventStatus,
        val rrule: String?,
        val exDates: Set<LocalDateTime>,
    )

    private data class Occurrence(
        val uid: String,
        val title: String,
        val location: String?,
        val description: String?,
        val start: LocalDateTime,
        val end: LocalDateTime,
        val allDay: Boolean,
        val status: EventStatus,
    ) {
        fun toScheduleEvent(idPrefix: String, team: String): ScheduleEvent {
            val stamp = start.format(DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss"))
            return ScheduleEvent(
                id = "$idPrefix$uid/$stamp",
                title = title,
                team = team,
                room = location,
                status = status,
                start = start,
                end = end,
                date = start.toLocalDate(),
                notes = description,
                isAllDay = allDay,
            )
        }
    }

    private enum class Freq { DAILY, WEEKLY, MONTHLY, YEARLY }

    private data class Rrule(
        val freq: Freq,
        val interval: Int,
        val count: Int?,
        val until: LocalDateTime?,
        val byDays: List<DayOfWeek>,
    )
}
