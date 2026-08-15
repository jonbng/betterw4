package dk.betterlectio.android.feature.grades

import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GradeRepository @Inject constructor(
    private val client: LectioClient,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun load(forceRefresh: Boolean = false): AppResult<GradesReport> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.gradesReport)
        }
        val key = "grades_${student.studentId}"
        if (!forceRefresh) {
            cache.get(key)?.let { return AppResult.Success(GradeParser.parse(it)) }
        }
        val paths = listOf(
            "grades/grade_report.aspx?elevid=${student.studentId}",
            "grades/grade_report.aspx",
            "grades/grade_student.aspx",
            "Karakterer.aspx",
        )
        var lastFailure: AppResult.Failure? = null
        for (path in paths) {
            when (val res = client.get(path)) {
                is AppResult.Failure -> lastFailure = res
                is AppResult.Success -> {
                    cache.put(key, res.data.body)
                    return AppResult.Success(GradeParser.parse(res.data.body))
                }
            }
        }
        cache.get(key)?.let { return AppResult.Success(GradeParser.parse(it)) }
        return lastFailure ?: AppResult.Failure(AppError.Unknown("Kunne ikke hente karakterer"))
    }

    suspend fun loadSubjectDetail(
        row: GradeRow,
        report: GradesReport? = null,
    ): AppResult<GradeSubjectDetail> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val notes = GradeAverage.notesForHold(DemoData.gradesReport.notes, row.team)
            return AppResult.Success(
                GradeSubjectDetail(
                    row = row,
                    notes = notes.ifEmpty {
                        listOf(
                            GradeNoteEntry(
                                hold = row.team,
                                gradeType = "",
                                grade = "",
                                insertedAt = "",
                                note = "Ingen noter",
                            ),
                        )
                    },
                    columns = DemoData.gradesReport.columns,
                ),
            )
        }

        // Prefer notes already on the report (same page as grades).
        if (report != null) {
            return AppResult.Success(
                GradeSubjectDetail(
                    row = row,
                    notes = GradeAverage.notesForHold(report.notes, row.team),
                    columns = report.columns,
                ),
            )
        }

        val paths = listOf(
            "grades/grade_report.aspx?elevid=${student.studentId}",
            "grades/grade_report.aspx",
            "grades/grade_student_note.aspx",
        )
        for (path in paths) {
            when (val res = client.get(path)) {
                is AppResult.Success -> {
                    val parsed = GradeParser.parse(res.data.body)
                    return AppResult.Success(
                        GradeSubjectDetail(
                            row = row,
                            notes = GradeAverage.notesForHold(parsed.notes, row.team),
                            columns = parsed.columns.ifEmpty { report?.columns.orEmpty() },
                        ),
                    )
                }
                is AppResult.Failure -> continue
            }
        }
        return AppResult.Success(GradeSubjectDetail(row, emptyList()))
    }
}
