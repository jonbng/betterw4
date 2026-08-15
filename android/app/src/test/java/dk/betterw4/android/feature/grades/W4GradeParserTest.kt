package dk.betterw4.android.feature.grades

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class W4GradeParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/grades.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_ib_grade_table() {
        val report = W4GradeParser.parse(html)
        assertEquals(listOf("predicted", "final"), report.columns.map { it.key })
        assertEquals(3, report.grades.size)
        val math = report.grades[0]
        assertEquals("Mathematics HL", math.subject)
        assertEquals("A. Newton", math.team)
        assertEquals("6", math.cell("predicted")?.value)
        assertEquals("6", math.cell("final")?.value)
        val bio = report.grades[2]
        assertEquals("Biology SL", bio.subject)
        assertEquals("5", bio.cell("predicted")?.value)
        assertNull(bio.cell("final"))
        assertTrue(GradeAverage.looksLikeIb(report.columns, report.grades))
        assertEquals("6,00", GradeAverage.weightedAverageDisplay(report.grades, "predicted"))
    }

    @Test
    fun skips_empty_results_table() {
        val empty = """
            <div id="content_inner">
              <table class="items">
                <thead><tr><th>Subject</th><th>Predicted</th></tr></thead>
                <tbody><tr><td colspan="2" class="empty">No results found.</td></tr></tbody>
              </table>
            </div>
        """.trimIndent()
        val report = W4GradeParser.parse(empty)
        assertEquals(1, report.columns.size)
        assertTrue(report.grades.isEmpty())
    }
}
