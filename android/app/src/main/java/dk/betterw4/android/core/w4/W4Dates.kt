package dk.betterw4.android.core.w4

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale

/**
 * W4 datepicker / form dates are `dd-M-yy` in en-GB (`14-Aug-2026`).
 */
object W4Dates {
    private val FORMATTERS = listOf(
        DateTimeFormatter.ofPattern("d-MMM-yyyy", Locale.UK),
        DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.UK),
        DateTimeFormatter.ofPattern("d-MMM-yy", Locale.UK),
        DateTimeFormatter.ofPattern("dd-MMM-yy", Locale.UK),
        DateTimeFormatter.ISO_LOCAL_DATE,
        DateTimeFormatter.ofPattern("d/M/yyyy", Locale.UK),
        DateTimeFormatter.ofPattern("dd/MM/yyyy", Locale.UK),
    )

    fun parse(value: String): LocalDate? {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return null
        for (fmt in FORMATTERS) {
            try {
                return LocalDate.parse(trimmed, fmt)
            } catch (_: DateTimeParseException) {
                // try next
            }
        }
        return null
    }

    fun format(date: LocalDate): String =
        date.format(DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.UK))
}
