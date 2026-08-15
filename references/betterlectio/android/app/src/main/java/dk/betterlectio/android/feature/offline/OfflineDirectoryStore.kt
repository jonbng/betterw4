package dk.betterlectio.android.feature.offline

import dk.betterlectio.android.feature.directory.DirectoryEntity
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.directory.DirectoryParser
import dk.betterlectio.android.feature.offline.OfflineDatabase
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OfflineDirectoryStore @Inject constructor(
    private val db: OfflineDatabase,
) {
    private val dao get() = db.directoryDao()

    suspend fun loadAll(studentId: String): List<DirectoryEntity> =
        dao.loadAll(studentId).map { it.toModel() }

    /**
     * Upsert entities without removing other rows (e.g. hold-member bootstrap).
     * Merges with existing rows so class-code / initials labels never overwrite real names,
     * and avatar URLs are preserved when the incoming row lacks one.
     */
    suspend fun saveAll(studentId: String, entities: List<DirectoryEntity>) {
        if (entities.isEmpty()) return
        val existingById = loadAll(studentId).associateBy { it.id }
        val merged = entities.map { incoming ->
            DirectoryParser.mergeEntity(existingById[incoming.id], incoming)
        }
        val now = System.currentTimeMillis()
        dao.upsertAll(
            merged.map { e ->
                DirectoryEntityRow(
                    compositeKey = "$studentId|${e.id}",
                    studentId = studentId,
                    entityId = e.id,
                    name = e.name,
                    kind = e.kind.name,
                    subtitle = e.subtitle,
                    avatarUrl = e.avatarUrl,
                    updatedAt = now,
                )
            },
        )
    }

    /**
     * Replace the full offline snapshot for [studentId] (iOS `replaceDirectorySnapshot`).
     * Clears prior rows first so bad HTML scrapes and stale entities are purged.
     * Preserves previously resolved [DirectoryEntity.avatarUrl] values by entity id.
     */
    suspend fun replaceAll(studentId: String, entities: List<DirectoryEntity>) {
        val previousAvatars = loadAll(studentId)
            .mapNotNull { e -> e.avatarUrl?.takeIf { it.isNotBlank() }?.let { e.id to it } }
            .toMap()
        val merged = entities.map { e ->
            if (e.avatarUrl.isNullOrBlank() && previousAvatars.containsKey(e.id)) {
                e.copy(avatarUrl = previousAvatars[e.id])
            } else {
                e
            }
        }
        dao.clearStudent(studentId)
        saveAll(studentId, merged)
    }

    /**
     * Patch a single entity's avatar URL without rewriting the full catalog.
     * No-op when the entity row is not yet offline.
     */
    suspend fun updateAvatarUrl(studentId: String, entityId: String, avatarUrl: String) {
        if (avatarUrl.isBlank()) return
        val existing = dao.loadAll(studentId).firstOrNull { it.entityId == entityId } ?: return
        if (existing.avatarUrl == avatarUrl) return
        dao.upsertAll(
            listOf(
                existing.copy(
                    avatarUrl = avatarUrl,
                    updatedAt = System.currentTimeMillis(),
                ),
            ),
        )
    }

    private fun DirectoryEntityRow.toModel() = DirectoryEntity(
        id = entityId,
        name = name,
        kind = runCatching { DirectoryEntityKind.valueOf(kind) }
            .getOrDefault(DirectoryEntityKind.OTHER),
        subtitle = subtitle,
        avatarUrl = avatarUrl,
    )
}
