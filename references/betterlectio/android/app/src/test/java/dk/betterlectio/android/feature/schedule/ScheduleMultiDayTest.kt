package dk.betterlectio.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

class ScheduleMultiDayTest {

    private val mon = LocalDate.of(2026, 5, 4)
    private val tue = LocalDate.of(2026, 5, 5)
    private val wed = LocalDate.of(2026, 5, 6)

    @Test
    fun expand_single_day_returns_one() {
        val event = timed(
            id = "ABS1",
            start = mon.atTime(8, 10),
            end = mon.atTime(9, 50),
            date = mon,
        )
        val out = ScheduleMultiDay.expandEventAcrossDays(event)
        assertEquals(1, out.size)
        assertEquals(mon, out[0].date)
        assertFalse(out[0].isAllDay)
    }

    @Test
    fun expand_mon_wed_timed_covers_three_days() {
        val event = timed(
            id = "ABS-MULTI",
            start = mon.atTime(8, 0),
            end = wed.atTime(16, 0),
            date = mon,
        )
        val out = ScheduleMultiDay.expandEventAcrossDays(event)
        assertEquals(3, out.size)
        assertEquals(listOf(mon, tue, wed), out.map { it.date })
        // First / last are partial → timed; middle full day → all-day chip
        assertFalse(out[0].isAllDay)
        assertTrue(out[1].isAllDay)
        assertFalse(out[2].isAllDay)
        // True range preserved for labels / live
        assertEquals(mon.atTime(8, 0), out[0].start)
        assertEquals(wed.atTime(16, 0), out[0].end)
    }

    @Test
    fun expand_overnight_two_days() {
        val event = timed(
            id = "AFT1",
            start = mon.atTime(16, 0),
            end = tue.atTime(9, 0),
            date = mon,
        )
        val out = ScheduleMultiDay.expandEventAcrossDays(event)
        assertEquals(2, out.size)
        assertFalse(out[0].isAllDay)
        assertFalse(out[1].isAllDay)
    }

    @Test
    fun expand_exclusive_midnight_end_does_not_include_next_day() {
        val event = timed(
            id = "ABS2",
            start = mon.atTime(10, 0),
            end = tue.atTime(0, 0), // exclusive end of Monday
            date = mon,
        )
        val out = ScheduleMultiDay.expandEventAcrossDays(event)
        assertEquals(1, out.size)
        assertEquals(mon, out[0].date)
    }

    @Test
    fun expand_week_places_event_on_middle_days() {
        val event = timed(
            id = "ABS-MULTI",
            start = mon.atTime(8, 0),
            end = wed.atTime(16, 0),
            date = mon,
        )
        val week = ScheduleWeek(
            year = 2026,
            week = 19,
            days = listOf(
                ScheduleDay(mon, listOf(event)),
                ScheduleDay(tue, emptyList()),
                ScheduleDay(wed, emptyList()),
            ),
        )
        val expanded = ScheduleMultiDay.expandWeek(week)
        assertEquals(1, expanded.days.find { it.date == mon }!!.events.size)
        assertEquals(1, expanded.days.find { it.date == tue }!!.events.size)
        assertEquals(1, expanded.days.find { it.date == wed }!!.events.size)
        assertEquals("ABS-MULTI", expanded.days.find { it.date == tue }!!.events.single().id)
    }

    @Test
    fun expand_week_dedupes_same_id_already_on_each_day() {
        val monEv = timed("ABS-MULTI", mon.atTime(8, 0), wed.atTime(16, 0), mon)
        val tueEv = timed("ABS-MULTI", mon.atTime(8, 0), wed.atTime(16, 0), tue)
        val week = ScheduleWeek(
            year = 2026,
            week = 19,
            days = listOf(
                ScheduleDay(mon, listOf(monEv)),
                ScheduleDay(tue, listOf(tueEv)),
                ScheduleDay(wed, emptyList()),
            ),
        )
        val expanded = ScheduleMultiDay.expandWeek(week)
        assertEquals(1, expanded.days.find { it.date == mon }!!.events.size)
        assertEquals(1, expanded.days.find { it.date == tue }!!.events.size)
        assertEquals(1, expanded.days.find { it.date == wed }!!.events.size)
    }

    @Test
    fun segment_first_day_extends_to_end_of_day() {
        val event = timed("X", mon.atTime(16, 0), tue.atTime(9, 0), mon)
        val seg = ScheduleMultiDay.segmentMinutesOnDay(event, mon, dayStartHour = 8)
        assertNotNull(seg)
        // 16:00 → 8h from 08:00 = 480; end of day from 08:00 = 960
        assertEquals(480, seg!!.first)
        assertEquals(960, seg.second)
    }

    @Test
    fun segment_last_day_starts_at_grid_top() {
        val event = timed("X", mon.atTime(16, 0), tue.atTime(9, 0), mon)
        val seg = ScheduleMultiDay.segmentMinutesOnDay(event, tue, dayStartHour = 8)
        assertNotNull(seg)
        // Before 08:00 clips to 0; 09:00 = 60
        assertEquals(0, seg!!.first)
        assertEquals(60, seg.second)
    }

    @Test
    fun segment_all_day_returns_null() {
        val event = ScheduleEvent(
            id = "AD1",
            title = "Fest",
            date = mon,
            isAllDay = true,
            start = mon.atTime(0, 0),
            end = tue.atTime(0, 0),
        )
        assertNull(ScheduleMultiDay.segmentMinutesOnDay(event, mon, dayStartHour = 8))
    }

    @Test
    fun parse_tooltip_multi_date() {
        val tip = ScheduleParser.parseTooltip(
            """
            Studietur
            5/5-2026 08:00 til 7/5-2026 16:00
            Hold: 1x
            """.trimIndent(),
            LocalDate.of(2026, 5, 5),
        )
        assertEquals(LocalDateTime.of(2026, 5, 5, 8, 0), tip.start)
        assertEquals(LocalDateTime.of(2026, 5, 7, 16, 0), tip.end)
        assertTrue(ScheduleMultiDay.isMultiDay(
            ScheduleEvent(
                id = "1",
                title = tip.title,
                date = LocalDate.of(2026, 5, 5),
                start = tip.start,
                end = tip.end,
            ),
        ))
    }

    @Test
    fun private_merge_expands_across_days() {
        val local = LocalPrivateEvents()
        local.createFromDraft(
            PrivateEventDraft(
                title = "Weekend",
                note = "",
                startDate = "04/05-2026",
                startTime = "10:00",
                endDate = "06/05-2026",
                endTime = "14:00",
            ),
            id = "local-private-1",
            nowDate = mon,
        )
        val week = ScheduleWeek(
            year = 2026,
            week = 19,
            days = listOf(
                ScheduleDay(mon, emptyList()),
                ScheduleDay(tue, emptyList()),
                ScheduleDay(wed, emptyList()),
            ),
        )
        val merged = local.mergeIntoWeek(week)
        assertEquals(1, merged.days.find { it.date == mon }!!.events.size)
        assertEquals(1, merged.days.find { it.date == tue }!!.events.size)
        assertEquals(1, merged.days.find { it.date == wed }!!.events.size)
    }

    private fun timed(
        id: String,
        start: LocalDateTime,
        end: LocalDateTime,
        date: LocalDate,
    ) = ScheduleEvent(
        id = id,
        title = "Multi",
        date = date,
        start = start,
        end = end,
        isAllDay = false,
    )
}
