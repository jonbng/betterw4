package dk.betterw4.android.feature.absence

import dk.betterw4.android.core.w4.W4Dates
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.time.LocalDate

data class W4AbsencePage(
    val meter: W4AbsenceMeter?,
    val registrations: List<AbsenceRegistration>,
)

data class W4HomeAbsenceMeters(
    val academic: W4AbsenceMeter?,
    val ea: W4AbsenceMeter?,
)

/**
 * Home AC/EA meters (`You have N absences and M latenesses`) plus Yii
 * absence-list tables on `people/students/absences` and `eaabsences`.
 */
object W4AbsenceParser {

    private val METER = Regex(
        """You have (\d+) absences? and (\d+) lateness(?:es)?""",
        RegexOption.IGNORE_CASE,
    )

    private val DATE_HEADERS = listOf("date", "when", "absence date")
    private val PERIOD_HEADERS = listOf("period", "slot", "time", "lesson")
    private val CLASS_HEADERS = listOf("class", "subject", "course", "activity", "group")
    private val TYPE_HEADERS = listOf("type", "kind", "absence type")
    private val STATUS_HEADERS = listOf("status")
    private val NOTE_HEADERS = listOf("comment", "note", "remarks", "reason", "explanation")
    private val TEACHER_HEADERS = listOf("teacher", "staff")

    fun parseHomeMeters(html: String): W4HomeAbsenceMeters {
        val doc = Jsoup.parse(html)
        val academic = meterFrom(doc.selectFirst("#academic-absences"))
            ?: meterNearLink(doc, "people/students/absences")
        val ea = meterFrom(doc.selectFirst("#ea-absences"))
            ?: meterNearLink(doc, "people/students/eaabsences")
        return W4HomeAbsenceMeters(academic = academic, ea = ea)
    }

    fun parseList(html: String, source: AbsenceSource): W4AbsencePage {
        val doc = Jsoup.parse(html)
        val inner = doc.getElementById("content_inner") ?: doc.body()
        val meter = meterFrom(inner)
            ?: when (source) {
                AbsenceSource.ACADEMICS -> meterFrom(doc.selectFirst("#academic-absences"))
                AbsenceSource.EA -> meterFrom(doc.selectFirst("#ea-absences"))
            }
        val table = inner.selectFirst("table.items") ?: inner.selectFirst("table")
        val rows = table?.let { parseTable(it, source) }.orEmpty()
        return W4AbsencePage(
            meter = meter ?: meterFromRows(rows),
            registrations = rows,
        )
    }

    internal fun parseMeterText(text: String): W4AbsenceMeter? {
        val match = METER.find(text) ?: return null
        return W4AbsenceMeter(
            absences = match.groupValues[1].toIntOrNull() ?: return null,
            latenesses = match.groupValues[2].toIntOrNull() ?: return null,
        )
    }

    internal fun normalizeType(raw: String): String {
        val t = raw.trim()
        if (t.isEmpty()) return "Absence"
        return if (t.contains("late", ignoreCase = true) || t.contains("forsink", ignoreCase = true)) {
            "Lateness"
        } else {
            t.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        }
    }

    internal fun meterFromRows(rows: List<AbsenceRegistration>): W4AbsenceMeter? {
        if (rows.isEmpty()) return null
        var absences = 0
        var latenesses = 0
        for (row in rows) {
            if (isLateness(row.cause)) latenesses++ else absences++
        }
        return W4AbsenceMeter(absences = absences, latenesses = latenesses)
    }

    fun isLateness(cause: String): Boolean =
        cause.contains("late", ignoreCase = true) || cause.contains("forsink", ignoreCase = true)

    private fun meterFrom(el: Element?): W4AbsenceMeter? =
        el?.text()?.let { parseMeterText(it) }

    private fun meterNearLink(doc: Element, route: String): W4AbsenceMeter? {
        val link = doc.select("a[href]").firstOrNull { a ->
            val href = a.attr("href")
            href.contains(route) && !href.contains("$route/")
        } ?: return null
        return parseMeterText(link.parent()?.text().orEmpty())
    }

    private fun parseTable(table: Element, source: AbsenceSource): List<AbsenceRegistration> {
        val headers = headerLabels(table).map { it.lowercase() }
        val dateIdx = indexOf(headers, DATE_HEADERS)
        val periodIdx = indexOf(headers, PERIOD_HEADERS)
        val classIdx = indexOf(headers, CLASS_HEADERS)
        val typeIdx = indexOf(headers, TYPE_HEADERS)
        val statusIdx = indexOf(headers, STATUS_HEADERS)
        val noteIdx = indexOf(headers, NOTE_HEADERS)
        val teacherIdx = indexOf(headers, TEACHER_HEADERS)

        return bodyRows(table).mapIndexedNotNull { index, tr ->
            if (tr.selectFirst("td.empty") != null) return@mapIndexedNotNull null
            val cells = tr.select("td").map { it.text().trim() }
            if (cells.isEmpty() || cells.all { it.isBlank() }) return@mapIndexedNotNull null
            val dateRaw = cell(cells, dateIdx, 0)
            if (dateRaw.equals("No results found.", ignoreCase = true)) return@mapIndexedNotNull null
            val date = parseDateCell(dateRaw)
            val period = cell(cells, periodIdx, if (dateIdx == null) 1 else null)
            val klass = cell(cells, classIdx, if (headers.isEmpty()) 2 else null)
            val type = normalizeType(cell(cells, typeIdx, if (headers.isEmpty()) 3 else null))
            val status = cell(cells, statusIdx)
            val note = cell(cells, noteIdx)
            val teacher = cell(cells, teacherIdx)
            val team = klass.ifBlank { period }
            if (team.isBlank() && date == null && type == "Absence" && note.isBlank()) {
                return@mapIndexedNotNull null
            }
            val dateLabel = buildString {
                if (date != null) append(W4Dates.format(date))
                else if (dateRaw.isNotBlank()) append(dateRaw)
                if (period.isNotBlank()) {
                    if (isNotEmpty()) append(" · ")
                    append(period)
                }
            }
            AbsenceRegistration(
                id = listOf(source.id, dateRaw, period, klass, type, index.toString())
                    .joinToString("|"),
                date = date,
                team = team.ifBlank { type },
                cause = type,
                status = status,
                activityTitle = team,
                percent = null,
                note = note,
                missingCause = false,
                teacher = teacher,
                dateTimeLabel = dateLabel,
                lessonTitle = source.label,
                remark = source.label,
                editable = false,
            )
        }
    }

    private fun parseDateCell(raw: String): LocalDate? {
        val first = raw.substringBefore(' ').trim().ifBlank { raw.trim() }
        return W4Dates.parse(first) ?: W4Dates.parse(raw.trim())
    }

    private fun cell(cells: List<String>, index: Int?, fallback: Int? = null): String {
        val idx = index ?: fallback ?: return ""
        return cells.getOrElse(idx) { "" }
    }

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
            names.any { name -> header == name || header.contains(name) }
        }
        return idx.takeIf { it >= 0 }
    }
}

enum class AbsenceSource(val id: String, val label: String) {
    ACADEMICS("ac", "Academics"),
    EA("ea", "EA"),
}
