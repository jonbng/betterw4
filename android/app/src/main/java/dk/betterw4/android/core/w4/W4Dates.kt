package dk.betterw4.android.core.w4

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * W4 datepicker / form dates are `dd-M-yy` in en-GB (`14-Aug-2026`).
 * Wall clock is always Europe/Oslo — never the phone's zone.
 */
object W4Dates {
    val ZONE: ZoneId = ZoneId.of("Europe/Oslo")

    private val DATE_FORMATTERS = listOf(
        DateTimeFormatter.ofPattern("d-MMM-yyyy", Locale.ENGLISH),
        DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.ENGLISH),
        DateTimeFormatter.ofPattern("d-MMM-yyyy", Locale.UK),
        DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.UK),
        DateTimeFormatter.ofPattern("d-MMM-yy", Locale.ENGLISH),
        DateTimeFormatter.ofPattern("dd-MMM-yy", Locale.ENGLISH),
        DateTimeFormatter.ofPattern("d-MMM-yy", Locale.UK),
        DateTimeFormatter.ofPattern("dd-MMM-yy", Locale.UK),
        DateTimeFormatter.ISO_LOCAL_DATE,
        DateTimeFormatter.ofPattern("d/M/yyyy", Locale.UK),
        DateTimeFormatter.ofPattern("dd/MM/yyyy", Locale.UK),
    )

    private val DATE_TIME_FORMATTERS = listOf(
        DateTimeFormatter.ofPattern("d-MMM-yyyy HH:mm", Locale.UK),
        DateTimeFormatter.ofPattern("dd-MMM-yyyy HH:mm", Locale.UK),
        DateTimeFormatter.ofPattern("d-MMM-yy HH:mm", Locale.UK),
        DateTimeFormatter.ofPattern("dd-MMM-yy HH:mm", Locale.UK),
    )

    fun parse(value: String): LocalDate? {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return null
        for (fmt in DATE_FORMATTERS) {
            try {
                return LocalDate.parse(trimmed, fmt)
            } catch (_: DateTimeParseException) {
                // try next
            }
        }
        return null
    }

    fun parseDateTime(value: String): LocalDateTime? {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return null
        for (fmt in DATE_TIME_FORMATTERS) {
            try {
                return LocalDateTime.parse(trimmed, fmt)
            } catch (_: DateTimeParseException) {
                // try next
            }
        }
        val date = parse(trimmed) ?: return null
        return LocalDateTime.of(date, LocalTime.MIDNIGHT)
    }

    fun format(date: LocalDate): String =
        date.format(DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.UK))

    fun today(): LocalDate = LocalDate.now(ZONE)

    /** Oslo wall-clock "now". Timetable math must never use the phone's zone. */
    fun now(): LocalDateTime = LocalDateTime.now(ZONE)

    fun nowZoned(): ZonedDateTime = ZonedDateTime.now(ZONE)

    /**
     * Milliseconds until the next Europe/Oslo minute. Always at least 1 ms so a
     * ticker cannot spin if it wakes on the exact boundary.
     */
    fun millisUntilNextMinute(now: ZonedDateTime = nowZoned()): Long {
        val next = now.truncatedTo(ChronoUnit.MINUTES).plusMinutes(1)
        return ChronoUnit.MILLIS.between(now, next).coerceAtLeast(1L)
    }
}
