package dk.betterw4.android.feature.notifications

import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.homework.HomeworkItem
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.trips.W4Trip
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * On-device notification diffs.
 *
 * W4 has no Lectio-style `s2cancelled` / `s2changed` brick classes — the
 * captured stylesheet only styles attendance (`.present` / `.absence` /
 * `.prearranged`). Timetable "moved" is therefore a fingerprint of
 * start/end/room for the same class on the same day, compared across polls.
 */
object NotificationDiff {
    const val HORIZON_HOURS = 48L
    const val MAX_PER_CATEGORY = 5

    enum class LessonChangeKind { CANCELLED, MOVED, ROOM, CHANGED }

    enum class AssessmentChangeKind { NEW, OVERDUE }

    enum class TripChangeKind { NEW, STATUS }

    data class LessonWatch(
        val identity: String,
        val title: String,
        val timeLabel: String,
        val room: String?,
        val fingerprint: String,
        val startEpochMinute: Long,
        val endEpochMinute: Long,
    )

    data class AssessmentWatch(
        val id: String,
        val title: String,
        val subtitle: String?,
        val state: String,
    )

    data class TripWatch(
        val id: String,
        val name: String,
        val status: String,
    )

    data class LessonChange(
        val identity: String,
        val title: String,
        val kind: LessonChangeKind,
        val timeLabel: String,
        val detail: String?,
    )

    data class AssessmentChange(
        val id: String,
        val title: String,
        val kind: AssessmentChangeKind,
        val subtitle: String?,
    )

    data class TripChange(
        val id: String,
        val name: String,
        val kind: TripChangeKind,
        val status: String,
    )

    data class Snapshot(
        val lessons: List<LessonWatch> = emptyList(),
        val assessments: List<AssessmentWatch> = emptyList(),
        val trips: List<TripWatch> = emptyList(),
    )

    fun watchLessons(
        events: List<ScheduleEvent>,
        now: LocalDateTime = W4Dates.now(),
        horizonHours: Long = HORIZON_HOURS,
    ): List<LessonWatch> {
        val horizon = now.plusHours(horizonHours)
        val grouped = linkedMapOf<String, MutableList<ScheduleEvent>>()
        for (event in events) {
            if (event.isAllDay) continue
            if (event.source == "gcal" || event.source == "local") continue
            val start = event.start ?: continue
            val end = event.end ?: start.plusMinutes(45)
            if (!end.isAfter(now)) continue
            if (start.isAfter(horizon)) continue
            grouped.getOrPut(lessonIdentity(event)) { mutableListOf() }.add(event)
        }
        return grouped.map { (identity, group) ->
            val ordered = group.sortedBy { it.start }
            val first = ordered.first()
            val last = ordered.last()
            val start = first.start ?: now
            val end = last.end ?: start
            LessonWatch(
                identity = identity,
                title = first.title,
                timeLabel = timeLabel(ordered),
                room = uniqueRooms(ordered),
                fingerprint = fingerprint(ordered),
                startEpochMinute = start.toEpochMinute(),
                endEpochMinute = end.toEpochMinute(),
            )
        }
    }

    fun watchAssessments(
        items: List<HomeworkItem>,
        today: LocalDate = W4Dates.today(),
    ): List<AssessmentWatch> {
        return items.mapNotNull { item ->
            if (isStudentCreated(item)) return@mapNotNull null
            val overdue = isOverdue(item, today)
            val state = when {
                item.done -> "done"
                overdue -> "overdue"
                else -> "pending"
            }
            AssessmentWatch(
                id = item.id,
                title = item.activityTitle,
                subtitle = item.note.ifBlank { null },
                state = state,
            )
        }
    }

    fun watchTrips(trips: List<W4Trip>): List<TripWatch> {
        return trips.map { trip ->
            TripWatch(
                id = trip.id,
                name = trip.name,
                status = normalizeTripStatus(trip.status),
            )
        }
    }

    fun diffLessons(
        previous: List<LessonWatch>,
        current: List<LessonWatch>,
        now: LocalDateTime = W4Dates.now(),
    ): List<LessonChange> {
        val currentById = current.associateBy { it.identity }
        val nowMinute = now.toEpochMinute()
        val changes = mutableListOf<LessonChange>()
        for (before in previous) {
            if (before.endEpochMinute <= nowMinute) continue
            val after = currentById[before.identity]
            if (after == null) {
                changes += LessonChange(
                    identity = before.identity,
                    title = before.title,
                    kind = LessonChangeKind.CANCELLED,
                    timeLabel = before.timeLabel,
                    detail = before.room,
                )
                continue
            }
            if (after.fingerprint == before.fingerprint) continue
            changes += LessonChange(
                identity = before.identity,
                title = after.title,
                kind = lessonKind(before, after),
                timeLabel = after.timeLabel,
                detail = after.room,
            )
        }
        return changes.take(MAX_PER_CATEGORY)
    }

    fun diffAssessments(
        previous: List<AssessmentWatch>,
        current: List<AssessmentWatch>,
    ): List<AssessmentChange> {
        val previousById = previous.associateBy { it.id }
        val changes = mutableListOf<AssessmentChange>()
        for (item in current) {
            if (item.state == "done") continue
            val before = previousById[item.id]
            when {
                before == null && item.state == "pending" -> {
                    changes += AssessmentChange(item.id, item.title, AssessmentChangeKind.NEW, item.subtitle)
                }
                before == null && item.state == "overdue" -> {
                    changes += AssessmentChange(item.id, item.title, AssessmentChangeKind.OVERDUE, item.subtitle)
                }
                before != null && before.state != "overdue" && item.state == "overdue" -> {
                    changes += AssessmentChange(item.id, item.title, AssessmentChangeKind.OVERDUE, item.subtitle)
                }
            }
        }
        return changes.take(MAX_PER_CATEGORY)
    }

    fun diffTrips(
        previous: List<TripWatch>,
        current: List<TripWatch>,
    ): List<TripChange> {
        val previousById = previous.associateBy { it.id }
        val changes = mutableListOf<TripChange>()
        for (trip in current) {
            val before = previousById[trip.id]
            when {
                before == null -> {
                    changes += TripChange(trip.id, trip.name, TripChangeKind.NEW, trip.status)
                }
                before.status != trip.status -> {
                    changes += TripChange(trip.id, trip.name, TripChangeKind.STATUS, trip.status)
                }
            }
        }
        return changes.take(MAX_PER_CATEGORY)
    }

    fun encode(snapshot: Snapshot): Set<String> {
        val keys = linkedSetOf<String>()
        for (lesson in snapshot.lessons) {
            keys += listOf(
                "L",
                lesson.identity,
                lesson.fingerprint,
                lesson.title,
                lesson.timeLabel,
                lesson.room.orEmpty(),
                lesson.startEpochMinute.toString(),
                lesson.endEpochMinute.toString(),
            ).joinToString(RS)
        }
        for (item in snapshot.assessments) {
            keys += listOf("A", item.id, item.state, item.title, item.subtitle.orEmpty())
                .joinToString(RS)
        }
        for (trip in snapshot.trips) {
            keys += listOf("T", trip.id, trip.status, trip.name).joinToString(RS)
        }
        return keys
    }

    fun decode(keys: Set<String>): Snapshot {
        val lessons = mutableListOf<LessonWatch>()
        val assessments = mutableListOf<AssessmentWatch>()
        val trips = mutableListOf<TripWatch>()
        for (raw in keys) {
            val parts = raw.split(RS)
            when (parts.firstOrNull()) {
                "L" -> if (parts.size >= 8) {
                    lessons += LessonWatch(
                        identity = parts[1],
                        title = parts[3],
                        timeLabel = parts[4],
                        room = parts[5].ifBlank { null },
                        fingerprint = parts[2],
                        startEpochMinute = parts[6].toLongOrNull() ?: 0L,
                        endEpochMinute = parts[7].toLongOrNull() ?: 0L,
                    )
                }
                "A" -> if (parts.size >= 5) {
                    assessments += AssessmentWatch(
                        id = parts[1],
                        title = parts[3],
                        subtitle = parts[4].ifBlank { null },
                        state = parts[2],
                    )
                }
                "T" -> if (parts.size >= 4) {
                    trips += TripWatch(
                        id = parts[1],
                        name = parts[3],
                        status = parts[2],
                    )
                }
            }
        }
        return Snapshot(lessons = lessons, assessments = assessments, trips = trips)
    }

    internal fun lessonIdentity(event: ScheduleEvent): String {
        val classKey = event.team.ifBlank { event.title }.trim().lowercase(Locale.ROOT)
        return "${event.source}|${event.date}|$classKey"
    }

    internal fun normalizeTripStatus(raw: String): String {
        val text = raw.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]+"), " ").trim()
        return when {
            text.contains("pending") || text.contains("awaiting") ||
                text.contains("for confirmation") || text.contains("submitted") -> "pending"
            text.contains("cancel") || text.contains("rejected") || text.contains("declined") ||
                text.contains("withdrawn") || text.contains("not approved") -> "cancelled"
            text.contains("approved") || text.contains("confirmed") || text.contains("accepted") -> "approved"
            text.contains("planning") || text.contains("planned") || text.contains("draft") -> "planning"
            text.isBlank() -> "unknown"
            else -> text
        }
    }

    internal fun isStudentCreated(item: HomeworkItem): Boolean =
        item.id.startsWith("student:") || item.href.equals("student", ignoreCase = true)

    internal fun isOverdue(item: HomeworkItem, today: LocalDate): Boolean {
        if (item.done) return false
        if (item.date?.isBefore(today) == true) return true
        return item.note.contains("overdue", ignoreCase = true)
    }

    private fun fingerprint(events: List<ScheduleEvent>): String {
        return events.sortedBy { it.start }.joinToString(";") { event ->
            val start = event.start?.format(HM) ?: ""
            val end = event.end?.format(HM) ?: ""
            val room = event.room.orEmpty().trim().lowercase(Locale.ROOT)
            "$start-$end|$room"
        }
    }

    private fun timeLabel(events: List<ScheduleEvent>): String {
        val first = events.first().start ?: return ""
        val last = events.last().end ?: events.last().start ?: first
        return "${first.format(HM)}–${last.format(HM)}"
    }

    private fun uniqueRooms(events: List<ScheduleEvent>): String? {
        val rooms = events.mapNotNull { it.room?.trim()?.ifBlank { null } }.distinct()
        return rooms.singleOrNull() ?: rooms.takeIf { it.isNotEmpty() }?.joinToString(", ")
    }

    private fun lessonKind(before: LessonWatch, after: LessonWatch): LessonChangeKind {
        return when {
            before.startEpochMinute != after.startEpochMinute ||
                before.timeLabel != after.timeLabel -> LessonChangeKind.MOVED
            before.room != after.room -> LessonChangeKind.ROOM
            else -> LessonChangeKind.CHANGED
        }
    }

    private fun LocalDateTime.toEpochMinute(): Long =
        toLocalDate().toEpochDay() * 24 * 60 + hour * 60L + minute

    private val HM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    /** Record separator — titles can contain `|` but almost never this. */
    private const val RS = "\u001e"
}
