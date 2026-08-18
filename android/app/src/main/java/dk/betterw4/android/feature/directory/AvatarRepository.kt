package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.offline.OfflineDirectoryStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.text.Normalizer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Resolves W4 portrait URLs for students and teachers.
 *
 * W4 photos are derived from a UWC id (`/files/user_photos/{uwc_id}_thumb.jpg`).
 * Calendar bricks only carry the teacher's display name, so this repository
 * indexes the offline people catalog by normalized name and peeks/guesses
 * the thumb URL from the matching id.
 */
@Singleton
class AvatarRepository @Inject constructor(
    private val rateLimiter: RateLimitedAvatarLoader,
    private val session: SessionController,
    private val offline: OfflineDirectoryStore,
) {
    private val index = AvatarIndex(rateLimiter)
    private val indexMutex = Mutex()
    @Volatile private var indexedForStudent: String? = null

    val indexEpoch: StateFlow<Int> = index.generation

    fun peekUrl(
        entityId: String? = null,
        name: String? = null,
        teacherNumericId: String? = null,
        knownUrl: String? = null,
    ): String? = index.peek(entityId, name, teacherNumericId, knownUrl)

    @Suppress("UNUSED_PARAMETER")
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
        peekUrl(entityId, name, teacherNumericId, knownUrl)?.let { return it }
        return null
    }

    fun remember(entityId: String, url: String, name: String? = null) {
        index.remember(entityId, url, name)
    }

    fun ingest(entities: Collection<DirectoryEntity>) {
        index.ingest(entities)
    }

    suspend fun seedSelf(pictureId: String?, entityStudentId: String, gymId: Int) {
        val id = AvatarIndex.uwcId(entityStudentId) ?: entityStudentId
        val url = pictureId?.takeIf { it.startsWith("http") }
            ?: AvatarIndex.derivedUrl(id)
        if (url != null) {
            index.remember(id, url, session.currentStudent?.name)
        } else {
            session.currentStudent?.name?.let { index.indexName(it, id) }
        }
        @Suppress("UNUSED_VARIABLE")
        val unusedGym = gymId
    }

    private suspend fun ensureNameIndex(studentId: String) {
        if (indexedForStudent == studentId && index.hasNames()) return
        indexMutex.withLock {
            if (indexedForStudent == studentId && index.hasNames()) return
            val rows = offline.loadAll(studentId)
            if (rows.isNotEmpty()) {
                index.ingest(rows)
                indexedForStudent = studentId
            }
        }
    }

    private fun resolveDemo(
        entityId: String?,
        name: String?,
        teacherNumericId: String?,
    ): String? {
        val catalog = DemoData.directory
        entityId?.let { id ->
            catalog.firstOrNull { it.id.equals(id, ignoreCase = true) }
                ?.avatarUrl
                ?.let { return it }
        }
        teacherNumericId?.let { tid ->
            catalog.firstOrNull {
                it.id.equals(tid, ignoreCase = true) || it.id.equals("T$tid", ignoreCase = true)
            }?.avatarUrl?.let { return it }
        }
        name?.let { n ->
            val norm = AvatarIndex.normalizeName(n)
            catalog.firstOrNull { AvatarIndex.normalizeName(it.name) == norm }
                ?.avatarUrl
                ?.let { return it }
        }
        return null
    }

    companion object {
        fun normalizeName(name: String): String = AvatarIndex.normalizeName(name)
    }
}

/**
 * In-memory name → UWC id index plus derived `/files/user_photos/{id}_thumb.jpg` URLs.
 * Calendar bricks resolve portraits through here after the people catalog is ingested.
 */
internal class AvatarIndex(
    private val rateLimiter: RateLimitedAvatarLoader = RateLimitedAvatarLoader(),
) {
    private val memory = ConcurrentHashMap<String, String>()
    private val nameIndex = ConcurrentHashMap<String, String>()
    private val generationValue = AtomicInteger(0)
    private val _generation = MutableStateFlow(0)
    val generation: StateFlow<Int> = _generation.asStateFlow()

    fun hasNames(): Boolean = nameIndex.isNotEmpty()

    fun peek(
        entityId: String? = null,
        name: String? = null,
        teacherNumericId: String? = null,
        knownUrl: String? = null,
    ): String? {
        DirectoryParser.pickAvatar(null, knownUrl)?.let { return it }
        entityId?.let { pickCached(it) }?.let { return it }
        teacherNumericId?.let { pickCached(it) }?.let { return it }
        name?.let { n ->
            val key = nameIndex[normalizeName(n)] ?: return@let
            pickCached(key)?.let { return it }
        }

        derivedUrl(entityId)?.let { return it }
        derivedUrl(teacherNumericId)?.let { return it }
        name?.let { n ->
            val key = nameIndex[normalizeName(n)] ?: return@let
            derivedUrl(key)?.let { return it }
        }
        return null
    }

    fun remember(entityId: String, url: String?, name: String? = null) {
        rememberInternal(entityId, url, name, bump = true)
    }

    fun ingest(entities: Collection<DirectoryEntity>) {
        for (entity in entities) {
            if (entity.kind != DirectoryEntityKind.STUDENT &&
                entity.kind != DirectoryEntityKind.TEACHER
            ) {
                continue
            }
            rememberInternal(entity.id, entity.avatarUrl, entity.name, bump = false)
        }
        bump()
    }

    fun indexName(name: String, entityId: String) {
        val key = normalizeName(name)
        if (key.isNotBlank() && entityId.isNotBlank()) {
            nameIndex[key] = entityId
            bump()
        }
    }

    private fun rememberInternal(
        entityId: String,
        url: String?,
        name: String?,
        bump: Boolean,
    ) {
        if (entityId.isBlank()) return
        val usable = DirectoryParser.pickAvatar(null, url) ?: derivedUrl(entityId)
        if (usable != null) {
            memory[entityId] = usable
            rateLimiter.remember(entityId, usable)
        }
        name?.let { n ->
            val key = normalizeName(n)
            if (key.isNotBlank()) nameIndex[key] = entityId
        }
        if (bump) bump()
    }

    private fun pickCached(id: String): String? =
        DirectoryParser.pickAvatar(null, rateLimiter.cachedUrl(id))
            ?: DirectoryParser.pickAvatar(null, memory[id])

    private fun bump() {
        _generation.value = generationValue.incrementAndGet()
    }

    companion object {
        fun uwcId(raw: String?): String? {
            val value = raw?.trim().orEmpty()
            if (value.isEmpty()) return null
            return W4Html.UWC_ID.find(value)?.groupValues?.get(1)?.lowercase()
        }

        fun derivedUrl(raw: String?): String? {
            val id = uwcId(raw) ?: return null
            return W4PeopleParser.guessPhotoUrl(id)
        }

        /**
         * Lowercased, diacritic-folded, parentheticals stripped.
         * Tooltip `"István Poór"` must match directory `"Istvan Poor"`.
         */
        fun normalizeName(name: String): String {
            var clean = name.trim()
            clean = clean.replace(PARENTHETICAL, "")
            if (clean.endsWith("(k)", ignoreCase = true)) {
                clean = clean.dropLast(3)
            }
            val folded = Normalizer.normalize(clean, Normalizer.Form.NFD)
                .replace(COMBINING_MARKS, "")
            return folded.lowercase()
                .replace(NON_ALNUM, " ")
                .replace(MULTI_SPACE, " ")
                .trim()
        }

        private val PARENTHETICAL = Regex("""\s*\([^)]*\)""")
        private val COMBINING_MARKS = Regex("\\p{M}+")
        private val NON_ALNUM = Regex("""[^\p{L}\p{N}]+""")
        private val MULTI_SPACE = Regex("""\s+""")
    }
}
