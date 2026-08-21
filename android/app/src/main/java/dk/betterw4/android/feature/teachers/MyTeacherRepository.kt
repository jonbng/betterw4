package dk.betterw4.android.feature.teachers

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MyTeacherRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun load(force: Boolean = false): AppResult<List<MyTeacher>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.myTeachers)
        }

        val key = cacheKey(student.studentId)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.PEOPLE)) {
                    return AppResult.Success(W4TeacherParser.parse(cached.value))
                }
            }
        }
        return when (
            val res = client.get(
                W4Urls.Routes.STAFF,
                priority = FetchPriority.Important,
            )
        ) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4TeacherParser.parse(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4TeacherParser.parse(it)) }
                res
            }
        }
    }

    private fun cacheKey(studentId: String) = "myteachers_$studentId"
}
