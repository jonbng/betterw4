package dk.betterlectio.android.feature.directory

enum class DirectoryEntityKind {
    STUDENT, TEACHER, CLASS, HOLD, ROOM, GROUP, RESOURCE, OTHER
}

data class DirectoryEntity(
    val id: String,
    val name: String,
    val kind: DirectoryEntityKind,
    val subtitle: String? = null,
    val avatarUrl: String? = null,
)
