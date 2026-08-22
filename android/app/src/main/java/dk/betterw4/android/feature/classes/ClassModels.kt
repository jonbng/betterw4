package dk.betterw4.android.feature.classes

import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind

enum class ClassLevel {
    HIGHER,
    STANDARD,
    COMBINED,
    NONE,
    UNKNOWN,
    ;

    /** Badge shown in the UI: HL / SL / HL/SL. Empty when W4 has no IB level. */
    val badge: String
        get() = when (this) {
            HIGHER -> "HL"
            STANDARD -> "SL"
            COMBINED -> "HL/SL"
            NONE, UNKNOWN -> ""
        }

    companion object {
        fun parse(raw: String?): ClassLevel {
            val text = raw?.trim().orEmpty()
            if (text.isEmpty()) return UNKNOWN
            val compact = text.lowercase().replace(Regex("""[^a-z]"""), "")
            val first = text.first().uppercaseChar()
            return when {
                compact == "hlsl" || compact.startsWith("combined") -> COMBINED
                compact == "hl" || compact.startsWith("higher") -> HIGHER
                compact == "sl" || compact.startsWith("standard") -> STANDARD
                compact == "none" || compact == "x" -> NONE
                first == 'C' -> COMBINED
                first == 'H' -> HIGHER
                first == 'S' -> STANDARD
                first == 'X' -> NONE
                else -> UNKNOWN
            }
        }
    }
}

data class ClassRoom(
    val id: String? = null,
    val name: String,
)

data class ClassMember(
    val id: String,
    val name: String,
    val kind: DirectoryEntityKind,
    val photoUrl: String? = null,
    val level: ClassLevel = ClassLevel.UNKNOWN,
) {
    val entity: DirectoryEntity
        get() = DirectoryEntity(
            id = id,
            name = name,
            kind = kind,
            subtitle = level.badge.takeIf { it.isNotEmpty() },
            avatarUrl = photoUrl,
        )

    /**
     * True when [id] is a real UWC id, or a demo roster id. Caption-only
     * teacher slugs (`teacher-jens-jensen`) have no profile page.
     */
    val canOpenProfile: Boolean
        get() = W4Html.UWC_ID.matchEntire(id) != null
}

data class MyClass(
    val id: String,
    val subject: String,
    val subjectCode: String? = null,
    val year: String? = null,
    val block: String? = null,
    val level: ClassLevel = ClassLevel.UNKNOWN,
    val levelLabel: String? = null,
    val room: ClassRoom? = null,
    val teachers: List<ClassMember> = emptyList(),
    val students: List<ClassMember> = emptyList(),
    val loaded: Boolean = false,
) {
    val teacherNames: String
        get() = teachers.joinToString(", ") { it.name }

    val displayLevel: String
        get() = level.badge.ifBlank { levelLabel.orEmpty() }
}
