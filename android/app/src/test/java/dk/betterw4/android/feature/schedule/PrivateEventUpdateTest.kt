package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime

class PrivateEventUpdateTest {

    @Test
    fun updateFromDraft_replaces_event_fields_keeping_id() {
        val store = LocalPrivateEvents()
        val created = store.createFromDraft(
            PrivateEventDraft(
                title = "Old",
                startDate = "10/03-2026",
                startTime = "09:00",
                endDate = "10/03-2026",
                endTime = "10:00",
                note = "a",
            ),
            id = "local-private-edit-1",
            nowDate = LocalDate.of(2026, 3, 10),
        )
        assertEquals("Old", created.title)

        val updated = store.updateFromDraft(
            id = "local-private-edit-1",
            draft = PrivateEventDraft(
                title = "New title",
                startDate = "11/03-2026",
                startTime = "14:00",
                endDate = "11/03-2026",
                endTime = "15:30",
                note = "updated",
                eventId = "local-private-edit-1",
            ),
            nowDate = LocalDate.of(2026, 3, 10),
        )
        assertEquals("local-private-edit-1", updated.id)
        assertEquals("New title", updated.title)
        assertEquals("updated", updated.notes)
        assertEquals(LocalDate.of(2026, 3, 11), updated.date)
        assertEquals(LocalTime.of(14, 0), updated.start?.toLocalTime())
        assertEquals(LocalTime.of(15, 30), updated.end?.toLocalTime())
        assertEquals(1, store.snapshot().size)
        assertTrue(store.contains("local-private-edit-1"))
    }

    @Test
    fun draftToEvent_maps_field_overrides_consistently() {
        val draft = PrivateEventDraft(
            title = "Møde",
            startDate = "01/04-2026",
            startTime = "08:15",
            endDate = "01/04-2026",
            endTime = "09:15",
            note = "n",
        )
        val overrides = PrivateEventResponse.fieldOverrides(
            title = draft.title,
            startDate = draft.startDate,
            startTime = draft.startTime,
            endDate = draft.endDate,
            endTime = draft.endTime,
            note = draft.note,
        )
        val event = LocalPrivateEvents().draftToEvent(draft, "x", LocalDate.of(2026, 4, 1))
        assertEquals(overrides["m\$Content\$titelTextBox\$tb"], event.title)
        assertEquals(draft.startDate, "01/04-2026")
        assertEquals(LocalTime.of(8, 15), event.start?.toLocalTime())
        assertEquals(CustomEvents.SOURCE, event.source)
    }

    @Test
    fun draftToEvent_all_day_uses_midnight_bounds() {
        val event = LocalPrivateEvents().draftToEvent(
            PrivateEventDraft(
                title = "Holiday",
                startDate = "01/04-2026",
                startTime = "08:00",
                endDate = "01/04-2026",
                endTime = "09:00",
                isAllDay = true,
            ),
            id = "local-holiday",
            nowDate = LocalDate.of(2026, 4, 1),
        )
        assertTrue(event.isAllDay)
        assertEquals(LocalDate.of(2026, 4, 1).atStartOfDay(), event.start)
        assertEquals(LocalDate.of(2026, 4, 2).atStartOfDay(), event.end)
    }
}
