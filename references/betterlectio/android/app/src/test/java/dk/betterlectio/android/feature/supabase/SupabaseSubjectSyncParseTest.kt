package dk.betterlectio.android.feature.supabase

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SupabaseSubjectSyncParseTest {
    @Test
    fun subject_mapping_model_holds_fields() {
        val m = SupabaseSubjectSync.SubjectMapping(
            subjectKey = "Ma A",
            displayName = "Matematik",
            colorArgb = 0xFF3362E1L,
            mappingId = "abc",
        )
        assertEquals("Ma A", m.subjectKey)
        assertEquals("Matematik", m.displayName)
        assertEquals(0xFF3362E1L, m.colorArgb)
        assertEquals("abc", m.mappingId)
    }

    @Test
    fun hue_to_argb_is_opaque() {
        val argb = SupabaseSubjectService.hueToArgb(120)
        assertEquals(0xFFL, (argb ushr 24) and 0xFF)
    }

    @Test
    fun default_url_matches_ios_project() {
        assertTrue(SupabaseConfig.DEFAULT_URL.contains("supabase.co"))
    }
}
