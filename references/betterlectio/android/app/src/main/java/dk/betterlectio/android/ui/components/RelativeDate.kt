package dk.betterlectio.android.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import dk.betterlectio.android.R
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

/**
 * Relative due labels for homework / assignments lists.
 */
@Composable
fun relativeDueLabel(
    date: LocalDate?,
    today: LocalDate = LocalDate.now(),
): String? {
    date ?: return null
    return when (val days = ChronoUnit.DAYS.between(today, date)) {
        0L -> stringResource(R.string.due_today)
        1L -> stringResource(R.string.due_tomorrow)
        -1L -> stringResource(R.string.due_yesterday)
        in Long.MIN_VALUE..-2L -> stringResource(R.string.due_overdue_days, -days)
        in 2L..6L -> stringResource(R.string.due_in_days, days)
        else -> {
            val fmt = DateTimeFormatter.ofPattern("d. MMM", Locale.getDefault())
            date.format(fmt)
        }
    }
}

@Composable
fun relativeDueLabel(
    dateTime: LocalDateTime?,
    today: LocalDate = LocalDate.now(),
): String? = relativeDueLabel(dateTime?.toLocalDate(), today)

/** Whether a due date should be styled as urgent (overdue or today). */
fun isDueUrgent(date: LocalDate?, today: LocalDate = LocalDate.now()): Boolean {
    date ?: return false
    return !date.isAfter(today)
}

fun isDueUrgent(dateTime: LocalDateTime?, today: LocalDate = LocalDate.now()): Boolean =
    isDueUrgent(dateTime?.toLocalDate(), today)

@Composable
fun relativeDaySectionLabel(
    date: LocalDate?,
    today: LocalDate = LocalDate.now(),
): String {
    date ?: return stringResource(R.string.due_no_date)
    return when (val days = ChronoUnit.DAYS.between(today, date)) {
        0L -> stringResource(R.string.due_today)
        1L -> stringResource(R.string.due_tomorrow)
        -1L -> stringResource(R.string.due_yesterday)
        else -> {
            val fmt = DateTimeFormatter.ofPattern("EEEE d. MMM", Locale.getDefault())
            date.format(fmt).replaceFirstChar {
                if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
            }
        }
    }
}
