package dk.betterlectio.android.feature.grades

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GradeParserTest {

    private fun fixture(): GradesReport {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/grades_table.html")!!
            .bufferedReader().readText()
        return GradeParser.parse(html)
    }

    @Test
    fun parses_dynamic_columns_including_afsluttende() {
        val report = fixture()
        val keys = report.columns.map { it.key }
        assertEquals(
            listOf(
                "1.standpunkt",
                "2.standpunkt",
                "intern prøve",
                "afsluttende",
                "årskarakter",
                "eksamenskarakter",
            ),
            keys,
        )
    }

    @Test
    fun does_not_shift_year_and_exam_when_afsluttende_present() {
        val report = fixture()
        val ap = report.grades.first { it.subject.contains("Almen sprogforståelse") }

        // Intern at column 4, not year/exam
        assertEquals("12", ap.cell("intern prøve")?.value)
        assertEquals(0.25, ap.cell("intern prøve")?.weight!!, 0.001)

        // Årskarakter and eksamen stay in their labeled columns
        assertEquals("10", ap.cell("årskarakter")?.value)
        assertEquals("7", ap.cell("eksamenskarakter")?.value)

        // Afsluttende empty for this row
        assertNull(ap.cell("afsluttende"))
    }

    @Test
    fun parses_first_standpoint_weights_and_skriftlig_label() {
        val report = fixture()
        val ma = report.grades.first { it.subject.contains("Matematik") }
        assertEquals("1x MA", ma.team)
        assertEquals("HE1", ma.teamId)
        assertEquals("10", ma.cell("1.standpunkt")?.value)
        assertEquals(1.0, ma.cell("1.standpunkt")?.weight!!, 0.001)
        assertEquals("12", ma.cell("2.standpunkt")?.value)
        assertTrue(ma.subject.contains("Skriftlig"))
    }

    @Test
    fun ignores_mobile_duplicate_cells() {
        val report = fixture()
        // Three data rows, not doubled by mobile markup
        assertEquals(3, report.grades.size)
    }

    @Test
    fun parses_alerts_and_structured_notes() {
        val report = fixture()
        assertEquals(1, report.alerts.size)
        assertTrue(report.alerts[0].contains("Sommer 2026"))

        assertEquals(1, report.notes.size)
        val note = report.notes[0]
        assertEquals("1x MA", note.hold)
        assertEquals("10", note.grade)
        assertEquals("God indsats til terminsprøve", note.note)
        assertTrue(note.gradeType.contains("standpunkt"))
    }

    @Test
    fun canonicalColumnKey_order_matters_for_afsluttende_and_eksamen() {
        assertEquals("afsluttende", GradeParser.canonicalColumnKey("Afsluttende års-/standpunktskarakter"))
        assertEquals("eksamenskarakter", GradeParser.canonicalColumnKey("Eksamens-/årsprøvekarakter"))
        assertEquals("årskarakter", GradeParser.canonicalColumnKey("Årskarakter"))
        assertEquals("intern prøve", GradeParser.canonicalColumnKey("Intern prøve"))
        assertEquals("1.standpunkt", GradeParser.canonicalColumnKey("1.standpunkt"))
        assertEquals("2.standpunkt", GradeParser.canonicalColumnKey("2. standpunkt"))
        assertEquals("3.standpunkt", GradeParser.canonicalColumnKey("3.standpunkt"))
    }
}
