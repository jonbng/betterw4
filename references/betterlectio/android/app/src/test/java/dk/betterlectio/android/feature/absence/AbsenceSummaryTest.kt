package dk.betterlectio.android.feature.absence

import org.junit.Assert.assertEquals
import org.junit.Test

class AbsenceSummaryTest {

    @Test
    fun prefersOverviewTotalsWhenPresent() {
        val overview = AbsenceOverview(
            teams = emptyList(),
            attendanceAbsencePercent = 0.08,
            writtenAbsencePercent = 0.12,
        )
        val dual = AbsenceSummary.dual(overview)
        assertEquals(0.08, dual.regularFraction, 0.0001)
        assertEquals(0.12, dual.writtenFraction, 0.0001)
    }

    @Test
    fun convertsPercentOverOneToFraction() {
        assertEquals(0.15, AbsenceSummary.pctToFraction(15.0), 0.0001)
        assertEquals(0.05, AbsenceSummary.pctToFraction(0.05), 0.0001)
    }

    @Test
    fun averagesTeamsWhenOverviewMissing() {
        val overview = AbsenceOverview(
            teams = listOf(
                AbsenceTeamRow("Ma", null, 0.10, 0.10, 0.20, 0.20),
                AbsenceTeamRow("Da", null, 0.00, 0.00, 0.10, 0.10),
            ),
        )
        val dual = AbsenceSummary.dual(overview)
        assertEquals(0.05, dual.regularFraction, 0.0001)
        assertEquals(0.15, dual.writtenFraction, 0.0001)
    }
}
