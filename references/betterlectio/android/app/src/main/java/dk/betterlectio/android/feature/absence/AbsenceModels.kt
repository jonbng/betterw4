package dk.betterlectio.android.feature.absence

import java.time.LocalDate
import java.time.LocalDateTime

data class AbsenceFraction(
    val current: Double = 0.0,
    val total: Double = 0.0,
)

data class AbsenceTeamRow(
    val team: String,
    /** Flutter: `HE` + holdelementid */
    val teamId: String? = null,
    val regularCurrentPercent: Double,
    val regularFinalPercent: Double,
    val assignmentCurrentPercent: Double,
    val assignmentFinalPercent: Double,
    val regularCurrentModules: AbsenceFraction = AbsenceFraction(),
    val regularFinalModules: AbsenceFraction = AbsenceFraction(),
    val assignmentCurrentTime: AbsenceFraction = AbsenceFraction(),
    val assignmentFinalTime: AbsenceFraction = AbsenceFraction(),
)

/**
 * Single absence registration or missing-cause row.
 * Mirrors iOS [AbsenceEntry] fields used by the Fravær list.
 */
data class AbsenceRegistration(
    val id: String,
    val date: LocalDate?,
    /** Hold name, e.g. "1x MA" or "Fy B". */
    val team: String,
    val cause: String,
    val status: String,
    val week: String = "",
    /** Raw activity brick text when tooltip title is missing. */
    val activityTitle: String = "",
    /** 0.0–1.0 fraction of the module counted as absence. */
    val percent: Double? = null,
    val registeredAt: LocalDateTime? = null,
    val note: String = "",
    val missingCause: Boolean = false,
    val teacher: String = "",
    val room: String = "",
    /** Display string from tooltip, e.g. "10/10-2025 08:10 til 09:50". */
    val dateTimeLabel: String = "",
    /** Lesson title from tooltip first line when present. */
    val lessonTitle: String = "",
    val remark: String = "",
    /** Lectio "Godskrevet" / ok.gif. */
    val isApproved: Boolean = false,
) {
    /** Short subject label: "1x MA" → "MA", "Fy B" → "B" (last token). */
    val subjectShort: String
        get() {
            val hold = team.ifBlank { activityTitle }
            return hold.trim().split(Regex("\\s+")).lastOrNull().orEmpty().ifBlank { hold }
        }
}

data class AbsenceOverview(
    val teams: List<AbsenceTeamRow>,
    val registrations: List<AbsenceRegistration> = emptyList(),
    val attendanceAbsencePercent: Double? = null,
    val writtenAbsencePercent: Double? = null,
) {
    val missingReasons: List<AbsenceRegistration>
        get() = registrations.filter { it.missingCause }

    val withCause: List<AbsenceRegistration>
        get() = registrations.filter { !it.missingCause }
}

/**
 * Per-subject slice for the iOS-style donut ("Fravær pr. fag").
 */
data class SubjectAbsence(
    val subject: String,
    val fullHold: String,
    val totalEntries: Int,
    /** Average module absence percent 0–100. */
    val averagePercent: Double,
)

/**
 * Lectio cause dropdown strings — must match Flutter [AbsenceCauses] names.
 */
object AbsenceCauses {
    val all = listOf(
        "Sygdom",
        "Private forhold",
        "Skolerelaterede aktiviteter",
        "Kom for sent",
        "Andet",
    )
}
