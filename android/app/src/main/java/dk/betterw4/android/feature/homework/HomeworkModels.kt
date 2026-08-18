package dk.betterw4.android.feature.homework

import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.schedule.EventStatus
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The month W4's assessments calendar is showing.
 *
 * W4 takes `month` and `year` as sibling query keys, 1-based, and renders its own links
 * zero-padded (`month=08`).
 */
data class AssessmentMonth(
    val year: Int,
    val month: Int,
) {
    val key: String get() = "%04d-%02d".format(year, month)

    val query: Map<String, String>
        get() = mapOf(
            "month" to "%02d".format(month),
            "year" to year.toString(),
        )

    fun offset(byMonths: Int): AssessmentMonth {
        val next = YearMonth.of(year, month).plusMonths(byMonths.toLong())
        return AssessmentMonth(next.year, next.monthValue)
    }

    fun title(locale: Locale = Locale.UK): String =
        YearMonth.of(year, month).format(DateTimeFormatter.ofPattern("MMMM yyyy", locale))

    companion object {
        fun current(date: LocalDate = W4Dates.today()): AssessmentMonth =
            AssessmentMonth(date.year, date.monthValue)

        fun of(date: LocalDate): AssessmentMonth = AssessmentMonth(date.year, date.monthValue)
    }
}

enum class AssessmentDisplayMode { MONTH, LIST }

data class AssessmentCalendarDay(
    val date: LocalDate,
    val dayNumber: Int,
    val isInMonth: Boolean,
    val isToday: Boolean,
    val total: Int,
    val pending: Int,
    val overdue: Int,
) {
    val hasItems: Boolean get() = total > 0
}

fun assessmentCalendarDays(
    month: AssessmentMonth,
    items: List<HomeworkItem>,
    today: LocalDate = W4Dates.today(),
): List<AssessmentCalendarDay> {
    val first = LocalDate.of(month.year, month.month, 1)
    val leading = first.dayOfWeek.value - 1
    val dayCount = first.lengthOfMonth()
    val cellCount = ((leading + dayCount + 6) / 7) * 7
    val gridStart = first.minusDays(leading.toLong())
    val counts = mutableMapOf<LocalDate, Triple<Int, Int, Int>>()
    for (item in items) {
        val due = item.date ?: continue
        val current = counts[due] ?: Triple(0, 0, 0)
        val pending = current.second + if (!item.done) 1 else 0
        val overdue = current.third + if (!item.done && due.isBefore(today)) 1 else 0
        counts[due] = Triple(current.first + 1, pending, overdue)
    }
    return (0 until cellCount).map { offset ->
        val date = gridStart.plusDays(offset.toLong())
        val (total, pending, overdue) = counts[date] ?: Triple(0, 0, 0)
        AssessmentCalendarDay(
            date = date,
            dayNumber = date.dayOfMonth,
            isInMonth = date.year == month.year && date.monthValue == month.month,
            isToday = date == today,
            total = total,
            pending = pending,
            overdue = overdue,
        )
    }
}

/** Individual lektie item inside a content cell (iOS HomeworkItem). */
data class HomeworkTask(
    val id: String,
    val text: String,
    val url: String? = null,
)

data class HomeworkItem(
    val id: String,
    val note: String,
    val activityTitle: String,
    val date: LocalDate?,
    val team: String = "",
    val teacher: String? = null,
    val room: String? = null,
    val status: EventStatus = EventStatus.NORMAL,
    val done: Boolean = false,
    val href: String? = null,
    val detailHtml: String? = null,
    /** Structured lektier from content cell (iOS items). */
    val tasks: List<HomeworkTask> = emptyList(),
)

data class HomeworkDayGroup(
    val date: LocalDate?,
    val label: String,
    val items: List<HomeworkItem>,
)

fun List<HomeworkItem>.groupedByDate(): List<HomeworkDayGroup> {
    val groups = groupBy { it.date }.toSortedMap(compareBy(nullsLast()) { it })
    return groups.map { (date, items) ->
        HomeworkDayGroup(
            date = date,
            label = date?.toString() ?: "No date",
            items = items.sortedBy { it.activityTitle },
        )
    }
}
