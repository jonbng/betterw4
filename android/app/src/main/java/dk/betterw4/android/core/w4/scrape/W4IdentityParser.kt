package dk.betterw4.android.core.w4.scrape

import dk.betterw4.android.core.w4.W4Html

data class StudentIdentity(
    val studentId: String?,
    val teacherId: String? = null,
    val name: String? = null,
    val pictureId: String? = null,
) {
    val personId: String? get() = studentId ?: teacherId
}

/**
 * Logged-in W4 chrome: Welcome name + uwc_id. Delegates to [W4Html].
 */
object W4IdentityParser {
    fun parse(html: String): StudentIdentity = StudentIdentity(
        studentId = W4Html.uwcId(html),
        teacherId = null,
        name = W4Html.displayName(html),
        pictureId = null,
    )
}
