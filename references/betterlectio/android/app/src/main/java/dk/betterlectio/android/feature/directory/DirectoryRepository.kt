package dk.betterlectio.android.feature.directory

import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.offline.OfflineDirectoryStore
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DirectoryRepository @Inject constructor(
    private val client: LectioClient,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
    private val syncService: DirectorySyncService,
    private val avatars: AvatarRepository,
) {
    /**
     * Search the school directory. Prefers the offline full-catalog snapshot
     * (from [DirectorySyncService]); triggers a full dropdown sync when empty.
     * Never scrapes a single FindSkema letter page as the catalog source.
     */
    suspend fun search(query: String, kind: DirectoryEntityKind? = null): AppResult<List<DirectoryEntity>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(filterParsed(DemoData.directory, query, kind))
        }

        var catalog = offline.loadAll(student.studentId)
        if (catalog.isEmpty()) {
            // Try in-memory/file cache of the dropdown JSON before hitting network again.
            val cachedJson = cache.get(DirectorySyncService.dropdownCacheKey(student.gymId))
            if (cachedJson != null) {
                catalog = DirectoryParser.parseDropdownJson(cachedJson)
                if (catalog.isNotEmpty()) {
                    offline.replaceAll(student.studentId, catalog)
                }
            }
        }

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
            // Drop legacy HTML scrapes (nav chrome, fake item-* ids) still in Room.
            .filter { DirectoryParser.isValidPrefixedId(it.id) }
            .filter { !DirectoryParser.looksLikeNavChrome(it.name) }
            .filter { !DirectoryParser.looksLikeIdColumnLabel(it.name) }
            .filter {
                q.isEmpty() ||
                    it.name.lowercase().contains(q) ||
                    it.subtitle?.lowercase()?.contains(q) == true
            }
            .toList()
    }

    /** Members of a class/hold (demo always works; live parses elevliste HTML). */
    suspend fun loadMembers(entity: DirectoryEntity): AppResult<List<DirectoryEntity>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                DemoData.directoryMembers[entity.id]
                    ?: listOf(
                        DirectoryEntity("S1", "Demo Elev", DirectoryEntityKind.STUDENT, entity.name),
                        DirectoryEntity("S2", "Anna Andersen", DirectoryEntityKind.STUDENT, entity.name),
                    ),
            )
        }

        val holdElementId = DirectoryParser.numericId(entity.id)
        val path = when (entity.kind) {
            DirectoryEntityKind.CLASS, DirectoryEntityKind.HOLD, DirectoryEntityKind.GROUP ->
                // Extension ActivityClassModal: showteachers + showstudents + withpics
                "subnav/members.aspx?holdelementid=$holdElementId&showteachers=1&showstudents=1&reporttype=withpics"
            else -> "FindSkemaBew.aspx?type=elev&nosubnav=1&relatedto=$holdElementId"
        }

        val membersCacheKey = "dir_members_${student.gymId}_${entity.id}"
        cache.get(membersCacheKey)?.let { html ->
            val parsed = enrichMembersFromCatalog(
                student.studentId,
                DirectoryParser.parseMembers(html, entity, gymId = student.gymId),
            )
            if (parsed.isNotEmpty()) {
                rememberMemberAvatars(student.studentId, parsed)
                return AppResult.Success(parsed)
            }
        }

        return when (val res = client.get(path)) {
            is AppResult.Failure -> when (val alt = client.get("ElevKlasseListe.aspx")) {
                is AppResult.Success -> {
                    val members = enrichMembersFromCatalog(
                        student.studentId,
                        DirectoryParser.parseMembers(
                            alt.data.body,
                            entity,
                            gymId = student.gymId,
                        ),
                    )
                    rememberMemberAvatars(student.studentId, members)
                    AppResult.Success(members)
                }
                is AppResult.Failure -> res
            }
            is AppResult.Success -> {
                cache.put(membersCacheKey, res.data.body)
                val members = enrichMembersFromCatalog(
                    student.studentId,
                    DirectoryParser.parseMembers(
                        res.data.body,
                        entity,
                        gymId = student.gymId,
                    ),
                )
                if (members.isNotEmpty()) {
                    offline.saveAll(student.studentId, members)
                    rememberMemberAvatars(student.studentId, members)
                }
                AppResult.Success(members)
            }
        }
    }

    private suspend fun enrichMembersFromCatalog(
        studentId: String,
        members: List<DirectoryEntity>,
    ): List<DirectoryEntity> {
        if (members.isEmpty()) return members
        val catalog = offline.loadAll(studentId).associateBy { it.id }
        if (catalog.isEmpty()) return members
        return members.map { m -> DirectoryParser.mergeEntity(catalog[m.id], m) }
    }

    private suspend fun rememberMemberAvatars(studentId: String, members: List<DirectoryEntity>) {
        for (m in members) {
            val url = m.avatarUrl ?: continue
            avatars.remember(m.id, url, studentId)
        }
    }

    /** Offline catalog snapshot for search-before-network UX. */
    suspend fun offlineCatalog(): List<DirectoryEntity> {
        val student = session.currentStudent ?: return emptyList()
        return offline.loadAll(student.studentId)
            .filter { DirectoryParser.isValidPrefixedId(it.id) }
            .filter { !DirectoryParser.looksLikeNavChrome(it.name) }
            .filter { !DirectoryParser.looksLikeIdColumnLabel(it.name) }
    }
}
