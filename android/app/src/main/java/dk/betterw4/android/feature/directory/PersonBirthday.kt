package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Dates
import java.time.LocalDate
import java.time.Month
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * Birthday as printed on a public profile (`28-Jan`, `17-Nov`, `3 March`,
 * `1 January 2008`). Year is usually omitted; the interesting number is how
 * many days until the next occurrence.
 */
data class PersonBirthday(
    val raw: String,
    val month: Int,
    val day: Int,
    /** Day + full English month (`28 January`), never the year. */
    val display: String,
) {
    fun daysUntil(today: LocalDate = W4Dates.today()): Int {
        val thisYear = dateIn(today.year)
        if (thisYear == today) return 0
        if (thisYear.isAfter(today)) return ChronoUnit.DAYS.between(today, thisYear).toInt()
        return ChronoUnit.DAYS.between(today, dateIn(today.year + 1)).toInt()
    }

    fun isToday(today: LocalDate = W4Dates.today()): Boolean = daysUntil(today) == 0
    fun isTomorrow(today: LocalDate = W4Dates.today()): Boolean = daysUntil(today) == 1

    private fun dateIn(year: Int): LocalDate {
        val length = YearMonth.of(year, month).lengthOfMonth()
        return LocalDate.of(year, month, day.coerceAtMost(length))
    }

    companion object {
        private val DISPLAY = DateTimeFormatter.ofPattern("d MMMM", Locale.UK)
        private val MONTH_DAY = listOf(
            DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.UK),
            DateTimeFormatter.ofPattern("d MMM yyyy", Locale.UK),
            DateTimeFormatter.ofPattern("d-MMM", Locale.UK),
            DateTimeFormatter.ofPattern("dd-MMM", Locale.UK),
            DateTimeFormatter.ofPattern("d MMM", Locale.UK),
            DateTimeFormatter.ofPattern("dd MMM", Locale.UK),
            DateTimeFormatter.ofPattern("d MMMM", Locale.UK),
            DateTimeFormatter.ofPattern("dd MMMM", Locale.UK),
        )

        fun parse(raw: String?): PersonBirthday? {
            val trimmed = raw?.replace('\u00a0', ' ')?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            val date = parseDate(trimmed) ?: return null
            return PersonBirthday(
                raw = trimmed,
                month = date.monthValue,
                day = date.dayOfMonth,
                display = date.format(DISPLAY),
            )
        }

        private fun parseDate(raw: String): LocalDate? {
            W4Dates.parse(raw)?.let { return it }
            for (suffix in listOf(" 2024", "-2024")) {
                W4Dates.parse(raw + suffix)?.let { return it }
            }
            for (fmt in MONTH_DAY) {
                try {
                    val parsed = fmt.parse(raw)
                    val month = Month.from(parsed)
                    val day = parsed.get(java.time.temporal.ChronoField.DAY_OF_MONTH)
                    return LocalDate.of(2024, month, day)
                } catch (_: DateTimeParseException) {
                    // try next
                } catch (_: java.time.DateTimeException) {
                    // try next
                }
            }
            return null
        }
    }
}
