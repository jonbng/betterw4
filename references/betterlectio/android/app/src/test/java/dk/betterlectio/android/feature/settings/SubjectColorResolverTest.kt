package dk.betterlectio.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class SubjectColorResolverTest {

    @Test
    fun custom_map_wins() {
        val custom = mapOf("ma" to 0xFF112233L)
        val color = SubjectColorResolver.resolve("1x MA", custom)
        assertEquals(0xFF112233L, color)
    }

    @Test
    fun known_subjects_get_stable_hues() {
        val a = SubjectColorResolver.resolve("Matematik", emptyMap())
        val b = SubjectColorResolver.resolve("Dansk", emptyMap())
        assertNotEquals(a, b)
        assertEquals(a, SubjectColorResolver.resolve("1x MA", emptyMap()))
        assertEquals(b, SubjectColorResolver.resolve("da", emptyMap()))
    }

    @Test
    fun empty_key_uses_palette_first() {
        assertEquals(
            SettingsStore.DEFAULT_PALETTE.first(),
            SubjectColorResolver.resolve("  ", emptyMap()),
        )
    }
}
