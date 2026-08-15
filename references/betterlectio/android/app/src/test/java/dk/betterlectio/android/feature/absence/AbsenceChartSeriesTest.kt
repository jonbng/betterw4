package dk.betterlectio.android.feature.absence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AbsenceChartSeriesTest {

    @Test
    fun fromTeams_builds_bars_sorted_by_absence_desc() {
        val teams = listOf(
            AbsenceTeamRow("Ma A", regularCurrentPercent = 0.02, regularFinalPercent = 0.03, assignmentCurrentPercent = 0.0, assignmentFinalPercent = 0.0),
            AbsenceTeamRow("Fy B", regularCurrentPercent = 0.12, regularFinalPercent = 0.10, assignmentCurrentPercent = 0.0, assignmentFinalPercent = 0.0),
            AbsenceTeamRow("Da A", regularCurrentPercent = 0.05, regularFinalPercent = 0.05, assignmentCurrentPercent = 0.0, assignmentFinalPercent = 0.0),
        )
        val bars = AbsenceChartSeries.fromTeams(teams)
        assertEquals(3, bars.size)
        assertEquals("Fy B", bars[0].label)
        assertEquals(0.12, bars[0].fraction, 1e-9)
        assertEquals(12.0, bars[0].percent, 1e-9)
        assertEquals("Da A", bars[1].label)
        assertEquals("Ma A", bars[2].label)
        assertTrue(bars[0].fraction >= bars[1].fraction)
        assertTrue(bars[1].fraction >= bars[2].fraction)
    }

    @Test
    fun fromTeams_empty_input_returns_empty() {
        assertTrue(AbsenceChartSeries.fromTeams(emptyList()).isEmpty())
    }
}
