package dk.betterw4.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SubjectMapperTest {

    @Before
    fun clearProviders() {
        SubjectMapper.mappingProvider = null
        SubjectMapper.subjectInfoProvider = null
    }

    @Test
    fun canonicalKey_ibTitlesAndW4ClassIds() {
        assertEquals("mathematics", SubjectMapper.canonicalKey("Mathematics HL"))
        assertEquals("mathematics", SubjectMapper.canonicalKey("Mathematics Analysis and Approaches"))
        assertEquals("mathematics", SubjectMapper.canonicalKey("1DA13HMTAA"))
        assertEquals("mathematics", SubjectMapper.canonicalKey("MTAA"))
        assertEquals("economics", SubjectMapper.canonicalKey("Economics"))
        assertEquals("economics", SubjectMapper.canonicalKey("1EA16CECOX"))
        assertEquals("english-a", SubjectMapper.canonicalKey("English Language & Literature"))
        assertEquals("english-a", SubjectMapper.canonicalKey("1YA25SLALI"))
        assertEquals("danish-a", SubjectMapper.canonicalKey("Danish Literature"))
        assertEquals("danish-a", SubjectMapper.canonicalKey("2AA24CDALI"))
        assertEquals("philosophy", SubjectMapper.canonicalKey("1CA24CPHIX"))
        assertEquals("physics", SubjectMapper.canonicalKey("1BE12CPHYX"))
        assertEquals("core-meetings", SubjectMapper.canonicalKey("1ZAUDXCORE"))
        assertEquals("tok", SubjectMapper.canonicalKey("TOK"))
        assertEquals("tok", SubjectMapper.canonicalKey("2DA14XTHOK"))
        assertEquals("global-politics", SubjectMapper.canonicalKey("1AK21CGLOP"))
        assertEquals("norwegian-a", SubjectMapper.canonicalKey("1AA26CNOLI"))
        assertEquals("spanish-a", SubjectMapper.canonicalKey("1AA13CSPLI"))
        assertEquals("spanish", SubjectMapper.canonicalKey("1XA12SSPAB"))
        assertEquals("spanish", SubjectMapper.canonicalKey("2XA26CSPBB"))
        assertEquals("french", SubjectMapper.canonicalKey("1XA24SFRAB"))
        assertEquals("english-b", SubjectMapper.canonicalKey("1DA21HENGB"))
        assertEquals("environmental-systems-and-societies", SubjectMapper.canonicalKey("1EE15CENSS"))
        assertEquals("theatre", SubjectMapper.canonicalKey("1CMUSCTHEX"))
        assertEquals("visual-arts", SubjectMapper.canonicalKey("1CA22CVART"))
        assertEquals("world-literature", SubjectMapper.canonicalKey("2YA25SWOLX"))
        assertEquals("psychology", SubjectMapper.canonicalKey("1BA24CPSYC"))
        assertEquals("history", SubjectMapper.canonicalKey("1DK11CHIST"))
        assertEquals("mathematics", SubjectMapper.canonicalKey("1EA11SMTAI"))
    }

    @Test
    fun canonicalKey_levelSuffixesCollapse() {
        assertEquals("mathematics", SubjectMapper.canonicalKey("Mathematics SL"))
        assertEquals("biology", SubjectMapper.canonicalKey("DP1 Biology HL"))
        assertEquals("english-a", SubjectMapper.canonicalKey("English A: Language and Literature HL"))
        assertEquals("english-b", SubjectMapper.canonicalKey("English B SL"))
    }

    @Test
    fun canonicalKey_furnitureIsIgnored() {
        assertNull(SubjectMapper.canonicalKey(""))
        assertNull(SubjectMapper.canonicalKey("   "))
        assertNull(SubjectMapper.canonicalKey("Breakfast"))
        assertNull(SubjectMapper.canonicalKey("Break"))
        assertNull(SubjectMapper.canonicalKey("Lunch"))
        assertNull(SubjectMapper.canonicalKey("Weekend"))
        assertNull(SubjectMapper.canonicalKey("House cleaning"))
    }

    @Test
    fun displayName_usesW4NamesAndOverrides() {
        assertEquals("Mathematics", SubjectMapper.displayName("1DA13HMTAA"))
        assertEquals("Economics", SubjectMapper.displayName("1EA16CECOX"))
        assertEquals("Danish Literature", SubjectMapper.displayName("2AA24CDALI"))
        assertEquals("Core meetings", SubjectMapper.displayName("CORE"))

        SubjectMapper.mappingProvider = { key ->
            if (key == "economics") {
                ResolvedLessonMapping(
                    mappingId = "id-econ",
                    canonicalKey = "economics",
                    defaultName = "Economics",
                    defaultColorHue = 54,
                    displayName = "Econ ✨",
                    displayColorHue = 10,
                )
            } else {
                null
            }
        }
        assertEquals("Econ ✨", SubjectMapper.displayName("1EA16CECOX"))
        assertEquals("Econ ✨", SubjectMapper.displayName("Economics"))
        assertEquals(10, SubjectMapper.colorHue("ECOX"))
    }

    @Test
    fun colorHue_knownSubjectsAreStableAndDistinct() {
        assertEquals(238, SubjectMapper.colorHue("mathematics"))
        assertEquals(54, SubjectMapper.colorHue("economics"))
        assertNotEquals(
            SubjectMapper.colorHue("1DA13HMTAA"),
            SubjectMapper.colorHue("1EA16CECOX"),
        )
        assertEquals(
            SubjectMapper.colorHue("Mathematics HL"),
            SubjectMapper.colorHue("1DA13HMTAA"),
        )
    }

    @Test
    fun unknownSubjectKeepsNameAndStableHue() {
        val title = "Underwater Basket Weaving HL"
        assertFalse(SubjectMapper.isKnownSubject(title))
        assertEquals(title, SubjectMapper.displayName(title))
        assertEquals("underwater basket weaving", SubjectMapper.canonicalKey(title))
        val first = SubjectMapper.colorHue(title)
        assertEquals(first, SubjectMapper.colorHue("Underwater Basket Weaving SL"))
        assertEquals(first, SubjectMapper.stableHue("underwater basket weaving"))
    }

    @Test
    fun allSubjects_includesEventTitles() {
        val subjects = SubjectMapper.allSubjects(
            including = listOf("1EA16CECOX", "Danish Literature", "Underwater Basket Weaving HL"),
        )
        val codes = subjects.map { it.code }.toSet()
        assertTrue(codes.contains("economics"))
        assertTrue(codes.contains("danish-a"))
        assertTrue(codes.contains("underwater basket weaving"))
    }

    @Test
    fun isKnownSubject() {
        assertTrue(SubjectMapper.isKnownSubject("1DA13HMTAA"))
        assertTrue(SubjectMapper.isKnownSubject("Economics"))
        assertFalse(SubjectMapper.isKnownSubject("Breakfast"))
        assertFalse(SubjectMapper.isKnownSubject("Underwater Basket Weaving HL"))
    }
}
