package dk.betterw4.android.feature.classes

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
                compact == "hl" || compact.startsWith("higher") || first == 'H' -> HIGHER
                compact == "sl" || compact.startsWith("standard") || first == 'S' -> STANDARD
                compact.startsWith("combined") || compact == "c" || first == 'C' -> COMBINED
                compact == "none" || compact == "x" || first == 'X' -> NONE
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
