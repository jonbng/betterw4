package dk.betterlectio.android.feature.homework

import dk.betterlectio.android.feature.schedule.EventStatus
import java.time.LocalDate

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
            label = date?.toString() ?: "Uden dato",
            items = items.sortedBy { it.activityTitle },
        )
    }
}
