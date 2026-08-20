package dk.betterw4.android.feature.directory

enum class DirectoryEntityKind {
    STUDENT, TEACHER
}

data class DirectoryEntity(
    val id: String,
    val name: String,
    val kind: DirectoryEntityKind,
    val subtitle: String? = null,
    val avatarUrl: String? = null,
    /** `"1"` or `"2"` when the row stated an IB year. */
    val year: String? = null,
) {
    val resolvedYear: String?
        get() = year ?: DirectoryYear.parse(subtitle)
}
