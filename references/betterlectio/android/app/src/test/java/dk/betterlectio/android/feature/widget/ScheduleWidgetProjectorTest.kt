package dk.betterlectio.android.feature.widget

import dk.betterlectio.android.feature.schedule.EventStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class ScheduleWidgetProjectorTest {

    private val zone = ZoneId.of("Europe/Copenhagen")
    private val today = LocalDate.of(2026, 8, 11)

    @Test
    fun stale_when_missing_or_wrong_date() {
        assertEquals(
            WidgetContentKind.STALE,
            ScheduleWidgetProjector.present(null, today).kind,
        )
        val snap = WidgetSnapshot(date = "2026-08-10", dayLabel = "man.", lessons = emptyList())
        assertEquals(WidgetContentKind.STALE, ScheduleWidgetProjector.present(snap, today).kind)
    }

    @Test
    fun free_day_when_today_empty() {
        val snap = WidgetSnapshot(date = today.toString(), dayLabel = "tir.", lessons = emptyList())
        assertEquals(WidgetContentKind.FREE_DAY, ScheduleWidgetProjector.present(snap, today).kind)
    }

    @Test
    fun features_current_then_lists_remaining() {
        val morning = lesson("1", "Math", hour = 8, endHour = 9)
        val current = lesson("2", "Physics", hour = 10, endHour = 11)
        val later = lesson("3", "Danish", hour = 12, endHour = 13)
        val snap = WidgetSnapshot(
            date = today.toString(),
            dayLabel = "tir.",
            lessons = listOf(morning, current, later),
        )
        val now = LocalDateTime.of(2026, 8, 11, 10, 30).atZone(zone).toInstant().toEpochMilli()
        val presented = ScheduleWidgetProjector.present(snap, today, now)
        assertEquals(WidgetContentKind.CONTENT, presented.kind)
        assertEquals(WidgetFeaturedKind.CURRENT, presented.featuredKind)
        assertEquals("2", presented.featured?.id)
        assertEquals(listOf("3"), presented.rows.map { it.id })
    }

    @Test
    fun features_next_when_between_lessons() {
        val morning = lesson("1", "Math", hour = 8, endHour = 9)
        val later = lesson("2", "Physics", hour = 11, endHour = 12)
        val snap = WidgetSnapshot(
            date = today.toString(),
            dayLabel = "tir.",
            lessons = listOf(morning, later),
        )
        val now = LocalDateTime.of(2026, 8, 11, 10, 0).atZone(zone).toInstant().toEpochMilli()
        val presented = ScheduleWidgetProjector.present(snap, today, now)
        assertEquals(WidgetFeaturedKind.NEXT, presented.featuredKind)
        assertEquals("2", presented.featured?.id)
        assertTrue(presented.rows.none { it.id == "2" })
    }

    @Test
    fun skips_cancelled_for_featured() {
        val cancelled = lesson("1", "Math", hour = 10, endHour = 11, status = EventStatus.CANCELLED)
        val next = lesson("2", "Physics", hour = 12, endHour = 13)
        val snap = WidgetSnapshot(
            date = today.toString(),
            dayLabel = "tir.",
            lessons = listOf(cancelled, next),
        )
        val now = LocalDateTime.of(2026, 8, 11, 10, 30).atZone(zone).toInstant().toEpochMilli()
        val presented = ScheduleWidgetProjector.present(snap, today, now)
        assertEquals(WidgetFeaturedKind.NEXT, presented.featuredKind)
        assertEquals("2", presented.featured?.id)
    }

    @Test
    fun day_done_lists_all_without_featured() {
        val morning = lesson("1", "Math", hour = 8, endHour = 9)
        val snap = WidgetSnapshot(
            date = today.toString(),
            dayLabel = "tir.",
            lessons = listOf(morning),
        )
        val now = LocalDateTime.of(2026, 8, 11, 18, 0).atZone(zone).toInstant().toEpochMilli()
        val presented = ScheduleWidgetProjector.present(snap, today, now)
        assertNull(presented.featured)
        assertEquals(listOf("1"), presented.rows.map { it.id })
    }

    @Test
    fun codec_round_trips() {
        val snap = WidgetSnapshot(
            date = today.toString(),
            dayLabel = "tir. 11. aug",
            lessons = listOf(lesson("1", "Math", hour = 8, endHour = 9)),
        )
        val decoded = ScheduleWidgetCodec.decode(ScheduleWidgetCodec.encode(snap))
        assertEquals(snap, decoded)
    }

    private fun lesson(
        id: String,
        title: String,
        hour: Int,
        endHour: Int,
        status: EventStatus = EventStatus.NORMAL,
    ): WidgetLesson {
        val start = LocalDateTime.of(2026, 8, 11, hour, 0).atZone(zone).toInstant().toEpochMilli()
        val end = LocalDateTime.of(2026, 8, 11, endHour, 0).atZone(zone).toInstant().toEpochMilli()
        return WidgetLesson(
            id = id,
            title = title,
            startLabel = "%02d:00".format(hour),
            timeRange = "%02d:00 – %02d:00".format(hour, endHour),
            status = status.name,
            startEpochMilli = start,
            endEpochMilli = end,
        )
    }
}
