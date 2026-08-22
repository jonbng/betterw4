package dk.betterw4.android.feature.teachers

import dk.betterw4.android.feature.classes.ClassLevel
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind

/**
 * One row on `people/students/staff`. The caption under the name is the role
 * (`Core meetings`, `Economics`); a trailing HL/SL is split into [level].
 */
data class MyTeacher(
    val id: String,
    val name: String,
    val role: String? = null,
    val level: ClassLevel = ClassLevel.UNKNOWN,
    val photoUrl: String? = null,
) {
    val displayLevel: String
        get() = level.badge

    val entity: DirectoryEntity
        get() = DirectoryEntity(
            id = id,
            name = name,
            kind = DirectoryEntityKind.TEACHER,
            subtitle = role,
            avatarUrl = photoUrl,
        )
}
