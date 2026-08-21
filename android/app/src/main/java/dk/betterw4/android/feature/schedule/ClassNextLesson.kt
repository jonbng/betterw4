package dk.betterw4.android.feature.schedule

import java.time.LocalDateTime

/**
 * The next (or this week's first) timetable block for a class, from a week
 * that is already in the cache. No network.
 */
data class ClassNextLesson(
    val start: LocalDateTime,
    val room: String? = null,
)

object ClassNextLessons {
    fun next(week: ScheduleWeek, classId: String, now: LocalDateTime): ClassNextLesson? =
        map(week, now)[classId.lowercase()]

    /** One entry per class id found on the week, keyed lowercased. */
    fun map(week: ScheduleWeek, now: LocalDateTime): Map<String, ClassNextLesson> {
        val grouped = linkedMapOf<String, MutableList<ScheduleEvent>>()
        for (day in week.days) {
            for (event in day.events) {
                val classId = ClassRoster.classId(event.href, event.team) ?: continue
                val start = event.start ?: continue
                if (event.isAllDay) continue
                if (event.status == EventStatus.CANCELLED) continue
                grouped.getOrPut(classId.lowercase()) { mutableListOf() }.add(event)
            }
        }
        val result = linkedMapOf<String, ClassNextLesson>()
        for ((id, events) in grouped) {
            val picked = pick(events, now) ?: continue
            result[id] = ClassNextLesson(
                start = picked.start ?: now,
                room = picked.room?.trim()?.takeIf { it.isNotEmpty() },
            )
        }
        return result
    }

    private fun pick(events: List<ScheduleEvent>, now: LocalDateTime): ScheduleEvent? {
        val ordered = events.sortedBy { it.start }
        return ordered.firstOrNull { event ->
            val start = event.start ?: return@firstOrNull false
            !start.isBefore(now)
        } ?: ordered.firstOrNull()
    }
}
