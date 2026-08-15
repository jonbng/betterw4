package dk.betterlectio.android.feature.live

import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import java.time.Duration
import java.time.LocalDateTime

/**
 * Pure helpers for scheduling live-lesson boundary refresh (start/end of lessons).
 * Testable without Android framework.
 */
object LiveLessonBoundary {
    const val UPCOMING_WINDOW_MINUTES = 60L

    enum class Phase { UPCOMING, CURRENT }

    data class Projection(
        val phase: Phase,
        val event: ScheduleEvent,
        val target: LocalDateTime,
        val minutesRemaining: Int,
        val progress: Float?,
        val nextLesson: ScheduleEvent?,
    )

    data class Boundary(
        val at: LocalDateTime,
        val eventId: String,
        val kind: Kind,
        val title: String,
    ) {
        enum class Kind { START, END }
    }

    fun project(
        events: List<ScheduleEvent>,
        now: LocalDateTime = LocalDateTime.now(),
    ): Projection? {
        val timed = eligibleEvents(events)
        val current = timed
            .filter { event ->
                val start = event.start!!
                val end = event.end!!
                !now.isBefore(start) && now.isBefore(end)
            }
            .minByOrNull { it.start!! }

        if (current != null) {
            val start = current.start!!
            val end = current.end!!
            val durationMs = Duration.between(start, end).toMillis().coerceAtLeast(1L)
            val elapsedMs = Duration.between(start, now).toMillis().coerceAtLeast(0L)
            val next = timed
                .filter { it.id != current.id && !it.start!!.isBefore(end) }
                .minByOrNull { it.start!! }
            return Projection(
                phase = Phase.CURRENT,
                event = current,
                target = end,
                minutesRemaining = roundedUpMinutes(now, end),
                progress = (elapsedMs.toFloat() / durationMs).coerceIn(0f, 1f),
                nextLesson = next,
            )
        }

        val upcoming = timed
            .filter { it.start!!.isAfter(now) }
            .minByOrNull { it.start!! }
            ?: return null
        val upcomingStart = upcoming.start!!
        if (Duration.between(now, upcomingStart) > Duration.ofMinutes(UPCOMING_WINDOW_MINUTES)) {
            return null
        }

        return Projection(
            phase = Phase.UPCOMING,
            event = upcoming,
            target = upcomingStart,
            minutesRemaining = roundedUpMinutes(now, upcomingStart),
            progress = null,
            nextLesson = null,
        )
    }

    fun nextRefreshBoundary(
        events: List<ScheduleEvent>,
        now: LocalDateTime = LocalDateTime.now(),
    ): Boundary? = eligibleEvents(events)
        .flatMap { event ->
            val start = event.start!!
            listOf(
                Boundary(
                    at = start.minusMinutes(UPCOMING_WINDOW_MINUTES),
                    eventId = event.id,
                    kind = Boundary.Kind.START,
                    title = event.title,
                ),
                Boundary(start, event.id, Boundary.Kind.START, event.title),
                Boundary(event.end!!, event.id, Boundary.Kind.END, event.title),
            )
        }
        .filter { it.at.isAfter(now) }
        .minWithOrNull(compareBy({ it.at }, { it.eventId }, { it.kind.name }))

    /**
     * Next boundary at or after [now] among timed events (start or end).
     */
    fun nextBoundary(
        events: List<ScheduleEvent>,
        now: LocalDateTime = LocalDateTime.now(),
    ): Boundary? {
        val candidates = mutableListOf<Boundary>()
        for (e in eligibleEvents(events)) {
            val s = e.start ?: continue
            val en = e.end ?: continue
            if (!s.isBefore(now)) {
                candidates += Boundary(s, e.id, Boundary.Kind.START, e.title)
            }
            if (!en.isBefore(now)) {
                candidates += Boundary(en, e.id, Boundary.Kind.END, e.title)
            }
        }
        return candidates.minByOrNull { it.at }
    }

    /** All boundaries in chronological order at/after [now]. */
    fun upcomingBoundaries(
        events: List<ScheduleEvent>,
        now: LocalDateTime = LocalDateTime.now(),
        limit: Int = 8,
    ): List<Boundary> {
        val candidates = mutableListOf<Boundary>()
        for (e in eligibleEvents(events)) {
            val s = e.start ?: continue
            val en = e.end ?: continue
            if (!s.isBefore(now)) {
                candidates += Boundary(s, e.id, Boundary.Kind.START, e.title)
            }
            if (!en.isBefore(now)) {
                candidates += Boundary(en, e.id, Boundary.Kind.END, e.title)
            }
        }
        return candidates
            .sortedWith(compareBy({ it.at }, { it.eventId }, { it.kind.name }))
            .distinctBy { Triple(it.at, it.eventId, it.kind) }
            .take(limit)
    }

    fun currentLesson(
        events: List<ScheduleEvent>,
        now: LocalDateTime = LocalDateTime.now(),
    ): ScheduleEvent? = eligibleEvents(events).firstOrNull { e ->
        val s = e.start
        val en = e.end
        s != null && en != null && !now.isBefore(s) && now.isBefore(en)
    }

    private fun eligibleEvents(events: List<ScheduleEvent>): List<ScheduleEvent> =
        events.filter { event ->
            val start = event.start
            val end = event.end
            event.status != EventStatus.CANCELLED &&
                !event.isAllDay &&
                start != null &&
                end != null &&
                end.isAfter(start)
        }

    private fun roundedUpMinutes(from: LocalDateTime, to: LocalDateTime): Int {
        val seconds = Duration.between(from, to).seconds.coerceAtLeast(0L)
        return ((seconds + 59L) / 60L).toInt()
    }
}
