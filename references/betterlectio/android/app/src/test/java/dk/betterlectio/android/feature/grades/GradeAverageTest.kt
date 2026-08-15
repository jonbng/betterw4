package dk.betterlectio.android.feature.grades

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GradeAverageTest {

    private fun cell(value: String, weight: Double? = null) =
        GradeCellValue(value = value, weight = weight)

    private fun row(
        subject: String,
        grades: Map<String, GradeCellValue>,
        team: String = "1x",
    ) = GradeRow(team = team, subject = subject, grades = grades)

    @Test
    fun weightedAverage_firstStandpoint_usesWeights() {
        val rows = listOf(
            row("Ma", mapOf("1.standpunkt" to cell("10", 2.0))),
            row("Da", mapOf("1.standpunkt" to cell("7", 1.0))),
        )
        // (10*2 + 7*1) / 3 = 9.0
        assertEquals(9.0, GradeAverage.weightedAverage(rows, "1.standpunkt")!!, 0.001)
        assertEquals("9,00", GradeAverage.weightedAverageDisplay(rows, "1.standpunkt"))
    }

    @Test
    fun weightedAverage_fractionalWeights() {
        val rows = listOf(
            row("Ap", mapOf("intern prøve" to cell("12", 0.25))),
            row("Nv", mapOf("intern prøve" to cell("12", 0.25))),
            row("Ma", mapOf("intern prøve" to cell("4", 1.0))),
        )
        // (12*0.25 + 12*0.25 + 4*1) / 1.5 = 10.0 / 1.5 ≈ 6.666...
        val avg = GradeAverage.weightedAverage(rows, "intern prøve")!!
        assertEquals(6.666, avg, 0.01)
    }

    @Test
    fun missingWeight_defaultsToOne() {
        val rows = listOf(
            row("Ma", mapOf("1.standpunkt" to cell("10"))),
            row("Da", mapOf("1.standpunkt" to cell("4"))),
        )
        assertEquals(7.0, GradeAverage.weightedAverage(rows, "1.standpunkt")!!, 0.001)
    }

    @Test
    fun columnAverages_neverMixesTypes() {
        val rows = listOf(
            row(
                "Ma",
                mapOf(
                    "1.standpunkt" to cell("10", 1.0),
                    "eksamenskarakter" to cell("4", 1.0),
                ),
            ),
            row("Da", mapOf("1.standpunkt" to cell("7", 1.0))),
        )
        val columns = listOf(
            GradeColumn("1.standpunkt", "1.standpunkt"),
            GradeColumn("eksamenskarakter", "Eksamenskarakter"),
        )
        val avgs = GradeAverage.columnAverages(rows, columns)
        assertEquals(2, avgs.size)
        // 1.SP: (10+7)/2 = 8.50 — NOT mixed with exam 4
        assertEquals("8,50", avgs.first { it.first.key == "1.standpunkt" }.second)
        // Exam: only 4
        assertEquals("4,00", avgs.first { it.first.key == "eksamenskarakter" }.second)
    }

    @Test
    fun gradeToNumber_onlySevenStep() {
        assertEquals(12.0, GradeAverage.gradeToNumber("12")!!, 0.001)
        assertEquals(2.0, GradeAverage.gradeToNumber("02")!!, 0.001)
        assertEquals(0.0, GradeAverage.gradeToNumber("00")!!, 0.001)
        assertEquals(-3.0, GradeAverage.gradeToNumber("-3")!!, 0.001)
        assertEquals(10.0, GradeAverage.gradeToNumber("10*")!!, 0.001)
        assertNull(GradeAverage.gradeToNumber("B"))
        assertNull(GradeAverage.gradeToNumber("—"))
        assertNull(GradeAverage.gradeToNumber(""))
        assertNull(GradeAverage.gradeToNumber("8")) // not on 7-step scale
    }

    @Test
    fun nonScaleGrades_excludedFromAverage() {
        val rows = listOf(
            row("Ma", mapOf("1.standpunkt" to cell("10"))),
            row("Ib", mapOf("1.standpunkt" to cell("B"))),
        )
        assertEquals(10.0, GradeAverage.weightedAverage(rows, "1.standpunkt")!!, 0.001)
    }

    @Test
    fun filterRows_onlyIncludesRowsWithSelectedColumn() {
        val rows = listOf(
            row("Ma", mapOf("1.standpunkt" to cell("10"))),
            row("Da", mapOf("eksamenskarakter" to cell("7"))),
            row("En", mapOf("1.standpunkt" to cell("4"), "eksamenskarakter" to cell("10"))),
        )
        val firstOnly = GradeAverage.filterRows(rows, "1.standpunkt")
        assertEquals(2, firstOnly.size)
        assertTrue(firstOnly.any { it.subject == "Ma" })
        assertTrue(firstOnly.any { it.subject == "En" })

        val examOnly = GradeAverage.filterRows(rows, "eksamenskarakter")
        assertEquals(2, examOnly.size)
    }

    @Test
    fun displaySubject_shortensSkriftligMundtlig() {
        assertEquals("Dansk A (M)", GradeAverage.displaySubject("Dansk A, Mundtlig"))
        assertEquals("Tysk B (S)", GradeAverage.displaySubject("Tysk B, Skriftlig"))
        assertEquals("Matematik A", GradeAverage.displaySubject("Matematik A"))
    }

    @Test
    fun progressForGrade_mapsSevenStepToUnitInterval() {
        assertEquals(0f, GradeAverage.progressForGrade("-3")!!, 0.001f)
        assertEquals(1f, GradeAverage.progressForGrade("12")!!, 0.001f)
        assertNull(GradeAverage.progressForGrade("B"))
    }

    @Test
    fun defaultColumnKey_prefersFirstStandpunktWithData() {
        val columns = listOf(
            GradeColumn("1.standpunkt", "1.standpunkt"),
            GradeColumn("eksamenskarakter", "Eksamen"),
        )
        val rows = listOf(row("Ma", mapOf("eksamenskarakter" to cell("7"))))
        // 1.SP exists but has no data → fall through to exam
        assertEquals("eksamenskarakter", GradeAverage.defaultColumnKey(columns, rows))

        val rows2 = listOf(row("Ma", mapOf("1.standpunkt" to cell("10"))))
        assertEquals("1.standpunkt", GradeAverage.defaultColumnKey(columns, rows2))
    }

    @Test
    fun notesForHold_filtersByTeam() {
        val notes = listOf(
            GradeNoteEntry("1x MA", "1.SP", "10", "1/1", "ok"),
            GradeNoteEntry("1x DA", "1.SP", "7", "1/1", "meh"),
        )
        assertEquals(1, GradeAverage.notesForHold(notes, "1x MA").size)
        assertEquals("ok", GradeAverage.notesForHold(notes, "1x MA").first().note)
    }
}
