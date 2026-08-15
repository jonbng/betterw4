package dk.betterlectio.android.feature.schedule

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import dk.betterlectio.android.R

fun ScheduleEvent.timeLabel(context: Context): String = when {
    isAllDay && ScheduleMultiDay.isMultiDay(this) && start != null && end != null -> {
        val range = formatDayMonthRange(start, end)
        "$range · ${context.getString(R.string.event_all_day)}"
    }
    isAllDay -> context.getString(R.string.event_all_day)
    start != null && end != null && ScheduleMultiDay.isMultiDay(this) -> {
        val s = start
        val e = end
        "%d/%d %02d:%02d – %d/%d %02d:%02d".format(
            s.dayOfMonth, s.monthValue, s.hour, s.minute,
            e.dayOfMonth, e.monthValue, e.hour, e.minute,
        )
    }
    start != null && end != null ->
        "%02d:%02d – %02d:%02d".format(start.hour, start.minute, end.hour, end.minute)
    else -> ""
}

private fun formatDayMonthRange(start: java.time.LocalDateTime, end: java.time.LocalDateTime): String {
    val endDay = if (end.toLocalTime() == java.time.LocalTime.MIDNIGHT &&
        end.toLocalDate().isAfter(start.toLocalDate())
    ) {
        end.toLocalDate().minusDays(1)
    } else {
        end.toLocalDate()
    }
    val s = start.toLocalDate()
    return if (s == endDay) {
        "%d/%d".format(s.dayOfMonth, s.monthValue)
    } else {
        "%d/%d – %d/%d".format(s.dayOfMonth, s.monthValue, endDay.dayOfMonth, endDay.monthValue)
    }
}

fun ScheduleEvent.statusLabel(context: Context): String? = when (status) {
    EventStatus.CHANGED -> context.getString(R.string.event_status_changed)
    EventStatus.CANCELLED -> context.getString(R.string.event_status_cancelled)
    EventStatus.NORMAL -> null
}

@Composable
@ReadOnlyComposable
fun ScheduleEvent.timeLabelText(): String {
    val context = LocalContext.current
    return timeLabel(context)
}

@Composable
@ReadOnlyComposable
fun ScheduleEvent.statusLabelText(): String? {
    val context = LocalContext.current
    return statusLabel(context)
}

/** Protocol / identity token for local private events (not for display). */
const val PRIVATE_EVENT_TEAM_TOKEN = "Privat"

/** Stored default title when draft title is blank (matched in canDelete checks). */
const val PRIVATE_EVENT_DEFAULT_TITLE = "Privat aftale"
