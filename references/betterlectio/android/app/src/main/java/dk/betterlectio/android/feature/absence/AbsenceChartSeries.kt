package dk.betterlectio.android.feature.absence

/**
 * Pure chart series construction from absence team rows (Flutter AbsenceChart parity).
 * Values are percentages 0–100 for bar length; [fraction] remains 0–1 for rings.
 */
data class AbsenceChartBar(
    val label: String,
    /** 0.0–1.0 absence fraction used for bar width and color banding */
    val fraction: Double,
    /** Display value e.g. 12.0 for "12%" */
    val percent: Double = fraction * 100.0,
)

object AbsenceChartSeries {
    /**
     * One bar per team using regular current absence (Flutter measureFn: regular.currentModules.current).
     * Sorted descending by absence so the worst teams surface first.
     */
    fun fromTeams(teams: List<AbsenceTeamRow>): List<AbsenceChartBar> {
        return teams
            .map { row ->
                AbsenceChartBar(
                    label = row.team,
                    fraction = row.regularCurrentPercent.coerceIn(0.0, 1.0),
                )
            }
            .sortedByDescending { it.fraction }
    }
}
