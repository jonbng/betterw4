package dk.betterw4.android.feature.grades

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GradeRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun load(force: Boolean = false): AppResult<GradesReport> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.gradesReport)
        }
        val key = "grades_${student.studentId}"
        if (!force) {
            cache.get(key)?.let { return AppResult.Success(W4GradeParser.parse(it)) }
        }
        return when (val res = client.get(W4Urls.Routes.GRADES)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4GradeParser.parse(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4GradeParser.parse(it)) }
                res
            }
        }
    }

    suspend fun loadSubjectDetail(
        row: GradeRow,
        report: GradesReport?,
    ): AppResult<GradeSubjectDetail> {
        val notes = report?.notes.orEmpty().filter { it.hold.equals(row.team, ignoreCase = true) }
        return AppResult.Success(
            GradeSubjectDetail(row = row, notes = notes, columns = report?.columns.orEmpty()),
        )
    }
}
