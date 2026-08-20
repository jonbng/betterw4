package dk.betterw4.android.feature.homework

import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.schedule.EventStatus
import org.jsoup.Jsoup
import java.time.LocalDate

data class W4AssessmentAjax(
    val confirm: String,
    val revert: String,
    val save: String,
    val create: String,
    val delete: String,
)

/**
 * Student assessments calendar (`academics/deadlines`).
 *
 * Class-assigned items: `a.assessment-link[data-assessment-type!=student]`.
 * Student-created items: `data-assessment-type=student`.
 */
object W4AssessmentParser {
    private val AJAX = Regex(
        """(confirm|revert|save|create|delete)\s*:\s*['"]([^'"]+)['"]""",
    )

    fun parse(html: String): List<HomeworkItem> {
        val doc = Jsoup.parse(html)
        return doc.select("a.assessment-link").mapNotNull { link ->
            val id = link.attr("data-assessment-id").ifBlank { return@mapNotNull null }
            val kind = link.attr("data-assessment-type").ifBlank { "class" }
            val status = link.attr("data-status").ifBlank { "pending" }
            val date = W4Dates.parse(link.attr("data-assessment-date"))
                ?: dayHeaderDate(link, html)
            val subject = link.attr("data-subject-name")
            val teacher = link.attr("data-teacher-name").ifBlank { null }
            val unit = link.attr("data-unit")
            val daysLeft = link.attr("data-days-left")
            val title = link.text().trim().ifBlank { unit.ifBlank { "Assessment" } }
            val note = listOfNotNull(
                subject.takeIf { it.isNotBlank() },
                teacher,
                unit.takeIf { it.isNotBlank() },
                daysLeft.takeIf { it.isNotBlank() }?.let { "$it days left" },
            ).joinToString(" · ")
            val overdue = link.hasClass("overdue") ||
                link.classNames().any { it.contains("overdue", ignoreCase = true) } ||
                link.attr("data-css-class").contains("overdue", ignoreCase = true)
            HomeworkItem(
                id = "$kind:$id",
                note = note,
                activityTitle = title,
                date = date,
                team = subject,
                teacher = teacher,
                status = if (overdue) EventStatus.CHANGED else EventStatus.NORMAL,
                done = !status.equals("pending", ignoreCase = true),
                href = kind,
            )
        }
    }

    fun parseAjaxUrls(html: String): W4AssessmentAjax? {
        val found = AJAX.findAll(html).associate { it.groupValues[1] to it.groupValues[2] }
        val confirm = found["confirm"] ?: return null
        return W4AssessmentAjax(
            confirm = confirm,
            revert = found["revert"].orEmpty(),
            save = found["save"].orEmpty(),
            create = found["create"].orEmpty(),
            delete = found["delete"].orEmpty(),
        )
    }

    fun fieldsForStatus(item: HomeworkItem): Map<String, String> {
        val rawId = item.id.substringAfter(":", item.id)
        return if (item.href == "student" || item.id.startsWith("student:")) {
            mapOf("student_assessment_id" to rawId)
        } else {
            mapOf("assessment_id" to rawId)
        }
    }

    private fun dayHeaderDate(link: org.jsoup.nodes.Element, html: String): LocalDate? {
        val day = link.parents()
            .firstOrNull { it.hasClass("day") }
            ?.selectFirst(".day-header")
            ?.text()
            ?.trim()
            ?.toIntOrNull()
            ?: return null
        val monthYear = monthAndYear(html) ?: return null
        return runCatching { LocalDate.of(monthYear.second, monthYear.first, day) }.getOrNull()
    }

    /**
     * Bug B11: `month=(\d+)` never matched `var month = 08 - 1;`.
     * Prefer the script form (1-based month, `- 1` is for JS Date), then query keys.
     */
    internal fun monthAndYear(html: String): Pair<Int, Int>? {
        val month = parsedMonth(html) ?: return null
        val year = parsedYear(html) ?: return null
        return month to year
    }

    private fun parsedMonth(source: String): Int? {
        MONTH_SCRIPT.find(source)?.groupValues?.get(1)?.toIntOrNull()
            ?.takeIf { it in 1..12 }
            ?.let { return it }
        MONTH_QUERY.find(source)?.groupValues?.get(1)?.toIntOrNull()
            ?.takeIf { it in 1..12 }
            ?.let { return it }
        return MONTH_BARE.find(source)?.groupValues?.get(1)?.toIntOrNull()?.takeIf { it in 1..12 }
    }

    private fun parsedYear(source: String): Int? =
        YEAR_SCRIPT.find(source)?.groupValues?.get(1)?.toIntOrNull()?.takeIf { it in 1900..2200 }
            ?: YEAR_QUERY.find(source)?.groupValues?.get(1)?.toIntOrNull()?.takeIf { it in 1900..2200 }

    private val MONTH_SCRIPT = Regex("""\bmonth\s*=\s*(\d{1,2})\s*-\s*1\b""")
    private val MONTH_QUERY = Regex("""[?&]month=(\d{1,2})""")
    private val MONTH_BARE = Regex("""\bmonth\s*=\s*(\d{1,2})""")
    private val YEAR_SCRIPT = Regex("""\byear\s*=\s*(\d{4})""")
    private val YEAR_QUERY = Regex("""[?&]year=(\d{4})""")
}
