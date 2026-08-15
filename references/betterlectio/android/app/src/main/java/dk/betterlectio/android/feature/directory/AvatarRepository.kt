package dk.betterlectio.android.feature.directory

import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.scrape.StudentIdentityParser
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.offline.OfflineDirectoryStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import timber.log.Timber
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Resolves Lectio profile photo URLs for students and teachers.
 *
 * Mirrors iOS [DirectoryStore] avatar flow:
 * 1. Memory + offline catalog cache (`DirectoryEntity.avatarUrl`)
 * 2. Name → entity index for message senders
 * 3. Lazy fetch of `SkemaNy.aspx?elevid=` / `laererid=` to scrape picture id
 * 4. Persist full GetImage URL back onto the offline directory row
 *
 * Network resolution runs on an app-scoped [fetchScope] so LazyList recycling
 * (composition cancellation) does not abort in-flight SkemaNy scrapes.
 */
@Singleton
class AvatarRepository @Inject constructor(
    private val client: LectioClient,
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
    private val rateLimiter: RateLimitedAvatarLoader,
) {
    /** entityId → avatar URL (or [NONE] when fetch found no photo). */
    private val memory = ConcurrentHashMap<String, String>()

    /** normalized name → entityId for person rows. */
    private val nameIndex = ConcurrentHashMap<String, String>()

    /** In-flight network resolutions that outlive composition scopes. */
    private val inflight = ConcurrentHashMap<String, Deferred<String?>>()

    private val fetchScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val indexMutex = Mutex()
    @Volatile private var indexBuiltForStudent: String? = null

    /**
     * Peek a cached URL without network I/O (memory / rate-limiter cache / entity field).
     */
    fun peekUrl(
        entityId: String? = null,
        name: String? = null,
        teacherNumericId: String? = null,
        knownUrl: String? = null,
    ): String? {
        knownUrl?.takeIf { it.isNotBlank() }?.let { return it }

        entityId?.let { id ->
            rateLimiter.cachedUrl(id)?.let { return it }
            memory[id]?.let { return it.takeIf { u -> u != NONE } }
        }

        teacherNumericId?.let { tid ->
            val id = "T$tid"
            rateLimiter.cachedUrl(id)?.let { return it }
            memory[id]?.let { return it.takeIf { u -> u != NONE } }
        }

        name?.let { n ->
            val entityKey = nameIndex[normalizeName(n)]
            if (entityKey != null) {
                rateLimiter.cachedUrl(entityKey)?.let { return it }
                memory[entityKey]?.let { return it.takeIf { u -> u != NONE } }
            }
        }

        return null
    }

    /**
     * Resolve a photo URL, fetching from Lectio when necessary.
     * Returns null when no photo is available.
     */
    suspend fun resolveUrl(
        entityId: String? = null,
        name: String? = null,
        kind: DirectoryEntityKind? = null,
        teacherNumericId: String? = null,
        knownUrl: String? = null,
    ): String? {
        peekUrl(entityId, name, teacherNumericId, knownUrl)?.let { return it }

        val student = session.currentStudent ?: return null
        if (student.isDemo) {
            return resolveDemo(entityId, name, teacherNumericId)
        }

        ensureNameIndex(student.studentId)

        // Re-check after index warm (offline rows may have avatarUrl).
        peekUrl(entityId, name, teacherNumericId, knownUrl)?.let { return it }

        val resolvedEntityId = entityId
            ?: teacherNumericId?.let { "T$it" }
            ?: name?.let { nameIndex[normalizeName(it)] }

        if (resolvedEntityId == null) return null

        val entityKind = kind
            ?: when {
                resolvedEntityId.startsWith("T", ignoreCase = true) -> DirectoryEntityKind.TEACHER
                resolvedEntityId.startsWith("S", ignoreCase = true) -> DirectoryEntityKind.STUDENT
                else -> null
            }

        if (entityKind != DirectoryEntityKind.STUDENT && entityKind != DirectoryEntityKind.TEACHER) {
            return null
        }

        return fetchAndCache(
            entityId = resolvedEntityId,
            kind = entityKind,
            gymId = student.gymId,
            studentId = student.studentId,
            personName = name,
        )
    }

    /**
     * Store a known avatar URL (e.g. from hold-member HTML that embeds thumbnails).
     */
    suspend fun remember(entityId: String, avatarUrl: String, studentId: String? = null) {
        if (entityId.isBlank() || avatarUrl.isBlank()) return
        memory[entityId] = avatarUrl
        rateLimiter.remember(entityId, avatarUrl)
        val sid = studentId ?: session.currentStudent?.studentId ?: return
        offline.updateAvatarUrl(sid, entityId, avatarUrl)
    }

    /**
     * Batch-remember picture ids scraped from member lists.
     */
    suspend fun rememberPictureIds(
        pairs: List<Pair<String, String>>,
        gymId: Int,
        studentId: String,
    ) {
        for ((entityId, pictureId) in pairs) {
            if (entityId.isBlank() || pictureId.isBlank()) continue
            val url = AvatarUrls.fromPictureId(gymId, pictureId)
            remember(entityId, url, studentId)
        }
    }

    /** Seed the logged-in student's own picture from session identity. */
    suspend fun seedSelf(pictureId: String?, entityStudentId: String, gymId: Int) {
        if (pictureId.isNullOrBlank()) return
        val entityId = "S$entityStudentId"
        val url = AvatarUrls.fromPictureId(gymId, pictureId)
        remember(entityId, url, entityStudentId)
    }

    private suspend fun resolveDemo(
        entityId: String?,
        name: String?,
        teacherNumericId: String?,
    ): String? {
        val catalog = offline.loadAll(Student.DEMO_STUDENT_ID)
            .ifEmpty { DemoData.directory }
        entityId?.let { id ->
            catalog.firstOrNull { it.id == id }?.avatarUrl?.let { return it }
        }
        teacherNumericId?.let { tid ->
            catalog.firstOrNull { it.id == "T$tid" }?.avatarUrl?.let { return it }
        }
        name?.let { n ->
            val norm = normalizeName(n)
            catalog.firstOrNull { normalizeName(it.name) == norm }?.avatarUrl?.let { return it }
        }
        return null
    }

    private suspend fun ensureNameIndex(studentId: String) {
        if (indexBuiltForStudent == studentId && nameIndex.isNotEmpty() && memory.isNotEmpty()) {
            return
        }
        indexMutex.withLock {
            if (indexBuiltForStudent == studentId && memory.isNotEmpty()) return
            val rows = offline.loadAll(studentId)
            for (e in rows) {
                if (e.kind == DirectoryEntityKind.STUDENT || e.kind == DirectoryEntityKind.TEACHER) {
                    indexName(e.name, e.id)
                    // Subtitle may hold class/code; also re-index common display variants.
                    e.subtitle?.let { sub ->
                        if (sub.length in 2..8) {
                            // Do not map pure class codes like "3x" to people.
                        }
                    }
                    e.avatarUrl?.takeIf { it.isNotBlank() }?.let { url ->
                        memory[e.id] = url
                        rateLimiter.remember(e.id, url)
                    }
                }
            }
            // Self picture from session.
            session.currentStudent?.let { s ->
                if (!s.pictureId.isNullOrBlank()) {
                    val selfId = "S${s.studentId}"
                    val url = AvatarUrls.fromPictureId(s.gymId, s.pictureId!!)
                    memory[selfId] = url
                    rateLimiter.remember(selfId, url)
                    s.name?.let { indexName(it, selfId) }
                }
            }
            indexBuiltForStudent = studentId
        }
    }

    private suspend fun fetchAndCache(
        entityId: String,
        kind: DirectoryEntityKind,
        gymId: Int,
        studentId: String,
        personName: String?,
    ): String? {
        memory[entityId]?.let { cached ->
            return cached.takeIf { it != NONE }
        }

        // Deduplicate: one app-scoped job per entity. Composition may cancel while
        // awaiting, but the scrape continues so the next bind can reuse the result.
        val existing = inflight[entityId]
        if (existing != null) {
            return existing.await()
        }

        val deferred = fetchScope.async {
            try {
                doFetchAndCache(entityId, kind, gymId, studentId, personName)
            } finally {
                inflight.remove(entityId)
            }
        }
        val winner = inflight.putIfAbsent(entityId, deferred)
        if (winner != null) {
            deferred.cancel()
            return winner.await()
        }
        return deferred.await()
    }

    private suspend fun doFetchAndCache(
        entityId: String,
        kind: DirectoryEntityKind,
        gymId: Int,
        studentId: String,
        personName: String?,
    ): String? {
        memory[entityId]?.let { cached ->
            return cached.takeIf { it != NONE }
        }

        val numericId = DirectoryParser.numericId(entityId)
        if (numericId.isBlank()) {
            memory[entityId] = NONE
            return null
        }

        val idParam = if (kind == DirectoryEntityKind.TEACHER) "laererid" else "elevid"
        val path = "SkemaNy.aspx?$idParam=$numericId"

        return when (
            val res = client.get(path, priority = FetchPriority.Opportunistic)
        ) {
            is AppResult.Failure -> {
                Timber.d("Avatar fetch failed for %s: %s", entityId, res.error)
                // Transient — do not cache NONE so a later attempt can retry.
                null
            }
            is AppResult.Success -> {
                val pictureId = StudentIdentityParser.parse(res.data.body).pictureId
                    ?: parsePictureIdFallback(res.data.body)
                if (pictureId.isNullOrBlank()) {
                    memory[entityId] = NONE
                    Timber.d("No picture id for %s (%s)", entityId, personName)
                    return null
                }
                val url = AvatarUrls.fromPictureId(gymId, pictureId)
                memory[entityId] = url
                rateLimiter.remember(entityId, url)
                personName?.let { indexName(it, entityId) }
                offline.updateAvatarUrl(studentId, entityId, url)
                url
            }
        }
    }

    /** Index several normalized keys for a person so message titles match directory rows. */
    private fun indexName(name: String, entityId: String) {
        val primary = normalizeName(name)
        if (primary.isNotBlank()) nameIndex[primary] = entityId
        // Also index raw lowercased form without paren strip (rare exact matches)
        val raw = name.trim().lowercase().replace(Regex("\\s+"), " ")
        if (raw.isNotBlank() && raw != primary) nameIndex[raw] = entityId
    }

    private fun parsePictureIdFallback(html: String): String? {
        // Broader fallback when the header id is missing (some teacher pages).
        return Regex(
            """pictureid=(\d+)""",
            RegexOption.IGNORE_CASE,
        ).find(html)?.groupValues?.getOrNull(1)
    }

    companion object {
        /** Sentinel: remote fetch completed with no photo. */
        private const val NONE = ""

        /**
         * Normalize person names for avatar lookup.
         * Matches extension `normalizeNameForLookup` / iOS `normalizedLookupName`:
         * strip parenthetical suffixes like `(MPS)`, `(1x)`, `(k)` then lowercase.
         *
         * Message list titles are often `"Full Name (CODE)"` while the directory
         * stores `"Full Name"` — without stripping, lookup always misses.
         */
        fun normalizeName(name: String): String {
            var clean = name.trim()
            // Drop all parenthetical groups: (MPS), (k), (1x 12), etc.
            clean = clean.replace(Regex("""\s*\([^)]*\)"""), "")
            if (clean.endsWith("(k)", ignoreCase = true)) {
                clean = clean.dropLast(3)
            }
            return clean.trim()
                .lowercase()
                .replace(Regex("\\s+"), " ")
                .trim()
        }
    }
}
