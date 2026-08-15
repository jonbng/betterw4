package dk.betterlectio.android.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun canonicalKey_mathematicsVariants() {
        assertEquals("ma", SubjectMapper.canonicalKey("1x MA"))
        assertEquals("ma", SubjectMapper.canonicalKey("2x MA"))
        assertEquals("ma", SubjectMapper.canonicalKey("2.4 MA"))
        assertEquals("ma", SubjectMapper.canonicalKey("L2d MA"))
        assertEquals("ma", SubjectMapper.canonicalKey("Matematik"))
        assertEquals("ma", SubjectMapper.canonicalKey("MA"))
        assertEquals("ma", SubjectMapper.canonicalKey("ma"))
        assertEquals("ma", SubjectMapper.canonicalKey("mat"))
        assertEquals("ma", SubjectMapper.canonicalKey("Ma A"))
        assertEquals("ma", SubjectMapper.canonicalKey("MA-A"))
    }

    @Test
    fun canonicalKey_specialProjectsAndKlassensTime() {
        assertEquals("srp", SubjectMapper.canonicalKey("SRP"))
        assertEquals("sro", SubjectMapper.canonicalKey("SRO"))
        assertEquals("dho", SubjectMapper.canonicalKey("DHO"))
        assertEquals("kt", SubjectMapper.canonicalKey("KT"))
        assertEquals("kt", SubjectMapper.canonicalKey("Klassens Time"))
    }

    @Test
    fun canonicalKey_namedAndHyphenatedClassPrefixes() {
        assertEquals("da", SubjectMapper.canonicalKey("BShannon DA"))
        assertEquals("pu", SubjectMapper.canonicalKey("BShannon PU"))
        assertEquals("ma", SubjectMapper.canonicalKey("BHamilton MA"))
        assertEquals("da", SubjectMapper.canonicalKey("Epsilon DA"))
        assertEquals("da", SubjectMapper.canonicalKey("3hx-u DA"))
        assertEquals("en", SubjectMapper.canonicalKey("IB1 En B"))
    }

    @Test
    fun canonicalKey_unknownAndIgnored() {
        assertNull(SubjectMapper.canonicalKey("Ukendt Fag XYZ"))
        assertNull(SubjectMapper.canonicalKey(""))
        assertNull(SubjectMapper.canonicalKey("   "))
        assertNull(SubjectMapper.canonicalKey("Kor"))
        assertNull(SubjectMapper.canonicalKey("Elevråd"))
        assertNull(SubjectMapper.canonicalKey("Kostelever"))
    }

    @Test
    fun displayName_usesBuiltInDefaultWithoutProvider() {
        assertEquals("Matematik", SubjectMapper.displayName("1x MA"))
        assertEquals("Dansk", SubjectMapper.displayName("da"))
        assertEquals("Ukendt Fag XYZ", SubjectMapper.displayName("Ukendt Fag XYZ"))
    }

    @Test
    fun displayName_usesProviderOverride() {
        SubjectMapper.mappingProvider = { key ->
            if (key == "ma") {
                ResolvedLessonMapping(
                    mappingId = "id-ma",
                    canonicalKey = "ma",
                    defaultName = "Matematik",
                    defaultColorHue = 238,
                    displayName = "Maths ✨",
                    displayColorHue = 10,
                )
            } else {
                null
            }
        }
        assertEquals("Maths ✨", SubjectMapper.displayName("1x MA"))
        assertEquals("Maths ✨", SubjectMapper.displayName("2.4 MA"))
        assertEquals(10, SubjectMapper.colorHue("L2d MA"))
    }

    @Test
    fun colorHue_defaultsPerSubject() {
        assertEquals(238, SubjectMapper.colorHue("ma"))
        assertEquals(342, SubjectMapper.colorHue("Dansk"))
        assertEquals(215, SubjectMapper.colorHue("Ukendt"))
    }

    @Test
    fun iconKey_knownAndUnknown() {
        assertEquals("functions", SubjectMapper.iconKey("ma"))
        assertEquals("book", SubjectMapper.iconKey("da"))
        assertEquals("translate", SubjectMapper.iconKey("en"))
        assertEquals("science", SubjectMapper.iconKey("fy"))
        assertEquals("school", SubjectMapper.iconKey("Ukendt Fag XYZ"))
    }

    @Test
    fun isKnownSubject() {
        assertTrue(SubjectMapper.isKnownSubject("1x MA"))
        assertTrue(SubjectMapper.isKnownSubject("Historie"))
        assertFalse(SubjectMapper.isKnownSubject("Ukendt Fag XYZ"))
        assertFalse(SubjectMapper.isKnownSubject("Kor"))
    }

    @Test
    fun allSubjects_includesEventTitles() {
        val subjects = SubjectMapper.allSubjects(including = listOf("1x MA", "2a Biologi", "Ukendt"))
        val codes = subjects.map { it.code }.toSet()
        assertTrue(codes.contains("ma"))
        assertTrue(codes.contains("bi"))
        assertFalse(codes.contains("ukendt"))
    }
}
