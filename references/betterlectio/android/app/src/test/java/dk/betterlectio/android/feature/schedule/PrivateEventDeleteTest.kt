package dk.betterlectio.android.feature.schedule

import dk.betterlectio.android.feature.demo.DemoData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Drives shipped [LocalPrivateEvents] used by [ScheduleRepository] for create/delete.
 * Create-then-delete must empty the snapshot and remove overlay from a week merge.
 */
class PrivateEventDeleteTest {

    @Test
    fun createFromDraft_then_delete_empties_snapshot() {
        val store = LocalPrivateEvents()
        val draft = PrivateEventDraft(
            title = "Læge",
            startDate = "10/03-2026",
            startTime = "09:00",
            endDate = "10/03-2026",
            endTime = "10:00",
            note = "Checkup",
        )
        val created = store.createFromDraft(draft, id = "local-private-test-1", nowDate = LocalDate.of(2026, 3, 10))
        assertEquals("local-private-test-1", created.id)
        assertEquals("Læge", created.title)
        assertEquals(1, store.snapshot().size)
        assertTrue(store.contains(created.id))

        val removed = store.delete(created.id)
        assertTrue(removed)
        assertTrue(store.snapshot().isEmpty())
        assertFalse(store.contains(created.id))
    }

    @Test
    fun delete_removes_event_from_merged_week() {
        val store = LocalPrivateEvents()
        val year = 2026
        val week = 11
        val monday = LocalDate.of(2026, 3, 9)
        val draft = PrivateEventDraft(
            title = "Privat møde",
            startDate = "09/03-2026",
            startTime = "12:00",
            endDate = "09/03-2026",
            endTime = "13:00",
            note = "",
        )
        val event = store.createFromDraft(draft, id = "local-private-week", nowDate = monday)
        val base = DemoData.scheduleWeek(year, week)
        val merged = store.mergeIntoWeek(base)
        assertTrue(merged.days.any { day -> day.events.any { it.id == event.id } })

        store.delete(event.id)
        val after = store.mergeIntoWeek(base)
        assertFalse(after.days.any { day -> day.events.any { it.id == event.id } })
        assertEquals(0, store.snapshot().size)
    }

    @Test
    fun parseDraftDate_matches_repository_format() {
        assertEquals(LocalDate.of(2026, 3, 10), LocalPrivateEvents.parseDraftDate("10/03-2026"))
        assertEquals(null, LocalPrivateEvents.parseDraftDate("bad"))
    }
}
