package dk.betterlectio.android.feature.directory

import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.offline.OfflineDirectoryStore
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Opportunistic full-catalog snapshot + hold-member bootstrap after auth.
 *
 * iOS / extension parity: fetch `FindSkemaAdv.aspx`, resolve the AvanceretSkema
 * DropDown URL, parse the full JSON catalog (all students/teachers/holds/rooms),
 * then replace the offline Room snapshot. Do **not** use FindSkema letter pages
 * — those only return the first letter group (e.g. names starting with "A").
 */
@Singleton
class DirectorySyncService @Inject constructor(
    private val client: LectioClient,
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
    private val cache: SimpleCache,
) {
    private val mutex = Mutex()
    @Volatile var lastSyncEpochMs: Long? = null
        private set

    /**
     * Fetch the full school directory and persist offline.
     * Safe to call multiple times; concurrent calls serialize.
     */
    suspend fun syncFullCatalog(): AppResult<Int> = mutex.withLock {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        if (student.isDemo) {
            offline.replaceAll(student.studentId, DemoData.directory)
            lastSyncEpochMs = System.currentTimeMillis()
            return AppResult.Success(DemoData.directory.size)
        }

        val gymId = student.gymId
        val cacheKey = dropdownCacheKey(gymId)

        // Prefer a fresh network fetch; fall back to cached JSON if Lectio is down.
        val entities = when (val remote = fetchDropdownCatalog(gymId, cacheKey)) {
            is AppResult.Success -> remote.data
            is AppResult.Failure -> {
                val cachedJson = cache.get(cacheKey)
                if (cachedJson != null) {
                    Timber.w(
                        "Directory sync network failed (%s); using cached dropdown JSON",
                        remote.error,
                    )
                    DirectoryParser.parseDropdownJson(cachedJson)
                } else {
                    val existing = offline.loadAll(student.studentId)
                    if (existing.isNotEmpty()) {
                        Timber.w("Directory sync failed; keeping %d offline entities", existing.size)
                        lastSyncEpochMs = System.currentTimeMillis()
                        return AppResult.Success(existing.size)
                    }
                    return remote
                }
            }
        }

        if (entities.isEmpty()) {
            Timber.w("Directory dropdown parsed 0 entities")
            val existing = offline.loadAll(student.studentId)
            if (existing.isNotEmpty()) return AppResult.Success(existing.size)
            return AppResult.Failure(AppError.Parsing("Empty directory catalog"))
        }

        // Full snapshot replace so prior bogus HTML scrapes (nav buttons as students) are purged.
        offline.replaceAll(student.studentId, entities)
        lastSyncEpochMs = System.currentTimeMillis()
        Timber.i(
            "Directory catalog cached %d entities (students=%d teachers=%d rooms=%d holds=%d)",
            entities.size,
            entities.count { it.kind == DirectoryEntityKind.STUDENT },
            entities.count { it.kind == DirectoryEntityKind.TEACHER },
            entities.count { it.kind == DirectoryEntityKind.ROOM },
            entities.count { it.kind == DirectoryEntityKind.HOLD },
        )

        // Bootstrap a few hold member lists for offline classmate search (iOS: homepage holds).
        bootstrapHoldMembers(
            entities.filter { it.kind == DirectoryEntityKind.HOLD }.take(12),
        )
        AppResult.Success(entities.size)
    }

    private suspend fun fetchDropdownCatalog(
        gymId: Int,
        cacheKey: String,
    ): AppResult<List<DirectoryEntity>> {
        val adv = client.get("FindSkemaAdv.aspx", FetchPriority.Opportunistic)
        if (adv is AppResult.Failure) return adv
        val html = (adv as AppResult.Success).data.body

        val relativePath = DirectoryParser.parseDropdownUrl(html)
            ?: return AppResult.Failure(AppError.Parsing("AvanceretSkema dropdown URL not found"))

        val dropdownPath = normalizeLectioPath(relativePath)
        val jsonRes = client.get(dropdownPath, FetchPriority.Opportunistic)
        if (jsonRes is AppResult.Failure) return jsonRes
        val jsonBody = (jsonRes as AppResult.Success).data.body

        cache.put(cacheKey, jsonBody)
        // Drop legacy per-kind FindSkema HTML caches if present.
        for (kind in DirectoryEntityKind.entries) {
            cache.remove("dir_${gymId}_$kind")
        }
        cache.remove("dir_${gymId}_all")

        val parsed = DirectoryParser.parseDropdownJson(jsonBody)
        return AppResult.Success(parsed)
    }

    /**
     * Load and cache members for the given holds (best-effort).
     */
    suspend fun bootstrapHoldMembers(holds: List<DirectoryEntity>) {
        val student = session.currentStudent ?: return
        if (student.isDemo) return
        for (hold in holds) {
            if (hold.kind != DirectoryEntityKind.HOLD && hold.kind != DirectoryEntityKind.CLASS) continue
            val holdElementId = DirectoryParser.numericId(hold.id)
            if (holdElementId.isEmpty()) continue
            val path =
                "subnav/members.aspx?holdelementid=$holdElementId&showteachers=1&showstudents=1&reporttype=withpics"
            when (val res = client.get(path, FetchPriority.Opportunistic)) {
                is AppResult.Success -> {
                    val members = DirectoryParser.parseMembers(res.data.body, hold)
                    if (members.isNotEmpty()) {
                        cache.put("dir_members_${student.gymId}_${hold.id}", res.data.body)
                        offline.saveAll(student.studentId, members)
                    }
                }
                is AppResult.Failure -> Timber.w("Hold members bootstrap failed for %s", hold.id)
            }
        }
    }

    companion object {
        fun dropdownCacheKey(gymId: Int): String = "dir_dropdown_$gymId"

        /**
         * DropDown URLs from Lectio are absolute paths (`/lectio/{gym}/cache/…`).
         * [LectioUrls.resolve] would otherwise double-prefix the gym base.
         */
        fun normalizeLectioPath(path: String): String {
            val trimmed = path.trim()
            return when {
                trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
                trimmed.startsWith("/lectio/") -> "https://www.lectio.dk$trimmed"
                else -> trimmed.removePrefix("/")
            }
        }
    }
}
