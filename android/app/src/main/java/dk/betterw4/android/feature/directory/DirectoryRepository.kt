package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.offline.OfflineDirectoryStore
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DirectoryRepository @Inject constructor(
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
    private val syncService: DirectorySyncService,
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

    suspend fun loadMembers(entity: DirectoryEntity): AppResult<List<DirectoryEntity>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                DemoData.directoryMembers[entity.id]
                    ?: DemoData.directory.filter { it.kind == DirectoryEntityKind.STUDENT },
            )
        }
        return search("", DirectoryEntityKind.STUDENT)
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
}
