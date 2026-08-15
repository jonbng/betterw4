package dk.betterlectio.android.wear.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class WearCountdownProjectorTest {
    private val zone = ZoneId.of("Europe/Copenhagen")
    private val date = LocalDate.of(2026, 7, 23)

    @Test
    fun `current lesson counts down to end and reports progress`() {
        val event = event("math", "08:00", "09:00")
        val result = WearCountdownProjector.project(listOf(event), instant("08:30"))

        assertEquals(CountdownKind.CURRENT, result.kind)
        assertSame(event, result.event)
        assertEquals(30L, result.minutes)
        assertEquals(0.5f, result.progress, 0.001f)
    }

    @Test
    fun `exact end boundary selects next lesson`() {
        val first = event("math", "08:00", "09:00")
        val next = event("english", "09:00", "10:00")

        val result = WearCountdownProjector.project(listOf(first, next), instant("09:00"))

        assertEquals(CountdownKind.CURRENT, result.kind)
        assertSame(next, result.event)
    }

    @Test
    fun `gap counts up to next lesson with ceiling minutes`() {
        val event = event("history", "10:00", "11:00")

        val result = WearCountdownProjector.project(listOf(event), instant("09:58:30"))

        assertEquals(CountdownKind.NEXT, result.kind)
        assertEquals(2L, result.minutes)
    }

    @Test
    fun `cancelled all day and untimed events never drive countdown`() {
        val events = listOf(
            event("cancelled", "08:00", "09:00").copy(status = WearEventStatus.CANCELLED),
            event("all-day", "00:00", "23:59").copy(isAllDay = true),
            event("untimed", null, null),
        )

        val result = WearCountdownProjector.project(events, instant("08:30"))

        assertEquals(CountdownKind.NONE, result.kind)
        assertNull(result.event)
    }

    @Test
    fun `overlap chooses lesson ending first`() {
        val long = event("long", "08:00", "10:00")
        val short = event("short", "08:30", "09:00")

        val result = WearCountdownProjector.project(listOf(long, short), instant("08:45"))

        assertSame(short, result.event)
        assertEquals(15L, result.minutes)
    }

    @Test
    fun `next day event remains eligible`() {
        val tomorrow = event("tomorrow", "08:00", "09:00", date.plusDays(1))

        val result = WearCountdownProjector.project(listOf(tomorrow), instant("16:00"))

        assertEquals(CountdownKind.NEXT, result.kind)
        assertSame(tomorrow, result.event)
    }

    @Test
    fun `snapshot codec is forward compatible and preserves timezone`() {
        val snapshot = WearScheduleSnapshot(
            generatedAtEpochMillis = instant("08:00"),
            validUntilEpochMillis = instant("16:00"),
            zoneId = zone.id,
            events = listOf(event("math", "08:00", "09:00")),
        )
        val encoded = WearScheduleCodec.encode(snapshot)
            .dropLast(1) + ",\"future_field\":true}"

        val decoded = WearScheduleCodec.decode(encoded)

        assertEquals(zone.id, decoded.zoneId)
        assertEquals(snapshot.events, decoded.events)
        assertFalse(decoded.isStale(instant("12:00")))
        assertTrue(decoded.isStale(instant("16:01")))
    }

    private fun event(
        id: String,
        start: String?,
        end: String?,
        eventDate: LocalDate = date,
    ) = WearScheduleEvent(
        id = id,
        title = id,
        startEpochMillis = start?.let { instant(it, eventDate) },
        endEpochMillis = end?.let { instant(it, eventDate) },
        dateEpochDay = eventDate.toEpochDay(),
    )

    private fun instant(time: String, eventDate: LocalDate = date): Long =
        eventDate.atTime(java.time.LocalTime.parse(normalizeTime(time)))
            .atZone(zone)
            .toInstant()
            .toEpochMilli()

    private fun normalizeTime(value: String): String =
        if (value.count { it == ':' } == 1) "$value:00" else value
}
