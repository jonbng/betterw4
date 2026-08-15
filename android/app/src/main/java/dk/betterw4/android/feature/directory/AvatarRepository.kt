package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.session.SessionController
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AvatarRepository @Inject constructor(
    private val rateLimiter: RateLimitedAvatarLoader,
    private val session: SessionController,
) {
    private val memory = ConcurrentHashMap<String, String>()
    private val nameIndex = ConcurrentHashMap<String, String>()

    fun peekUrl(
        entityId: String? = null,
        name: String? = null,
        teacherNumericId: String? = null,
        knownUrl: String? = null,
    ): String? {
        knownUrl?.let { DirectoryParser.pickAvatar(null, it) }?.let { return it }
        entityId?.let { id -> pickCached(id)?.let { return it } }
        teacherNumericId?.let { tid -> pickCached(tid)?.let { return it } }
        name?.let { n ->
            val key = nameIndex[normalizeName(n)] ?: return@let
            pickCached(key)?.let { return it }
        }
        return null
    }

    suspend fun resolveUrl(
        entityId: String? = null,
        name: String? = null,
        kind: DirectoryEntityKind? = null,
        teacherNumericId: String? = null,
        knownUrl: String? = null,
    ): String? {
        peekUrl(entityId, name, teacherNumericId, knownUrl)?.let { return it }
        return null
    }

    fun remember(entityId: String, url: String) {
        val usable = DirectoryParser.pickAvatar(null, url) ?: return
        if (entityId.isBlank()) return
        memory[entityId] = usable
        rateLimiter.remember(entityId, usable)
    }

    suspend fun seedSelf(pictureId: String?, entityStudentId: String, gymId: Int) {
        val id = W4Html.UWC_ID.find(entityStudentId)?.groupValues?.get(1)?.lowercase()
            ?: entityStudentId
        val url = pictureId?.takeIf { it.startsWith("http") }
            ?: W4PeopleParser.guessPhotoUrl(id)
        remember(id, url)
        session.currentStudent?.name?.let { nameIndex[normalizeName(it)] = id }
        @Suppress("UNUSED_VARIABLE")
        val unusedGym = gymId
    }

    private fun pickCached(id: String): String? =
        DirectoryParser.pickAvatar(null, rateLimiter.cachedUrl(id))
            ?: DirectoryParser.pickAvatar(null, memory[id])

    private fun normalizeName(name: String): String = name.trim().lowercase()
}
