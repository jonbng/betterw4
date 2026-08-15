package dk.betterw4.android.feature.grades

import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Defensive parser for `academics/grades/grades` (Yii `table.items`).
 *
 * No captured live HTML — maps the first content table: a name-like column
 * becomes the subject, optional teacher/level columns become [GradeRow.team],
 * remaining cells are grade values keyed by the header slug.
 */
object W4GradeParser {

    private val SUBJECT_HEADERS = listOf("subject", "course", "class", "name")
    private val TEACHER_HEADERS = listOf("teacher", "staff", "instructor")
    private val LEVEL_HEADERS = listOf("level", "hl/sl", "hl sl", "group")
    private val SKIP_HEADERS = listOf("actions", "action", "")

    fun parse(html: String): GradesReport {
        val doc = Jsoup.parse(html)
        val inner = doc.getElementById("content_inner") ?: doc.body()
        val table = inner.selectFirst("table.items") ?: inner.selectFirst("table")
            ?: return GradesReport(columns = emptyList(), grades = emptyList())
        val alerts = parseAlerts(doc)
        return parseTable(table, alerts)
    }

    internal fun parseTable(table: Element, alerts: List<String> = emptyList()): GradesReport {
        val headers = headerLabels(table)
        if (headers.isEmpty()) {
            return GradesReport(columns = emptyList(), grades = emptyList(), alerts = alerts)
        }
        val subjectIdx = indexOf(headers, SUBJECT_HEADERS) ?: 0
        val teacherIdx = indexOf(headers, TEACHER_HEADERS)
        val levelIdx = indexOf(headers, LEVEL_HEADERS)
        val identity = setOfNotNull(subjectIdx, teacherIdx, levelIdx)
        val gradeCols = headers.mapIndexedNotNull { index, label ->
            if (index in identity) return@mapIndexedNotNull null
            if (label.isBlank() || SKIP_HEADERS.contains(label.lowercase())) return@mapIndexedNotNull null
            GradeColumn(key = slug(label).ifBlank { "col-$index" }, label = label)
                .let { index to it }
        }
        val columns = gradeCols.map { it.second }

        val rows = bodyRows(table).mapNotNull { tr ->
            if (tr.selectFirst("td.empty") != null) return@mapNotNull null
            val cells = tr.select("td").map { it.text().trim() }
            if (cells.isEmpty() || cells.all { it.isBlank() }) return@mapNotNull null
            val subject = cells.getOrNull(subjectIdx).orEmpty()
            if (subject.isBlank() || subject.equals("No results found.", ignoreCase = true)) {
                return@mapNotNull null
            }
            val teacher = teacherIdx?.let { cells.getOrNull(it) }.orEmpty()
            val level = levelIdx?.let { cells.getOrNull(it) }.orEmpty()
            val subjectLabel = listOf(subject, level).filter { it.isNotBlank() }.joinToString(" ")
            val grades = linkedMapOf<String, GradeCellValue>()
            for ((index, column) in gradeCols) {
                val raw = cells.getOrNull(index)?.trim().orEmpty()
                if (raw.isNotEmpty() && raw != "–" && raw != "-") {
                    grades[column.key] = GradeCellValue(value = raw)
                }
            }
            GradeRow(
                team = teacher.ifBlank { level },
                subject = subjectLabel,
                teamId = slug(subjectLabel).ifBlank { null },
                grades = grades,
            )
        }

        return GradesReport(columns = columns, grades = rows, alerts = alerts)
    }

    private fun parseAlerts(root: Element): List<String> =
        root.select(".errorSummary li, .flash-error, .alert, .errorMessage")
            .map { it.text().trim() }
            .filter { it.isNotEmpty() }

    private fun headerLabels(table: Element): List<String> {
        val fromThead = table.select("thead th").map { it.text().trim() }
        if (fromThead.isNotEmpty()) return fromThead
        return table.selectFirst("tr")?.select("th")?.map { it.text().trim() }.orEmpty()
    }

    private fun bodyRows(table: Element): List<Element> {
        val body = table.select("tbody tr")
        if (body.isNotEmpty()) return body
        return table.select("tr").filter { it.selectFirst("th") == null }
    }

    private fun indexOf(headers: List<String>, names: List<String>): Int? {
        val idx = headers.indexOfFirst { header ->
            val h = header.lowercase()
            names.any { name -> h == name || h.contains(name) }
        }
        return idx.takeIf { it >= 0 }
    }

    private fun slug(label: String): String =
        label.trim().lowercase()
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
}
