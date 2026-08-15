package dk.betterlectio.android.feature.absence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Proves demo cause-edit mutates state: after updateCause, overview returns the new cause.
 * Exercises shipped [DemoAbsenceState] used by [AbsenceRepository].
 */
class AbsenceDemoCauseEditTest {

    @Test
    fun updateCause_changes_registration_visible_on_overview() {
        val state = DemoAbsenceState()
        state.reset(
            listOf(
                AbsenceRegistration("r1", LocalDate.of(2026, 7, 1), "Fy B", "Syg", "Godkendt"),
            ),
        )
        assertEquals("Syg", state.overview().registrations.single().cause)

        val ok = state.updateCause("r1", "Privat")
        assertTrue(ok)

        assertEquals("Privat", state.overview().registrations.single().cause)
        assertEquals("Privat", state.registrations().single().cause)
    }

    @Test
    fun updateCause_unknown_id_returns_false_without_side_effects() {
        val state = DemoAbsenceState()
        state.reset(
            listOf(
                AbsenceRegistration("r1", LocalDate.of(2026, 7, 1), "Fy B", "Syg", "Godkendt"),
            ),
        )
        assertFalse(state.updateCause("missing", "Andet"))
        assertEquals("Syg", state.registrations().single().cause)
    }
}
