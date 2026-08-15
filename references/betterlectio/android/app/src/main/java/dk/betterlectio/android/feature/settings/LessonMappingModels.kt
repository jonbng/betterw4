package dk.betterlectio.android.feature.settings

import kotlinx.serialization.Serializable

/**
 * Resolved school + user lesson mapping for a single [canonicalKey].
 * Mirrors iOS `SubjectMapper.ResolvedLessonMapping` / Supabase v2 row shape.
 */
@Serializable
data class ResolvedLessonMapping(
    val mappingId: String,
    val canonicalKey: String,
    val defaultName: String,
    val defaultColorHue: Int,
    val defaultIcon: String? = null,
    val displayName: String,
    val displayColorHue: Int,
    val displayIcon: String? = null,
) {
    val hasNameOverride: Boolean
        get() = displayName != defaultName

    val hasColorOverride: Boolean
        get() = displayColorHue != defaultColorHue

    val hasIconOverride: Boolean
        get() = displayIcon != null && displayIcon != defaultIcon

    val hasAnyOverride: Boolean
        get() = hasNameOverride || hasColorOverride || hasIconOverride
}

/**
 * Subject row for settings lists (canonical key + resolved display name).
 */
data class SubjectInfo(
    val code: String,
    val name: String,
    val mappingId: String? = null,
) {
    val id: String get() = code
}
