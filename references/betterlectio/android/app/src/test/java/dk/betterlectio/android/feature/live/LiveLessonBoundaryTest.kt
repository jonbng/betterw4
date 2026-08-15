package dk.betterlectio.android.feature.live

import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.EventStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class LiveLessonBoundaryTest {
    private val day = LocalDate.of(2026, 3, 10)

    private fun event(
        id: String,
        startH: Int,
        startM: Int,
        endH: Int,
        endM: Int,
        status: EventStatus = EventStatus.NORMAL,
        isAllDay: Boolean = false,
    ) = ScheduleEvent(
        id = id,
        title = id,
        start = LocalDateTime.of(day, LocalTime.of(startH, startM)),
        end = LocalDateTime.of(day, LocalTime.of(endH, endM)),
        date = day,
        status = status,
        isAllDay = isAllDay,
    )

    @Test
    fun nextBoundary_prefers_soonest_start_or_end() {
        val events = listOf(
            event("a", 8, 0, 9, 0),
            event("b", 10, 0, 11, 0),
        )
        val now = LocalDateTime.of(day, LocalTime.of(7, 30))
        val next = LiveLessonBoundary.nextBoundary(events, now)
        assertNotNull(next)
        assertEquals("a", next!!.eventId)
        assertEquals(LiveLessonBoundary.Boundary.Kind.START, next.kind)
    }

    @Test
    fun nextBoundary_during_lesson_returns_end() {
        val events = listOf(event("a", 8, 0, 9, 0))
        val now = LocalDateTime.of(day, LocalTime.of(8, 30))
        val next = LiveLessonBoundary.nextBoundary(events, now)
        assertNotNull(next)
        assertEquals(LiveLessonBoundary.Boundary.Kind.END, next!!.kind)
    }

    @Test
    fun currentLesson_detects_ongoing() {
        val events = listOf(event("a", 8, 0, 9, 0), event("b", 10, 0, 11, 0))
        val now = LocalDateTime.of(day, LocalTime.of(8, 20))
        assertEquals("a", LiveLessonBoundary.currentLesson(events, now)?.id)
        assertNull(LiveLessonBoundary.currentLesson(events, LocalDateTime.of(day, LocalTime.of(9, 30))))
    }

    @Test
    fun upcomingBoundaries_ordered() {
        val events = listOf(event("a", 8, 0, 9, 0), event("b", 10, 0, 11, 0))
        val now = LocalDateTime.of(day, LocalTime.of(7, 0))
        val list = LiveLessonBoundary.upcomingBoundaries(events, now, limit = 10)
        assertEquals(4, list.size)
        assertTrue(list.zipWithNext().all { (a, b) -> !a.at.isAfter(b.at) })
    }

    @Test
    fun project_includes_upcoming_at_60_minute_threshold_only() {
        val lesson = event("a", 9, 0, 10, 0)

        val atThreshold = LiveLessonBoundary.project(
            listOf(lesson),
            LocalDateTime.of(day, LocalTime.of(8, 0)),
        )
        assertNotNull(atThreshold)
        assertEquals(LiveLessonBoundary.Phase.UPCOMING, atThreshold!!.phase)
        assertEquals(60, atThreshold.minutesRemaining)

        assertNull(
            LiveLessonBoundary.project(
                listOf(lesson),
                LocalDateTime.of(day, LocalTime.of(7, 59)),
            ),
        )
    }

    @Test
    fun project_current_contains_progress_and_next_lesson() {
        val events = listOf(
            event("a", 8, 0, 9, 0),
            event("b", 9, 15, 10, 0),
        )
        val projection = LiveLessonBoundary.project(
            events,
            LocalDateTime.of(day, LocalTime.of(8, 30)),
        )

        assertNotNull(projection)
        assertEquals(LiveLessonBoundary.Phase.CURRENT, projection!!.phase)
        assertEquals("a", projection.event.id)
        assertEquals("b", projection.nextLesson?.id)
        assertEquals(30, projection.minutesRemaining)
        assertEquals(0.5f, projection.progress ?: 0f, 0.001f)
    }

    @Test
    fun project_excludes_cancelled_all_day_and_invalid_events() {
        val cancelled = event("cancelled", 8, 0, 9, 0, status = EventStatus.CANCELLED)
        val allDay = event("all-day", 8, 0, 9, 0, isAllDay = true)
        val invalid = event("invalid", 10, 0, 9, 0)

        assertNull(
            LiveLessonBoundary.project(
                listOf(cancelled, allDay, invalid),
                LocalDateTime.of(day, LocalTime.of(8, 30)),
            ),
        )
    }

    @Test
    fun project_overlapping_events_uses_earliest_start() {
        val events = listOf(
            event("later", 8, 15, 9, 15),
            event("earlier", 8, 0, 9, 0),
        )
        val projection = LiveLessonBoundary.project(
            events,
            LocalDateTime.of(day, LocalTime.of(8, 30)),
        )

        assertEquals("earlier", projection?.event?.id)
    }

    @Test
    fun nextRefreshBoundary_starts_tracking_one_hour_before_lesson() {
        val next = LiveLessonBoundary.nextRefreshBoundary(
            listOf(event("a", 9, 0, 10, 0)),
            LocalDateTime.of(day, LocalTime.of(7, 30)),
        )

        assertNotNull(next)
        assertEquals(LocalDateTime.of(day, LocalTime.of(8, 0)), next!!.at)
    }

    @Test
    fun projection_clears_after_final_lesson() {
        assertNull(
            LiveLessonBoundary.project(
                listOf(event("a", 8, 0, 9, 0)),
                LocalDateTime.of(day, LocalTime.of(9, 0)),
            ),
        )
    }
}
