package dk.betterlectio.android.feature.supabase

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Thin adapter over [SupabaseSubjectService] for callers that use a simpler
 * subject_key / display_name / color_argb model (e.g. MoreViewModel).
 */
@Singleton
class SupabaseSubjectSync @Inject constructor(
    private val manager: SupabaseManager,
    private val subjects: SupabaseSubjectService,
) {
    data class SubjectMapping(
        val subjectKey: String,
        val displayName: String?,
        val colorArgb: Long?,
        val mappingId: String? = null,
    )

    fun isConfigured(): Boolean = manager.isConfigured

    suspend fun fetchMappings(studentId: String, schoolId: String): List<SubjectMapping>? {
        if (!manager.isConfigured) return null
        val remote = subjects.fetchMappings(studentId, schoolId)
        if (remote.isEmpty()) return emptyList()
        return remote
            .filter { it.deletedAt == null }
            .map {
                SubjectMapping(
                    subjectKey = it.canonicalKey,
                    displayName = it.displayName,
                    colorArgb = SupabaseSubjectService.hueToArgb(it.displayColorHue),
                    mappingId = it.mappingId,
                )
            }
    }

    suspend fun upsertMapping(
        studentId: String,
        schoolId: String,
        mapping: SubjectMapping,
    ): Boolean {
        if (!manager.isConfigured) return false
        val mappingId = mapping.mappingId
            ?: subjects.fetchMappings(studentId, schoolId)
                .firstOrNull {
                    it.canonicalKey.equals(mapping.subjectKey, ignoreCase = true) ||
                        it.defaultName.equals(mapping.subjectKey, ignoreCase = true) ||
                        it.displayName.equals(mapping.subjectKey, ignoreCase = true)
                }?.mappingId
            ?: return false
        subjects.upsertMappingOverride(
            studentId = studentId,
            schoolId = schoolId,
            mappingId = mappingId,
            displayName = mapping.displayName,
            colorHue = mapping.colorArgb?.let { SupabaseSubjectService.argbToHue(it) },
            icon = null,
        )
        return true
    }
}
