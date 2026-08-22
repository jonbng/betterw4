package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class CustomEventStoreTest {

    @Test
    fun codec_round_trips_a_timed_event() {
        val event = ScheduleEvent(
            id = "local-abc",
            title = "Doctor",
            team = PRIVATE_EVENT_TEAM_TOKEN,
            notes = "Bring card",
            start = LocalDateTime.of(2026, 3, 10, 9, 0),
            end = LocalDateTime.of(2026, 3, 10, 10, 0),
            date = LocalDate.of(2026, 3, 10),
            source = CustomEvents.SOURCE,
        )
        val decoded = CustomEventStore.decode(CustomEventStore.encode(listOf(event)))
        assertEquals(1, decoded.size)
        val got = decoded.single()
        assertEquals(event.id, got.id)
        assertEquals(event.title, got.title)
        assertEquals(event.notes, got.notes)
        assertEquals(event.start, got.start)
        assertEquals(event.end, got.end)
        assertEquals(CustomEvents.SOURCE, got.source)
        assertTrue(CustomEvents.isCustomEvent(got))
    }

    @Test
    fun codec_round_trips_an_all_day_event() {
        val event = ScheduleEvent(
            id = "local-all-day",
            title = "Trip",
            team = PRIVATE_EVENT_TEAM_TOKEN,
            start = LocalDate.of(2026, 4, 1).atStartOfDay(),
            end = LocalDate.of(2026, 4, 2).atStartOfDay(),
            date = LocalDate.of(2026, 4, 1),
            isAllDay = true,
            source = CustomEvents.SOURCE,
        )
        val got = CustomEventStore.decode(CustomEventStore.encode(listOf(event))).single()
        assertTrue(got.isAllDay)
        assertEquals(event.start, got.start)
        assertEquals(event.end, got.end)
    }

    @Test
    fun decode_returns_empty_for_garbage() {
        assertTrue(CustomEventStore.decode("not-json").isEmpty())
    }

    @Test
    fun defaultStart_today_rounds_up_to_next_quarter() {
        val now = LocalDateTime.of(2026, 3, 10, 9, 7, 0)
        assertEquals(
            LocalDateTime.of(2026, 3, 10, 9, 15),
            CustomEvents.defaultStart(now.toLocalDate(), now),
        )
    }

    @Test
    fun defaultStart_other_day_is_eight() {
        val now = LocalDateTime.of(2026, 3, 10, 15, 0)
        assertEquals(
            LocalDateTime.of(2026, 3, 11, 8, 0),
            CustomEvents.defaultStart(LocalDate.of(2026, 3, 11), now),
        )
    }

    @Test
    fun remesh_replaces_previous_local_overlay() {
        val store = LocalPrivateEvents()
        val monday = LocalDate.of(2026, 3, 9)
        store.createFromDraft(
            PrivateEventDraft(
                title = "Old",
                startDate = "09/03-2026",
                startTime = "12:00",
                endDate = "09/03-2026",
                endTime = "13:00",
            ),
            id = "local-old",
            nowDate = monday,
        )
        val base = dk.betterw4.android.feature.demo.DemoData.scheduleWeek(2026, 11)
        val first = store.remesh(base)
        assertTrue(first.days.any { day -> day.events.any { it.id == "local-old" } })

        store.delete("local-old")
        store.createFromDraft(
            PrivateEventDraft(
                title = "New",
                startDate = "09/03-2026",
                startTime = "15:00",
                endDate = "09/03-2026",
                endTime = "16:00",
            ),
            id = "local-new",
            nowDate = monday,
        )
        val second = store.remesh(first)
        assertFalse(second.days.any { day -> day.events.any { it.id == "local-old" } })
        assertTrue(second.days.any { day -> day.events.any { it.id == "local-new" } })
    }
}
