package dk.betterlectio.android.feature.wear

import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleDay
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.ScheduleWeek
import dk.betterlectio.android.wear.model.WearEventStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class PhoneWearScheduleMapperTest {
    private val zone = ZoneId.of("Europe/Copenhagen")

    @Test
    fun `maps only current through next seven days and preserves status`() {
        val today = LocalDate.of(2026, 7, 23)
        val events = listOf(
            event("past", today.minusDays(1)),
            event("today", today, EventStatus.CHANGED),
            event("last", today.plusDays(7)),
            event("too-far", today.plusDays(8)),
        )
        val week = ScheduleWeek(
            year = 2026,
            week = 30,
            days = events.groupBy { it.date }.map { ScheduleDay(it.key, it.value) },
        )

        val snapshot = PhoneWearScheduleMapper.snapshot(
            weeks = listOf(week),
            now = today.atStartOfDay(zone).toInstant(),
            zoneId = zone,
        )

        assertEquals(listOf("today", "last"), snapshot.events.map { it.id })
        assertEquals(WearEventStatus.CHANGED, snapshot.events.first().status)
        assertEquals(zone.id, snapshot.zoneId)
    }

    @Test
    fun `converts local lesson time using supplied school timezone`() {
        val date = LocalDate.of(2026, 3, 29)
        val event = event("dst", date)
        val week = ScheduleWeek(2026, 13, listOf(ScheduleDay(date, listOf(event))))

        val snapshot = PhoneWearScheduleMapper.snapshot(
            listOf(week),
            date.atStartOfDay(zone).toInstant(),
            zone,
        )

        assertEquals(
            event.start!!.atZone(zone).toInstant().toEpochMilli(),
            snapshot.events.single().startEpochMillis,
        )
        assertTrue(snapshot.validUntilEpochMillis > snapshot.generatedAtEpochMillis)
    }

    private fun event(
        id: String,
        date: LocalDate,
        status: EventStatus = EventStatus.NORMAL,
    ) = ScheduleEvent(
        id = id,
        title = id,
        date = date,
        start = LocalDateTime.of(date, java.time.LocalTime.of(8, 0)),
        end = LocalDateTime.of(date, java.time.LocalTime.of(9, 0)),
        status = status,
    )
}
