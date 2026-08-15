package dk.betterlectio.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class PrivateEventIdsTest {

    @Test
    fun numericAftaleId_strips_AFT_prefix_for_update_path() {
        assertEquals("12345", PrivateEventIds.numericAftaleId("AFT12345"))
        assertEquals("12345", PrivateEventIds.numericAftaleId("aft12345"))
        assertEquals(
            "privat_aftale.aspx?aftaleid=12345",
            PrivateEventIds.updatePath("AFT12345"),
        )
    }

    @Test
    fun numericAftaleId_strips_PRIV_and_href_forms() {
        assertEquals("99", PrivateEventIds.numericAftaleId("PRIV99"))
        assertEquals("42", PrivateEventIds.numericAftaleId("priv42"))
        assertEquals(
            "7",
            PrivateEventIds.numericAftaleId("https://www.lectio.dk/lectio/1/privat_aftale.aspx?aftaleid=7"),
        )
        assertNull(PrivateEventIds.numericAftaleId("local-private-1"))
        assertNull(PrivateEventIds.updatePath("local-private-1"))
    }

    @Test
    fun storageId_matches_schedule_parser_AFT_convention() {
        assertEquals("AFT12345", PrivateEventIds.storageId("12345"))
    }

    @Test
    fun isPrivateEvent_true_for_AFT_even_with_empty_team() {
        val event = ScheduleEvent(
            id = "AFT7788",
            title = "Læge",
            team = "",
            date = LocalDate.of(2026, 3, 10),
        )
        assertTrue(PrivateEventIds.isPrivateEvent(event))
        assertTrue(PrivateEventIds.isPrivateEventId("AFT7788"))
    }

    @Test
    fun isPrivateEvent_true_for_team_token_and_href() {
        val byTeam = ScheduleEvent(
            id = "x",
            title = "Privat",
            team = PRIVATE_EVENT_TEAM_TOKEN,
            date = LocalDate.of(2026, 3, 10),
        )
        assertTrue(PrivateEventIds.isPrivateEvent(byTeam))
        val byHref = ScheduleEvent(
            id = "mod-1",
            title = "Aftale",
            team = "",
            date = LocalDate.of(2026, 3, 10),
            href = "privat_aftale.aspx?aftaleid=55",
        )
        assertTrue(PrivateEventIds.isPrivateEvent(byHref))
    }

    @Test
    fun isPrivateEvent_false_for_normal_module() {
        val event = ScheduleEvent(
            id = "1234567890",
            title = "Matematik",
            team = "Ma A",
            date = LocalDate.of(2026, 3, 10),
        )
        assertFalse(PrivateEventIds.isPrivateEvent(event))
        assertFalse(PrivateEventIds.isPrivateEventId(event.id))
    }

    @Test
    fun extractAftaleIdFromResponse_reads_link() {
        val html = """
            <html><body>
            <a href="/lectio/517/privat_aftale.aspx?aftaleid=98765">Rediger</a>
            </body></html>
        """.trimIndent()
        assertEquals("98765", PrivateEventIds.extractAftaleIdFromResponse(html))
        assertEquals(
            "AFT98765",
            PrivateEventIds.storageId(PrivateEventIds.extractAftaleIdFromResponse(html)!!),
        )
    }

    @Test
    fun createFromDraft_with_AFT_id_stays_editable_via_updatePath() {
        // Simulates post-create overlay id assignment used by ScheduleRepository
        val store = LocalPrivateEvents()
        val draft = PrivateEventDraft(
            title = "Møde",
            startDate = "10/03-2026",
            startTime = "09:00",
            endDate = "10/03-2026",
            endTime = "10:00",
        )
        val numeric = "12345"
        val id = PrivateEventIds.storageId(numeric)
        val created = store.createFromDraft(draft, id = id, nowDate = LocalDate.of(2026, 3, 10))
        assertEquals("AFT12345", created.id)
        assertTrue(PrivateEventIds.isPrivateEvent(created))
        assertEquals("privat_aftale.aspx?aftaleid=12345", PrivateEventIds.updatePath(created.id))
        // Update keeps same id so Lectio path remains valid
        val updated = store.updateFromDraft(
            id = created.id,
            draft = draft.copy(title = "Møde 2", eventId = created.id),
            nowDate = LocalDate.of(2026, 3, 10),
        )
        assertEquals("AFT12345", updated.id)
        assertEquals("Møde 2", updated.title)
        assertEquals("12345", PrivateEventIds.numericAftaleId(updated.id))
    }
}
