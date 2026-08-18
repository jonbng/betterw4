package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.offline.OfflineDirectoryStore
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DirectorySyncService @Inject constructor(
    private val client: W4Client,
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
    private val cache: SimpleCache,
    private val avatars: AvatarRepository,
) {
    suspend fun syncFullCatalog(): AppResult<Unit> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(Unit)

        val merged = linkedMapOf<String, DirectoryEntity>()
        val routes = listOf(
            W4Urls.Routes.STUDENTS_ALL,
            W4Urls.Routes.STAFF_CURRENT,
            W4Urls.Routes.STAFF,
            W4Urls.Routes.HOME,
        )
        var lastFailure: AppResult.Failure? = null
        for (route in routes) {
            when (val res = client.get(route)) {
                is AppResult.Failure -> lastFailure = res
                is AppResult.Success -> {
                    cache.put(cacheKey(student.studentId, route), res.data.body)
                    for (entity in W4PeopleParser.parse(res.data.body)) {
                        merged[entity.id] = DirectoryParser.mergeEntity(merged[entity.id], entity)
                    }
                }
            }
        }
        if (merged.isEmpty()) {
            return lastFailure ?: AppResult.Success(Unit)
        }
        val people = merged.values.toList()
        offline.replaceAll(student.studentId, people)
        avatars.ingest(people)
        Timber.i("Directory catalog synced: %d people", people.size)
        return AppResult.Success(Unit)
    }

    companion object {
        fun cacheKey(studentId: String, route: String) = "people_${studentId}_$route"
    }
}
