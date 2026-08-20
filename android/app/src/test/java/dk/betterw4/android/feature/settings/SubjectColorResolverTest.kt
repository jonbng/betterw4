package dk.betterw4.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SubjectColorResolverTest {

    @Test
    fun custom_map_wins() {
        val custom = mapOf("mathematics" to 0xFF112233L)
        val color = SubjectColorResolver.resolve("1DA13HMTAA", custom)
        assertEquals(0xFF112233L, color)
    }

    @Test
    fun known_subjects_get_stable_hues() {
        val a = SubjectColorResolver.resolve("Mathematics", emptyMap())
        val b = SubjectColorResolver.resolve("Economics", emptyMap())
        assertNotEquals(a, b)
        assertEquals(a, SubjectColorResolver.resolve("1DA13HMTAA", emptyMap()))
        assertEquals(b, SubjectColorResolver.resolve("ECOX", emptyMap()))
    }

    @Test
    fun empty_key_uses_palette_first() {
        assertEquals(
            SettingsStore.DEFAULT_PALETTE.first(),
            SubjectColorResolver.resolve("  ", emptyMap()),
        )
    }

    @Test
    fun swatch_yellow_is_too_light_on_white() {
        val yellow = SubjectColorResolver.hueToArgb(60)
        assertTrue(
            SubjectColorResolver.contrastRatio(yellow, SubjectColorResolver.WHITE_ARGB) < 4.5f,
        )
    }

    @Test
    fun readable_yellow_meets_wcag_on_white() {
        val yellow = SubjectColorResolver.hueToArgb(60)
        val readable = SubjectColorResolver.ensureContrast(yellow)
        assertTrue(
            SubjectColorResolver.contrastRatio(readable, SubjectColorResolver.WHITE_ARGB) >= 4.5f,
        )
        // Hue is preserved so the subject still reads as yellow/gold, not gray.
        val originalHue = SubjectColorResolver.argbToHue(yellow)
        val readableHue = SubjectColorResolver.argbToHue(readable)
        assertTrue(kotlin.math.abs(originalHue - readableHue) <= 2)
    }

    @Test
    fun every_mapped_hue_is_readable_on_white() {
        for (hue in 0 until 360 step 8) {
            val swatch = SubjectColorResolver.hueToArgb(hue)
            val readable = SubjectColorResolver.ensureContrast(swatch)
            assertTrue(
                "hue $hue contrast was ${SubjectColorResolver.contrastRatio(readable, SubjectColorResolver.WHITE_ARGB)}",
                SubjectColorResolver.contrastRatio(readable, SubjectColorResolver.WHITE_ARGB) >= 4.5f,
            )
        }
    }

    @Test
    fun already_dark_blue_is_unchanged_on_white() {
        val navy = SubjectColorResolver.hsvToArgb(215, 0.80f, 0.45f)
        assertEquals(navy, SubjectColorResolver.ensureContrast(navy))
    }
}
