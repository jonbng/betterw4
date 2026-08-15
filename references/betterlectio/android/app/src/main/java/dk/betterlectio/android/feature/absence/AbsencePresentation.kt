package dk.betterlectio.android.feature.absence

/**
 * Pure presentation helpers mirroring iOS [AbsenceViewModel].
 */
object AbsencePresentation {

    /**
     * Group all registrations by hold and sort by entry count (iOS subjectBreakdown).
     */
    fun subjectBreakdown(registrations: List<AbsenceRegistration>): List<SubjectAbsence> {
        if (registrations.isEmpty()) return emptyList()
        val grouped = registrations.groupBy { reg ->
            reg.team.ifBlank { reg.activityTitle }.ifBlank { "Ukendt" }
        }
        return grouped.map { (hold, entries) ->
            val avg = entries.mapNotNull { it.percent }
                .map { it * 100.0 }
                .let { if (it.isEmpty()) 0.0 else it.sum() / it.size }
            val subject = hold.trim().split(Regex("\\s+")).lastOrNull().orEmpty().ifBlank { hold }
            SubjectAbsence(
                subject = subject,
                fullHold = hold,
                totalEntries = entries.size,
                averagePercent = avg,
            )
        }.sortedByDescending { it.totalEntries }
    }

    /**
     * Warning copy when absence is concerning (iOS absenceWarning thresholds).
     * [regularPct] / [writtenPct] are 0–100 percentage points.
     */
    fun warningMessage(regularPct: Double, writtenPct: Double): String? {
        return when {
            writtenPct >= 15 ->
                "Dit skriftlige fravær er meget højt (${formatPct(writtenPct)}%). " +
                    "Du risikerer at blive indkaldt til samtale."
            regularPct >= 10 ->
                "Dit samlede fravær er højt (${formatPct(regularPct)}%). " +
                    "Hold øje med at det ikke stiger."
            writtenPct >= 10 ->
                "Dit skriftlige fravær er forhøjet (${formatPct(writtenPct)}%)."
            else -> null
        }
    }

    fun warningFromOverview(overview: AbsenceOverview): String? {
        val dual = AbsenceSummary.dual(overview)
        return warningMessage(dual.regularFraction * 100, dual.writtenFraction * 100)
    }

    /** Newest first (iOS sortedByDateDescending). */
    fun sortNewestFirst(registrations: List<AbsenceRegistration>): List<AbsenceRegistration> {
        return registrations.sortedWith(
            compareByDescending<AbsenceRegistration> { it.date }
                .thenByDescending { it.registeredAt },
        )
    }

    private fun formatPct(pct: Double): String =
        if (pct == pct.toLong().toDouble()) pct.toLong().toString()
        else "%.1f".format(pct)
}
