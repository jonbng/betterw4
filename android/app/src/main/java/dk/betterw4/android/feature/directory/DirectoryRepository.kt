package dk.betterw4.android.feature.directory

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
import dk.betterw4.android.feature.offline.OfflineDirectoryStore
import dk.betterw4.android.feature.schedule.PersonClass
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DirectoryRepository @Inject constructor(
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
    private val syncService: DirectorySyncService,
    private val client: W4Client,
    private val cache: SimpleCache,
) {
    suspend fun search(query: String, kind: DirectoryEntityKind? = null): AppResult<List<DirectoryEntity>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(filterParsed(DemoData.directory, query, kind))
        }

        var catalog = offline.loadAll(student.studentId)
        if (catalog.isEmpty()) {
            when (val sync = syncService.syncFullCatalog()) {
                is AppResult.Failure -> return sync
                is AppResult.Success -> catalog = offline.loadAll(student.studentId)
            }
        }
        return AppResult.Success(filterParsed(catalog, query, kind))
    }

    private fun filterParsed(
        parsed: List<DirectoryEntity>,
        query: String,
        kind: DirectoryEntityKind?,
    ): List<DirectoryEntity> {
        val q = query.trim().lowercase()
        return parsed.asSequence()
            .filter { kind == null || it.kind == kind }
            .filter { !DirectoryParser.looksLikeNavChrome(it.name) }
            .filter {
                q.isEmpty() ||
                    it.name.lowercase().contains(q) ||
                    it.subtitle?.lowercase()?.contains(q) == true ||
                    it.id.lowercase().contains(q)
            }
            .toList()
    }

    suspend fun loadProfile(
        entity: DirectoryEntity,
        force: Boolean = false,
    ): AppResult<W4PersonProfile> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoProfile(entity))

        val key = profileKey(student.studentId, entity.id)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.PROFILE)) {
                    W4PeopleParser.parseProfile(cached.value, entity.kind)?.let {
                        return AppResult.Success(it)
                    }
                }
            }
        }
        val route = if (entity.kind == DirectoryEntityKind.TEACHER) {
            W4Urls.Routes.STAFF_PROFILE
        } else {
            W4Urls.Routes.STUDENT_PROFILE
        }
        return when (
            val res = client.get(
                route,
                query = mapOf("uwc_id" to entity.id),
                priority = FetchPriority.Important,
            )
        ) {
            is AppResult.Success -> {
                val parsed = W4PeopleParser.parseProfile(res.data.body, entity.kind)
                    ?: return cache.get(key)?.let { html ->
                        W4PeopleParser.parseProfile(html, entity.kind)?.let { AppResult.Success(it) }
                    } ?: AppResult.Failure(AppError.Parsing("Profile page carried no uwc id"))
                cache.put(key, res.data.body)
                AppResult.Success(parsed)
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { html ->
                    W4PeopleParser.parseProfile(html, entity.kind)?.let { return AppResult.Success(it) }
                }
                res
            }
        }
    }

    private fun profileKey(studentId: String, uwcId: String) =
        "profile:$studentId:${uwcId.lowercase()}"

    private fun demoProfile(entity: DirectoryEntity): W4PersonProfile {
        val positions = if (entity.kind == DirectoryEntityKind.TEACHER) {
            StaffRoles.parse(entity.subtitle).ifEmpty { listOf("Teacher") }
        } else {
            emptyList()
        }
        val classes = if (entity.kind == DirectoryEntityKind.TEACHER) {
            DemoData.myClasses
                .filter { item -> item.teachers.any { it.id.equals(entity.id, ignoreCase = true) } }
                .map { item ->
                    PersonClass(
                        id = item.id,
                        name = item.subject,
                        year = item.year,
                        levelLabel = item.displayLevel.takeIf { it.isNotBlank() },
                        room = item.room?.name,
                    )
                }
        } else {
            emptyList()
        }
        return W4PersonProfile(
            entity = entity,
            email = "${entity.id}@uwcrcn.no",
            country = if (entity.kind == DirectoryEntityKind.STUDENT) entity.subtitle else null,
            birthday = if (entity.kind == DirectoryEntityKind.STUDENT) "1 January" else null,
            positions = positions,
            classes = classes,
        )
    }
}
