package dk.betterlectio.android.feature.assignments

import java.time.LocalDateTime

enum class AssignmentFilter {
    ALL,
    AWAITING_ME,
    DELIVERED,
    MISSING,
}

data class AssignmentItem(
    val id: String,
    val title: String,
    val team: String,
    val week: Int,
    val deadline: LocalDateTime?,
    val status: String,
    val studentTime: Double,
    val awaits: String,
    val note: String,
    val absence: String = "",
    val grade: String? = null,
    val gradeNote: String? = null,
    val studentNote: String? = null,
    val holdElementId: String? = null,
    val detailUrl: String? = null,
)

data class AssignmentSubmission(
    val id: String,
    val timestamp: String,
    val user: String,
    val comment: String? = null,
    val documentName: String? = null,
    val documentUrl: String? = null,
)

data class AssignmentDetail(
    val item: AssignmentItem,
    val description: String = "",
    val files: List<Pair<String, String>> = emptyList(), // name to url
    val responsible: String = "",
    val grading: String = "",
    val submissions: List<AssignmentSubmission> = emptyList(),
    val completed: Boolean = false,
    val studentGrade: String? = null,
    val studentGradeNote: String? = null,
)

fun AssignmentItem.matches(filter: AssignmentFilter): Boolean {
    val s = status.lowercase()
    val a = awaits.lowercase()
    return when (filter) {
        AssignmentFilter.ALL -> true
        // Lectio uses "Venter" (iOS) and sometimes "Afventer"
        AssignmentFilter.AWAITING_ME ->
            a.contains("elev") ||
                s.contains("afventer") ||
                s.contains("venter") ||
                s.contains("mangler")
        AssignmentFilter.DELIVERED ->
            s.contains("aflever") || s.contains("afsluttet") || a.contains("lærer")
        AssignmentFilter.MISSING ->
            s.contains("mangl") || s.contains("ikke aflever")
    }
}
