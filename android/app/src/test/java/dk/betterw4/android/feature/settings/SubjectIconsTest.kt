package dk.betterw4.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SubjectIconsTest {

    @Test
    fun resolvesIbTitlesAndW4Codes() {
        assertEquals("mathematics", SubjectIcons.canonicalKeyFor("Mathematics HL"))
        assertEquals("mathematics", SubjectIcons.canonicalKeyFor("1DA13HMTAA"))
        assertEquals("economics", SubjectIcons.canonicalKeyFor("ECOX"))
        assertEquals("english-a", SubjectIcons.canonicalKeyFor("LALI"))
        assertEquals("danish-a", SubjectIcons.canonicalKeyFor("Danish Literature"))
        assertEquals("spanish-a", SubjectIcons.canonicalKeyFor("SPLI"))
        assertEquals("world-literature", SubjectIcons.canonicalKeyFor("WOLX"))
        assertEquals("tok", SubjectIcons.canonicalKeyFor("THOK"))
        assertEquals("global-politics", SubjectIcons.canonicalKeyFor("GLOP"))
        assertEquals("functions", SubjectIcons.iconKeyFor("MTAA"))
        assertEquals("chart", SubjectIcons.iconKeyFor("Economics"))
        assertEquals("science", SubjectIcons.iconKeyFor("Physics"))
        assertNotNull(SubjectIcons.resolve("1EA16CECOX"))
    }

    @Test
    fun furnitureFallsBackToSchoolIcon() {
        assertEquals("school", SubjectIcons.iconKeyFor("Breakfast"))
        assertTrue(SubjectIcons.canonicalKeyFor("Breakfast") == null)
    }
}
