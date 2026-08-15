package dk.betterlectio.android.core.util

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields
import java.util.Locale

object LectioDateUtils {
    /** Lectio HTML / API parsing stays on a fixed Danish locale (server language). */
    private val parseLocale = Locale.forLanguageTag("da-DK")
    private val dMy = DateTimeFormatter.ofPattern("d/M-yyyy", parseLocale)
    private val dM = DateTimeFormatter.ofPattern("d/M", parseLocale)
    private val hm = DateTimeFormatter.ofPattern("H:mm", parseLocale)
    private val hmPadded = DateTimeFormatter.ofPattern("HH:mm", parseLocale)

    /** Active app locale for user-facing date labels. */
    private fun displayLocale(): Locale = Locale.getDefault()

    fun isoWeek(date: LocalDate = LocalDate.now()): Int =
        date.get(WeekFields.ISO.weekOfWeekBasedYear())

    fun isoWeekYear(date: LocalDate = LocalDate.now()): Int =
        date.get(WeekFields.ISO.weekBasedYear())

    fun weekStart(year: Int, week: Int): LocalDate =
        LocalDate.of(year, 1, 4)
            .with(WeekFields.ISO.weekOfWeekBasedYear(), week.toLong())
            .with(DayOfWeek.MONDAY)

    /**
     * Parse Lectio date/time strings used across schedule, homework, messages, etc.
     *
     * Supported (iOS + Flutter parity):
     * - `d/M-yyyy HH:mm`, `d/M-yyyy`
     * - `dd-MM-yyyy HH:mm:ss`, `dd-MM-yyyy HH:mm`
     * - `d/M HH:mm`, `d/M`
     * - Weekday-prefixed homework dates: `fr 13/3`, `ma 16/3`
     * - `i dag HH:mm`
     */
    fun parseLectioDate(raw: String, defaultYear: Int = LocalDate.now().year): LocalDateTime? {
        val t = raw.trim()
        if (t.isEmpty()) return null

        // Homework overview: "fr 13/3" / "ma 16/3" (iOS parseHomeworkDate, Flutter formatTwo)
        parseWeekdayPrefixedDate(t, defaultYear)?.let { return it.atStartOfDay() }

        listOf(
            "d/M-yyyy HH:mm",
            "dd-MM-yyyy HH:mm:ss",
            "dd-MM-yyyy HH:mm",
            "d/M-yyyy",
            "d/M HH:mm",
            "d/M",
            "HH:mm",
            "H:mm",
        ).forEach { pattern ->
            try {
                val fmt = DateTimeFormatter.ofPattern(pattern, parseLocale)
                return when {
                    pattern.contains("H") && pattern.contains("yyyy") ->
                        LocalDateTime.parse(t, fmt)
                    pattern.contains("H") && pattern.contains("M") && !pattern.contains("y") ->
                        LocalDateTime.parse(t, DateTimeFormatter.ofPattern("d/M H:mm", parseLocale))
                            .withYear(defaultYear)
                    pattern == "HH:mm" || pattern == "H:mm" ->
                        LocalDateTime.of(LocalDate.now(), LocalTime.parse(t, fmt))
                    pattern.contains("y") -> LocalDate.parse(t, fmt).atStartOfDay()
                    else -> LocalDate.parse(t, fmt).withYear(defaultYear).atStartOfDay()
                }
            } catch (_: Exception) {
                // try next
            }
        }
        // "i dag 12:00" / weekday forms — best effort
        val todayMatch = Regex("""i dag\s+(\d{1,2}:\d{2})""", RegexOption.IGNORE_CASE).find(t)
        if (todayMatch != null) {
            val time = parseLocalTime(todayMatch.groupValues[1]) ?: return null
            return LocalDateTime.of(LocalDate.now(), time)
        }
        return null
    }

    /**
     * iOS/Flutter homework date: `"fr 13/3"` or `"ma 16/3"` → day/month in [defaultYear].
     * Also accepts `"13/3"` alone after a weekday token was already stripped.
     */
    fun parseWeekdayPrefixedDate(raw: String, defaultYear: Int = LocalDate.now().year): LocalDate? {
        val t = raw.trim()
        if (t.isEmpty()) return null
        // Optional 1–3 letter weekday token, then d/M or d/M-yyyy
        val m = Regex(
            """^(?:[a-zA-ZæøåÆØÅ]{1,3}\s+)?(\d{1,2})/(\d{1,2})(?:-(\d{4}))?$""",
        ).find(t) ?: return null
        val day = m.groupValues[1].toIntOrNull() ?: return null
        val month = m.groupValues[2].toIntOrNull() ?: return null
        val year = m.groupValues[3].toIntOrNull() ?: defaultYear
        return runCatching { LocalDate.of(year, month, day) }.getOrNull()
    }

    fun parseTimeRange(line: String): Pair<LocalTime, LocalTime>? {
        // Prefer "til" / dash ranges (iOS extractTimes), fall back to first two times.
        val til = Regex("""(\d{1,2}:\d{2})\s+til\s+(\d{1,2}:\d{2})""", RegexOption.IGNORE_CASE)
            .find(line)
        if (til != null) {
            val a = parseLocalTime(til.groupValues[1])
            val b = parseLocalTime(til.groupValues[2])
            if (a != null && b != null) return a to b
        }
        val dash = Regex("""(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})""").find(line)
        if (dash != null) {
            val a = parseLocalTime(dash.groupValues[1])
            val b = parseLocalTime(dash.groupValues[2])
            if (a != null && b != null) return a to b
        }
        val times = Regex("""(\d{1,2}:\d{2})""").findAll(line).map { it.groupValues[1] }.toList()
        if (times.size < 2) return null
        val a = parseLocalTime(times[0]) ?: return null
        val b = parseLocalTime(times[1]) ?: return null
        return a to b
    }

    private fun parseLocalTime(raw: String): LocalTime? =
        runCatching { LocalTime.parse(raw, hm) }.getOrNull()
            ?: runCatching { LocalTime.parse(raw, hmPadded) }.getOrNull()

    fun formatHm(time: LocalTime): String = time.format(hmPadded)

    fun formatShortDate(date: LocalDate): String =
        date.format(DateTimeFormatter.ofPattern("EEE d/M", displayLocale()))
}
