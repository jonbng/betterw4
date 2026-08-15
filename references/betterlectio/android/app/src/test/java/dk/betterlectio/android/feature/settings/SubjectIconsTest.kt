package dk.betterlectio.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SubjectIconsTest {

    @Test
    fun resolvesDanishCodes() {
        assertEquals("ma", SubjectIcons.canonicalKeyFor("Ma A"))
        assertEquals("da", SubjectIcons.canonicalKeyFor("Dansk"))
        assertEquals("en", SubjectIcons.canonicalKeyFor("1x En B"))
        assertEquals("fy", SubjectIcons.canonicalKeyFor("fy"))
        assertEquals("functions", SubjectIcons.iconKeyFor("ma"))
        assertEquals("book", SubjectIcons.iconKeyFor("da"))
        assertEquals("translate", SubjectIcons.iconKeyFor("en"))
        assertEquals("science", SubjectIcons.iconKeyFor("fy"))
    }

    @Test
    fun resolvesAliasesAndHoldPrefixes() {
        assertEquals("bi", SubjectIcons.canonicalKeyFor("2a Biologi A"))
        assertEquals("hi", SubjectIcons.canonicalKeyFor("Historie"))
        assertEquals("id", SubjectIcons.canonicalKeyFor("Idræt"))
        assertNotNull(SubjectIcons.resolve("Matematik"))
    }

    @Test
    fun unknownFallsBackToSchoolIcon() {
        assertEquals("school", SubjectIcons.iconKeyFor("Ukendt Fag XYZ"))
        assertTrue(SubjectIcons.canonicalKeyFor("Ukendt Fag XYZ") == null)
    }
}
