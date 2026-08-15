package dk.betterw4.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class W4AssessmentParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/assessments-calendar.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_class_and_student_items() {
        val items = W4AssessmentParser.parse(html)
        assertEquals(2, items.size)
        val lab = items.first { it.activityTitle == "Lab report" }
        assertEquals("class:42", lab.id)
        assertFalse(lab.done)
        assertEquals("Biology", lab.team)
        assertEquals("Jane Doe", lab.teacher)
        assertEquals(LocalDate.of(2026, 8, 10), lab.date)

        val essay = items.first { it.activityTitle == "My essay" }
        assertEquals("student:99", essay.id)
        assertTrue(essay.done)
    }

    @Test
    fun ajax_urls_and_status_fields() {
        val urls = W4AssessmentParser.parseAjaxUrls(html)!!
        assertTrue(urls.confirm.contains("academics/deadlines/confirm"))
        assertTrue(urls.create.contains("academics/deadlines/create"))
        val classFields = W4AssessmentParser.fieldsForStatus(
            HomeworkItem(id = "class:42", note = "", activityTitle = "Lab", date = null, href = "class"),
        )
        assertEquals("42", classFields["assessment_id"])
        val studentFields = W4AssessmentParser.fieldsForStatus(
            HomeworkItem(id = "student:99", note = "", activityTitle = "Essay", date = null, href = "student"),
        )
        assertEquals("99", studentFields["student_assessment_id"])
    }
}
