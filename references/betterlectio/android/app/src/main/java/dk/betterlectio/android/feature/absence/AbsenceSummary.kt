package dk.betterlectio.android.feature.absence

/**
 * Dual summary rings for regular vs written absence (iOS AbsenceView hero).
 * Prefers overview totals when present; else averages team current percents.
 */
object AbsenceSummary {
    data class Dual(
        /** 0.0–1.0 fraction for regular (almindeligt) absence. */
        val regularFraction: Double,
        /** 0.0–1.0 fraction for written (skriftligt) absence. */
        val writtenFraction: Double,
    )

    fun dual(overview: AbsenceOverview): Dual {
        val regular = overview.attendanceAbsencePercent?.let { pctToFraction(it) }
            ?: averageOrZero(overview.teams.map { it.regularCurrentPercent })
        val written = overview.writtenAbsencePercent?.let { pctToFraction(it) }
            ?: averageOrZero(overview.teams.map { it.assignmentCurrentPercent })
        return Dual(
            regularFraction = regular.coerceIn(0.0, 1.0),
            writtenFraction = written.coerceIn(0.0, 1.0),
        )
    }

    /**
     * Overview fields may be stored as percent (0–100) or fraction (0–1).
     * Values > 1 are treated as percent.
     */
    fun pctToFraction(value: Double): Double =
        if (value > 1.0) value / 100.0 else value

    private fun averageOrZero(values: List<Double>): Double {
        if (values.isEmpty()) return 0.0
        return values.sum() / values.size
    }
}
