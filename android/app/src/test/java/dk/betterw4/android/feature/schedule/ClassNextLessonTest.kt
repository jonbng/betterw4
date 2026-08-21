package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class ClassNextLessonTest {
    private val monday = LocalDate.of(2026, 8, 24)
    private val wednesday = LocalDate.of(2026, 8, 26)

    @Test
    fun picks_the_soonest_future_block_for_the_class() {
        val week = week(
            event(monday, 8, 15, "1DA13HMTAA", "A 1.3"),
            event(monday, 9, 25, "1EA16CECOX", "A 1.6"),
            event(wednesday, 8, 15, "1DA13HMTAA", "A 1.3"),
        )
        val now = LocalDateTime.of(monday, LocalTime.of(10, 0))
        val next = ClassNextLessons.next(week, "1DA13HMTAA", now)
        assertEquals(LocalDateTime.of(wednesday, LocalTime.of(8, 15)), next?.start)
        assertEquals("A 1.3", next?.room)
    }

    @Test
    fun falls_back_to_the_first_block_when_the_week_has_already_passed() {
        val week = week(event(monday, 8, 15, "1DA13HMTAA", "A 1.3"))
        val fridayEvening = LocalDateTime.of(LocalDate.of(2026, 8, 28), LocalTime.of(20, 0))
        val next = ClassNextLessons.next(week, "1da13hmtaa", fridayEvening)
        assertEquals(LocalDateTime.of(monday, LocalTime.of(8, 15)), next?.start)
    }

    @Test
    fun skips_breakfast_and_cancelled_blocks() {
        val breakfast = ScheduleEvent(
            id = "breakfast",
            title = "Breakfast",
            date = monday,
            start = LocalDateTime.of(monday, LocalTime.of(7, 0)),
            end = LocalDateTime.of(monday, LocalTime.of(8, 0)),
        )
        val cancelled = event(monday, 8, 15, "1DA13HMTAA", "A 1.3").copy(status = EventStatus.CANCELLED)
        val live = event(wednesday, 8, 15, "1DA13HMTAA", "A 1.3")
        val week = week(breakfast, cancelled, live)
        val now = LocalDateTime.of(monday, LocalTime.of(7, 0))
        val next = ClassNextLessons.next(week, "1DA13HMTAA", now)
        assertEquals(LocalDateTime.of(wednesday, LocalTime.of(8, 15)), next?.start)
    }

    @Test
    fun matches_class_id_from_team_when_href_is_missing() {
        val week = week(
            ScheduleEvent(
                id = "math",
                title = "Mathematics",
                team = "1DA13HMTAA",
                room = "A 1.3",
                start = LocalDateTime.of(monday, LocalTime.of(8, 15)),
                date = monday,
            ),
        )
        val next = ClassNextLessons.next(week, "1DA13HMTAA", LocalDateTime.of(monday, LocalTime.of(7, 0)))
        assertEquals("A 1.3", next?.room)
    }

    @Test
    fun empty_week_returns_nil() {
        val week = ScheduleWeek(year = 2026, week = 35, days = listOf(ScheduleDay(monday, emptyList())))
        assertNull(ClassNextLessons.next(week, "1DA13HMTAA", LocalDateTime.of(monday, LocalTime.NOON)))
        assertTrue(ClassNextLessons.map(week, LocalDateTime.of(monday, LocalTime.NOON)).isEmpty())
    }

    private fun week(vararg events: ScheduleEvent): ScheduleWeek {
        val byDate = events.groupBy { it.date }
        return ScheduleWeek(
            year = 2026,
            week = 35,
            days = byDate.keys.sorted().map { date ->
                ScheduleDay(date = date, events = byDate[date].orEmpty())
            },
        )
    }

    private fun event(
        day: LocalDate,
        hour: Int,
        minute: Int,
        classId: String,
        room: String,
    ) = ScheduleEvent(
        id = "$classId-$day-$hour",
        title = "Class",
        href = "/index.php?r=academics/classes/class&class_id=$classId",
        room = room,
        start = LocalDateTime.of(day, LocalTime.of(hour, minute)),
        end = LocalDateTime.of(day, LocalTime.of(hour, minute)).plusMinutes(50),
        date = day,
    )
}
