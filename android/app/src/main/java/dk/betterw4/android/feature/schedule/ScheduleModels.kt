package dk.betterw4.android.feature.schedule

import java.time.LocalDate
import java.time.LocalDateTime

enum class EventStatus { NORMAL, CHANGED, CANCELLED }

data class ScheduleEvent(
    val id: String,
    val title: String,
    val team: String = "",
    val teacher: String? = null,
    /** Teacher UWC id (`nc16jmac`) when the period href carries one. */
    val teacherId: String? = null,
    val room: String? = null,
    val status: EventStatus = EventStatus.NORMAL,
    val start: LocalDateTime? = null,
    val end: LocalDateTime? = null,
    val date: LocalDate,
    val notes: String? = null,
    val homework: String? = null,
    val isAllDay: Boolean = false,
    val href: String? = null,
    /** Flutter `ls-lektier` icon on brick. */
    val hasHomeworkIcon: Boolean = false,
    /** Flutter `ls-note` icon on brick. */
    val hasNoteIcon: Boolean = false,
    /** `ac` / `ea` / `gcal` / `local` — prefixes event ids after an AC+EA merge (B20). */
    val source: String = "ac",
)

data class ScheduleDay(
    val date: LocalDate,
    val events: List<ScheduleEvent>,
    val informations: List<String> = emptyList(),
    val dayName: String? = null,
    val rotationDay: String? = null,
    val isNoClasses: Boolean = false,
    val eaNote: String? = null,
    val isToday: Boolean = false,
)

data class ScheduleWeek(
    val year: Int,
    val week: Int,
    val days: List<ScheduleDay>,
    val title: String? = null,
    val source: String = "ac",
    val startHour: Int = 7,
    val endHour: Int = 22,
)
