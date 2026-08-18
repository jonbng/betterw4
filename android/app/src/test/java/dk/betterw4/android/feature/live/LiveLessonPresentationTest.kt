package dk.betterw4.android.feature.live

import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.ScheduleEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class LiveLessonPresentationTest {
    private val day = LocalDate.of(2026, 3, 10)

    @Test
    fun title_is_subject_and_room() {
        val copy = present(
            current(
                subject = "Mathematics",
                room = "A2.14",
                teacher = "JEH",
            ),
        )
        assertEquals("Mathematics · A2.14", copy.title)
        assertEquals("JEH", copy.text)
        assertEquals("A2.14", copy.chipText)
    }

    @Test
    fun title_is_subject_when_room_missing() {
        val copy = present(current(subject = "Mathematics", teacher = "JEH"))
        assertEquals("Mathematics", copy.title)
        assertEquals("JEH", copy.text)
        assertNull(copy.chipText)
    }

    @Test
    fun teacher_is_not_repeated_in_expanded() {
        val copy = present(
            current(
                subject = "Mathematics",
                room = "A2.14",
                teacher = "JEH",
                nextSubject = "Danish",
                nextRoom = "B1.03",
                nextStartH = 9,
                nextStartM = 55,
            ),
        )
        assertEquals("JEH", copy.text)
        assertEquals("08:10 – 09:40\nNext: Danish · B1.03 · 09:55", copy.expandedText)
    }

    @Test
    fun without_teacher_text_is_next_lesson() {
        val copy = present(
            current(
                subject = "Mathematics",
                room = "A2.14",
                nextSubject = "Danish",
                nextRoom = "B1.03",
                nextStartH = 9,
                nextStartM = 55,
            ),
        )
        assertEquals("Next: Danish · B1.03 · 09:55", copy.text)
        assertEquals("08:10 – 09:40", copy.expandedText)
    }

    @Test
    fun upcoming_falls_back_to_clock_range() {
        val copy = present(
            upcoming(subject = "Mathematics", room = "A2.14"),
        )
        assertEquals("Mathematics · A2.14", copy.title)
        assertEquals("08:10 – 09:40", copy.text)
        assertNull(copy.expandedText)
    }

    @Test
    fun chip_uses_first_room_and_fits_status_chip() {
        assertEquals("A2.14", LiveLessonPresentation.chipRoom("A2.14 / A2.15"))
        assertEquals("Gym", LiveLessonPresentation.chipRoom("Gym"))
        assertEquals("Auditor", LiveLessonPresentation.chipRoom("Auditorium"))
    }

    @Test
    fun blank_room_and_teacher_are_omitted() {
        val copy = present(current(subject = "Mathematics", room = "  ", teacher = " "))
        assertEquals("Mathematics", copy.title)
        assertEquals("08:10 – 09:40", copy.text)
        assertNull(copy.chipText)
    }

    private fun present(projection: LiveLessonBoundary.Projection): LiveLessonCopy =
        LiveLessonPresentation.present(
            projection,
            subjectOf = { it.title },
            nextLabel = { "Next: $it" },
        )

    private fun current(
        subject: String,
        room: String? = null,
        teacher: String? = null,
        nextSubject: String? = null,
        nextRoom: String? = null,
        nextStartH: Int = 9,
        nextStartM: Int = 55,
    ): LiveLessonBoundary.Projection {
        val event = event(subject, 8, 10, 9, 40, room, teacher)
        val next = nextSubject?.let { event(it, nextStartH, nextStartM, 11, 25, nextRoom) }
        return LiveLessonBoundary.Projection(
            phase = LiveLessonBoundary.Phase.CURRENT,
            event = event,
            target = event.end!!,
            minutesRemaining = 30,
            progress = 0.5f,
            nextLesson = next,
        )
    }

    private fun upcoming(
        subject: String,
        room: String? = null,
    ): LiveLessonBoundary.Projection {
        val event = event(subject, 8, 10, 9, 40, room)
        return LiveLessonBoundary.Projection(
            phase = LiveLessonBoundary.Phase.UPCOMING,
            event = event,
            target = event.start!!,
            minutesRemaining = 20,
            progress = null,
            nextLesson = null,
        )
    }

    private fun event(
        title: String,
        startH: Int,
        startM: Int,
        endH: Int,
        endM: Int,
        room: String? = null,
        teacher: String? = null,
    ) = ScheduleEvent(
        id = title,
        title = title,
        teacher = teacher,
        room = room,
        status = EventStatus.NORMAL,
        start = LocalDateTime.of(day, LocalTime.of(startH, startM)),
        end = LocalDateTime.of(day, LocalTime.of(endH, endM)),
        date = day,
    )
}
