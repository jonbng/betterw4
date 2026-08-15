package dk.betterlectio.android.feature.grades

/** A grade column parsed from the live KarakterGV header (order varies by school/term). */
data class GradeColumn(
    /** Canonical key used to look up values in [GradeRow.grades]. */
    val key: String,
    /** Full Danish header label from Lectio. */
    val label: String,
)

data class GradeCellValue(
    val value: String,
    val weight: Double? = null,
    val xprsSubject: String? = null,
    val source: String? = null,
)

data class GradeRow(
    val team: String,
    val subject: String,
    val teamId: String? = null,
    /** Grades keyed by [GradeColumn.key] in the order of the live table. */
    val grades: Map<String, GradeCellValue> = emptyMap(),
) {
    fun cell(columnKey: String): GradeCellValue? = grades[columnKey]

    /** Compact multi-type summary for detail headers (filled cells only). */
    val gradeSummary: String
        get() = grades.values
            .map { it.value.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" · ")
}

data class GradeNoteEntry(
    val hold: String,
    val gradeType: String,
    val grade: String,
    val insertedAt: String,
    val note: String?,
)

data class GradesReport(
    val columns: List<GradeColumn>,
    val grades: List<GradeRow>,
    val notes: List<GradeNoteEntry> = emptyList(),
    val alerts: List<String> = emptyList(),
)

data class GradeSubjectDetail(
    val row: GradeRow,
    val notes: List<GradeNoteEntry>,
    val columns: List<GradeColumn> = emptyList(),
)
