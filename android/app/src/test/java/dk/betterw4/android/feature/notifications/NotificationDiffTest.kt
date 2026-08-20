package dk.betterw4.android.feature.notifications

import dk.betterw4.android.feature.homework.HomeworkItem
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.trips.W4Trip
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

class NotificationDiffTest {
    private val day = LocalDate.of(2026, 8, 20)
    private val now = LocalDateTime.of(2026, 8, 20, 8, 0)

    @Test
    fun lessonMove_sameClassSameDay_isMoved() {
        val previous = NotificationDiff.watchLessons(
            listOf(lesson("Economics", hour = 9, room = "A12")),
            now,
        )
        val current = NotificationDiff.watchLessons(
            listOf(lesson("Economics", hour = 14, room = "A12")),
            now,
        )
        val changes = NotificationDiff.diffLessons(previous, current, now)
        assertEquals(1, changes.size)
        assertEquals(NotificationDiff.LessonChangeKind.MOVED, changes.single().kind)
        assertEquals("Economics", changes.single().title)
    }

    @Test
    fun lessonRoomChange_isRoom() {
        val previous = NotificationDiff.watchLessons(
            listOf(lesson("Biology HL", hour = 9, room = "Lab 1")),
            now,
        )
        val current = NotificationDiff.watchLessons(
            listOf(lesson("Biology HL", hour = 9, room = "Lab 2")),
            now,
        )
        val changes = NotificationDiff.diffLessons(previous, current, now)
        assertEquals(NotificationDiff.LessonChangeKind.ROOM, changes.single().kind)
    }

    @Test
    fun lessonDisappeared_isCancelled() {
        val previous = NotificationDiff.watchLessons(
            listOf(lesson("TOK", hour = 11, room = "A1")),
            now,
        )
        val current = NotificationDiff.watchLessons(emptyList(), now)
        val changes = NotificationDiff.diffLessons(previous, current, now)
        assertEquals(NotificationDiff.LessonChangeKind.CANCELLED, changes.single().kind)
    }

    @Test
    fun pastLessonMissing_isNotCancelled() {
        val previous = NotificationDiff.watchLessons(
            listOf(lesson("History", hour = 7, room = "B2")),
            now = LocalDateTime.of(2026, 8, 20, 6, 50),
        )
        val later = LocalDateTime.of(2026, 8, 20, 9, 0)
        val changes = NotificationDiff.diffLessons(previous, emptyList(), later)
        assertTrue(changes.isEmpty())
    }

    @Test
    fun schoolCalendarEvents_areIgnored() {
        val event = lesson("Assembly", hour = 9, room = "Hall").copy(source = "gcal")
        val watched = NotificationDiff.watchLessons(listOf(event), now)
        assertTrue(watched.isEmpty())
    }

    @Test
    fun newPendingAssessment_isNew() {
        val current = NotificationDiff.watchAssessments(
            listOf(assessment("class:1", "Biology IA", done = false, date = day.plusDays(3))),
            today = day,
        )
        val changes = NotificationDiff.diffAssessments(emptyList(), current)
        assertEquals(NotificationDiff.AssessmentChangeKind.NEW, changes.single().kind)
    }

    @Test
    fun pendingBecomingOverdue_isOverdue() {
        val item = assessment("class:2", "Essay", done = false, date = day.minusDays(1))
        val previous = NotificationDiff.watchAssessments(listOf(item.copy(date = day.plusDays(1))), day.minusDays(2))
        val current = NotificationDiff.watchAssessments(listOf(item), day)
        val changes = NotificationDiff.diffAssessments(previous, current)
        assertEquals(NotificationDiff.AssessmentChangeKind.OVERDUE, changes.single().kind)
    }

    @Test
    fun studentCreatedAssessment_isIgnored() {
        val item = assessment("student:9", "My reminder", done = false, date = day.plusDays(1))
            .copy(href = "student")
        val watched = NotificationDiff.watchAssessments(listOf(item), day)
        assertTrue(watched.isEmpty())
    }

    @Test
    fun tripStatusChange_isStatus() {
        val previous = NotificationDiff.watchTrips(
            listOf(trip("t1", "Bergen weekend", "Planning")),
        )
        val current = NotificationDiff.watchTrips(
            listOf(trip("t1", "Bergen weekend", "Approved")),
        )
        val changes = NotificationDiff.diffTrips(previous, current)
        assertEquals(NotificationDiff.TripChangeKind.STATUS, changes.single().kind)
        assertEquals("approved", changes.single().status)
    }

    @Test
    fun newTrip_isNew() {
        val current = NotificationDiff.watchTrips(listOf(trip("t2", "Kayaking", "Planning")))
        val changes = NotificationDiff.diffTrips(emptyList(), current)
        assertEquals(NotificationDiff.TripChangeKind.NEW, changes.single().kind)
    }

    @Test
    fun encodeRoundTrip_preservesDiff() {
        val snapshot = NotificationDiff.Snapshot(
            lessons = NotificationDiff.watchLessons(listOf(lesson("Economics", hour = 9, room = "A12")), now),
            assessments = NotificationDiff.watchAssessments(
                listOf(assessment("class:1", "IA", done = false, date = day.plusDays(2))),
                day,
            ),
            trips = NotificationDiff.watchTrips(listOf(trip("t1", "Bergen weekend", "Planning"))),
        )
        val restored = NotificationDiff.decode(NotificationDiff.encode(snapshot))
        assertEquals(snapshot.lessons.single().identity, restored.lessons.single().identity)
        assertEquals(snapshot.assessments.single().id, restored.assessments.single().id)
        assertEquals("planning", restored.trips.single().status)
    }

    private fun lesson(title: String, hour: Int, room: String): ScheduleEvent {
        val start = LocalDateTime.of(day, java.time.LocalTime.of(hour, 0))
        return ScheduleEvent(
            id = "ac-w4-$title",
            title = title,
            team = title,
            room = room,
            status = EventStatus.NORMAL,
            start = start,
            end = start.plusHours(1),
            date = day,
            source = "ac",
        )
    }

    private fun assessment(id: String, title: String, done: Boolean, date: LocalDate): HomeworkItem =
        HomeworkItem(
            id = id,
            note = "Biology",
            activityTitle = title,
            date = date,
            done = done,
            href = "class",
        )

    private fun trip(id: String, name: String, status: String): W4Trip =
        W4Trip(
            id = id,
            name = name,
            outgoing = "20-Sep-2026 08:00",
            returning = "21-Sep-2026 18:00",
            destination = "Bergen",
            type = "Optional",
            participants = "12",
            status = status,
        )
}
