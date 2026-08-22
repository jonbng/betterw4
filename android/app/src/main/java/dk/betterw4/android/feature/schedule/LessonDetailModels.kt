package dk.betterw4.android.feature.schedule

import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind

data class LessonParticipant(
    val id: String,
    val name: String,
    val role: String? = null,
    val kind: DirectoryEntityKind? = null,
    val avatarUrl: String? = null,
) {
    companion object {
        fun fromDirectory(entity: DirectoryEntity): LessonParticipant {
            val role = entity.subtitle?.takeIf { it.isNotBlank() }
                ?: when (entity.kind) {
                    DirectoryEntityKind.TEACHER -> "Teacher"
                    DirectoryEntityKind.STUDENT -> "Student"
                }
            return LessonParticipant(
                id = entity.id,
                name = entity.name,
                role = role,
                kind = entity.kind,
                avatarUrl = entity.avatarUrl,
            )
        }
    }

    fun toEntity(): DirectoryEntity = DirectoryEntity(
        id = id,
        name = name,
        kind = kind ?: DirectoryEntityKind.STUDENT,
        subtitle = role,
        avatarUrl = avatarUrl,
    )
}

data class LessonResource(
    val title: String,
    val url: String,
    val isFile: Boolean = false,
)

data class LessonContentBlock(
    val kind: String, // heading | paragraph | note | image | divider
    val text: String,
    val url: String? = null,
    /** True when under Lektier section or doc-homework (iOS). */
    val isHomework: Boolean = false,
)

data class LessonDetail(
    val eventId: String,
    val title: String,
    val note: String? = null,
    val homework: String? = null,
    val contentBlocks: List<LessonContentBlock> = emptyList(),
    val participants: List<LessonParticipant> = emptyList(),
    val resources: List<LessonResource> = emptyList(),
    /** Hold element id (`HE123`) from activity detail nav — used to load members.aspx. */
    val holdId: String? = null,
)

data class PrivateEventDraft(
    val title: String,
    val startDate: String, // dd/MM-yyyy
    val startTime: String, // HH:mm
    val endDate: String,
    val endTime: String,
    val note: String = "",
    /** When set, repository performs update instead of create. */
    val eventId: String? = null,
    val isAllDay: Boolean = false,
)
