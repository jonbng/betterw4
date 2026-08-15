package dk.betterlectio.android.feature.schedule

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Session-local private events overlay used by [ScheduleRepository].
 * JVM-testable create/delete/snapshot without Android or Lectio HTTP.
 */
class LocalPrivateEvents {
    private val events = CopyOnWriteArrayList<ScheduleEvent>()

    fun snapshot(): List<ScheduleEvent> = events.toList()

    fun clear() = events.clear()

    fun add(event: ScheduleEvent) {
        events.add(event)
    }

    /** Remove by id; returns true if something was removed. */
    fun delete(eventId: String): Boolean = events.removeAll { it.id == eventId }

    fun contains(eventId: String): Boolean = events.any { it.id == eventId }

    fun get(eventId: String): ScheduleEvent? = events.firstOrNull { it.id == eventId }

    /**
     * Build a private event the same way [ScheduleRepository.createPrivateEvent] does for demo.
     */
    fun createFromDraft(
        draft: PrivateEventDraft,
        id: String = "local-private-${System.currentTimeMillis()}",
        nowDate: LocalDate = LocalDate.now(),
    ): ScheduleEvent {
        val event = draftToEvent(draft, id, nowDate)
        add(event)
        return event
    }

    /**
     * Replace an existing local private event by [id] (or insert if missing).
     */
    fun updateFromDraft(
        id: String,
        draft: PrivateEventDraft,
        nowDate: LocalDate = LocalDate.now(),
    ): ScheduleEvent {
        val event = draftToEvent(draft, id, nowDate)
        delete(id)
        add(event)
        return event
    }

    fun draftToEvent(
        draft: PrivateEventDraft,
        id: String,
        nowDate: LocalDate = LocalDate.now(),
    ): ScheduleEvent {
        val startDate = parseDraftDate(draft.startDate) ?: nowDate
        val endDate = parseDraftDate(draft.endDate) ?: startDate
        val startTime = parseDraftTime(draft.startTime) ?: LocalTime.of(8, 0)
        val endTime = parseDraftTime(draft.endTime) ?: LocalTime.of(9, 0)
        return ScheduleEvent(
            id = id,
            // Default title/team are stable tokens; UI localizes display via private_event_* strings.
            title = draft.title.ifBlank { PRIVATE_EVENT_DEFAULT_TITLE },
            team = PRIVATE_EVENT_TEAM_TOKEN,
            notes = draft.note.ifBlank { null },
            start = LocalDateTime.of(startDate, startTime),
            end = LocalDateTime.of(endDate, endTime),
            date = startDate,
            isAllDay = false,
            href = null,
        )
    }

    fun mergeIntoWeek(week: ScheduleWeek): ScheduleWeek {
        if (events.isEmpty()) return week
        // Expand multi-day private events onto every covered day before merging.
        val expanded = events.flatMap { ScheduleMultiDay.expandEventAcrossDays(it) }
        val byDate = expanded.groupBy { it.date }
        val days = week.days.map { day ->
            val extra = byDate[day.date].orEmpty()
            if (extra.isEmpty()) day
            else {
                day.copy(
                    events = (extra + day.events)
                        .distinctBy { it.id.ifBlank { "${it.title}|${it.start}|${it.end}" } }
                        .sortedBy { it.start ?: LocalDateTime.MIN },
                )
            }
        }.toMutableList()
        byDate.forEach { (date, list) ->
            if (days.none { it.date == date }) {
                days += ScheduleDay(date, list)
            }
        }
        return week.copy(days = days.sortedBy { it.date })
    }

    companion object {
        fun parseDraftDate(raw: String): LocalDate? {
            val m = Regex("""(\d{1,2})/(\d{1,2})-(\d{4})""").find(raw.trim()) ?: return null
            return runCatching {
                LocalDate.of(m.groupValues[3].toInt(), m.groupValues[2].toInt(), m.groupValues[1].toInt())
            }.getOrNull()
        }

        fun parseDraftTime(raw: String): LocalTime? {
            val m = Regex("""(\d{1,2}):(\d{2})""").find(raw.trim()) ?: return null
            return runCatching {
                LocalTime.of(m.groupValues[1].toInt(), m.groupValues[2].toInt())
            }.getOrNull()
        }
    }
}
