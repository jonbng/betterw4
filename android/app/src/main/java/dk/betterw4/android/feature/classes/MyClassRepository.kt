package dk.betterw4.android.feature.classes

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
class MyClassRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun loadIndex(force: Boolean = false): AppResult<List<MyClass>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.myClasses.map { it.copy(loaded = false) })
        }

        val key = indexKey(student.studentId)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.CLASSES)) {
                    return AppResult.Success(W4ClassParser.parseIndex(cached.value))
                }
            }
        }
        return when (
            val res = client.get(
                W4Urls.Routes.MY_CLASSES,
                priority = FetchPriority.Important,
            )
        ) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4ClassParser.parseIndex(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4ClassParser.parseIndex(it)) }
                res
            }
        }
    }

    suspend fun loadClass(
        classId: String,
        force: Boolean = false,
        priority: FetchPriority = FetchPriority.Important,
    ): AppResult<MyClass> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val match = DemoData.myClasses.firstOrNull { it.id.equals(classId, ignoreCase = true) }
                ?: return AppResult.Success(
                    MyClass(id = classId, subject = classId, loaded = true),
                )
            return AppResult.Success(match.copy(loaded = true))
        }

        val key = classKey(student.studentId, classId)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.CLASSES)) {
                    return AppResult.Success(W4ClassParser.parseClass(cached.value, classId))
                }
            }
        }
        return when (
            val res = client.get(
                W4Urls.Routes.CLASS,
                query = mapOf("class_id" to classId),
                priority = priority,
            )
        ) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4ClassParser.parseClass(res.data.body, classId))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let {
                    return AppResult.Success(W4ClassParser.parseClass(it, classId))
                }
                res
            }
        }
    }

    private fun indexKey(studentId: String) = "myclasses_$studentId"

    private fun classKey(studentId: String, classId: String) = "class_${classId}_$studentId"
}
