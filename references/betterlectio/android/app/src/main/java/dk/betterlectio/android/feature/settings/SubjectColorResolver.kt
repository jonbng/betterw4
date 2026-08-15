package dk.betterlectio.android.feature.settings

import dk.betterlectio.android.feature.supabase.SupabaseSubjectService

/**
 * Pure subject → ARGB resolution.
 * Prefer [SettingsStore.colorForSubject] which uses live lesson mappings;
 * this helper remains for tests and callers with an explicit map.
 */
object SubjectColorResolver {
    fun resolve(
        subjectKey: String,
        custom: Map<String, Long>,
        palette: List<Long> = SettingsStore.DEFAULT_PALETTE,
    ): Long {
        val key = subjectKey.trim()
        if (key.isEmpty()) return palette.first()
        custom[key]?.let { return it }
        val canonical = SubjectMapper.canonicalKey(key)
        if (canonical != null) {
            custom[canonical]?.let { return it }
            return SupabaseSubjectService.hueToArgb(SubjectMapper.defaultColorHue(canonical))
        }
        return palette[kotlin.math.abs(key.hashCode()) % palette.size]
    }

    fun resolveHue(
        subjectKey: String,
        customHues: Map<String, Int> = emptyMap(),
    ): Int {
        val key = subjectKey.trim()
        if (key.isEmpty()) return 215
        customHues[key]?.let { return it }
        val canonical = SubjectMapper.canonicalKey(key)
        if (canonical != null) {
            customHues[canonical]?.let { return it }
            return SubjectMapper.defaultColorHue(canonical)
        }
        return 215
    }
}
