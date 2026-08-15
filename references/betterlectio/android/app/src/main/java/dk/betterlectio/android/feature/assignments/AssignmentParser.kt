package dk.betterlectio.android.feature.assignments

import dk.betterlectio.android.core.lectio.scrape.AspNetForm
import dk.betterlectio.android.core.util.LectioDateUtils
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Assignments list + detail.
 * List: iOS [AssignmentParser] (`ExerciseGV` + OnlyDesktop) with Flutter column layout.
 * Detail: iOS label-based info table + RecipientGV + StudentGV.
 */
object AssignmentParser {
    fun parseList(html: String): List<AssignmentItem> {
        val doc = Jsoup.parse(html)
        val table = doc.getElementById("s_m_Content_Content_ExerciseGV")
            ?: doc.selectFirst("table[id*=ExerciseGV]")
            ?: doc.selectFirst("table")
            ?: return emptyList()
        return table.select("tr").mapNotNull { row ->
            if (row.select("th").isNotEmpty()) return@mapNotNull null
            parseRow(row)
        }
    }

    private fun parseRow(row: Element): AssignmentItem? {
        val cols = desktopCells(row)
        if (cols.size < 6) return null
        val week = cols[0].text().trim().toIntOrNull() ?: 0
        val holdSpan = cols[1].selectFirst("span[data-lectiocontextcard]")
        val team = holdSpan?.text()?.trim() ?: cols[1].text().trim()
        val holdElementId = holdSpan?.attr("data-lectiocontextcard")?.ifBlank { null }
        val link = cols[2].selectFirst("a") ?: return null
        val href = link.attr("href")
        val id = AspNetForm.queriesFromUrl(href)["exerciseid"]
            ?: Regex("""exerciseid=(\d+)""").find(href)?.groupValues?.get(1)
            ?: return null
        val title = link.text().trim()
        val deadline = LectioDateUtils.parseLectioDate(cols[3].text().trim())
        val studentTime = cols.getOrNull(4)?.text()?.replace(',', '.')?.trim()?.toDoubleOrNull() ?: 0.0
        val statusCell = cols.getOrNull(5)
        val statusText = statusCell?.text()?.trim().orEmpty()
        val status = when {
            statusCell?.selectFirst("span.exercisewait") != null -> "Venter"
            statusText.equals("Venter", true) -> "Venter"
            statusText.equals("Afventer", true) -> "Venter"
            else -> statusText
        }
        val absence = cols.getOrNull(6)?.text()?.trim().orEmpty()
        val awaits = cols.getOrNull(7)?.text()?.trim().orEmpty()
        val note = cols.getOrNull(8)?.text()?.trim().orEmpty()
        var grade: String? = null
        var gradeNote: String? = null
        cols.getOrNull(9)?.let { gradeCell ->
            val parts = gradeCell.html()
                .split(Regex("""<br\s*/?>""", RegexOption.IGNORE_CASE))
                .map { Jsoup.parse(it).text().trim() }
                .filter { it.isNotEmpty() }
            grade = parts.getOrNull(0)
            gradeNote = parts.getOrNull(1)
        }
        val studentNote = cols.getOrNull(10)?.text()?.trim()?.ifBlank { null }
        return AssignmentItem(
            id = id,
            title = title,
            team = team,
            week = week,
            deadline = deadline,
            status = status,
            studentTime = studentTime,
            awaits = awaits,
            note = note,
            absence = absence,
            grade = grade,
            gradeNote = gradeNote,
            studentNote = studentNote,
            holdElementId = holdElementId,
            detailUrl = href.ifBlank { null },
        )
    }

    fun parseDetail(html: String, item: AssignmentItem): AssignmentDetail {
        val doc = Jsoup.parse(html)
        val title = doc.getElementById("m_Content_NameLbl")?.text()?.trim().orEmpty().ifBlank { item.title }

        val infoSection = doc.selectFirst("#m_Content_registerAfl_pa")
        var hold = item.team
        var grading = doc.getElementById("m_Content_gradeScaleIdLbl")?.text()?.trim().orEmpty()
        var responsible = ""
        var studentTime = item.studentTime
        var description = item.note
        val files = mutableListOf<Pair<String, String>>()

        if (infoSection != null) {
            // Description files — iOS: a[id*=showdocumentHyperlnk]
            infoSection.select("a[id*=showdocumentHyperlnk], #m_Content_ExerciseFilePnl a").forEach { a ->
                val href = a.attr("href").trim()
                if (href.isEmpty()) return@forEach
                val name = a.text().trim().ifBlank { "Fil" }
                val url = absolutize(href)
                files += name to url
            }

            for (row in infoSection.select("table.ls-std-table-inputlist tr, table tr")) {
                val th = row.selectFirst("th")?.text()?.trim().orEmpty()
                val td = row.selectFirst("td") ?: continue
                when {
                    th.startsWith("Hold") -> hold = td.text().trim().ifBlank { hold }
                    th.startsWith("Karakterskala") -> grading = td.text().trim()
                    th.startsWith("Ansvarlig") -> responsible = td.text().trim()
                    th.startsWith("Elevtid") -> {
                        val raw = td.text().trim().ifBlank {
                            doc.getElementById("m_Content_WeightLbl")?.text()?.trim().orEmpty()
                        }
                        studentTime = raw.split(Regex("""\s+""")).firstOrNull()
                            ?.replace(',', '.')
                            ?.toDoubleOrNull()
                            ?: studentTime
                    }
                    th.startsWith("Opgavenote") -> description = td.text().trim().ifBlank { description }
                    th.contains("undervisningsbeskrivelse") -> { /* optional flag */ }
                }
            }
            // Fallback WeightLbl if Elevtid row missing
            if (studentTime == item.studentTime) {
                val weight = doc.getElementById("m_Content_WeightLbl")?.text()?.trim().orEmpty()
                studentTime = weight.split(Regex("""\s+""")).firstOrNull()
                    ?.replace(',', '.')
                    ?.toDoubleOrNull()
                    ?: studentTime
            }
        } else {
            // Legacy fallbacks (old Android paths)
            description = doc.selectFirst("#m_Content_DescriptionPnl, .exercise-description")
                ?.text()?.trim().orEmpty().ifBlank { item.note }
            doc.select("#m_Content_ExerciseFilePnl a").forEach { a ->
                val href = a.attr("href")
                if (href.isNotBlank()) files += a.text().trim().ifBlank { "Fil" } to absolutize(href)
            }
            responsible = doc.selectFirst("[data-lectiocontextcard^=T]")?.text()?.trim().orEmpty()
        }

        // Student status row
        var awaits = item.awaits
        var status = item.status
        var completed = false
        var studentGrade: String? = item.grade
        var studentGradeNote: String? = item.gradeNote
        doc.selectFirst("#m_Content_StudentGV")?.select("tr")?.forEach { row ->
            val cells = row.select("td")
            if (cells.size < 6) return@forEach
            awaits = cells.getOrNull(2)?.text()?.trim()?.ifBlank { awaits } ?: awaits
            status = cells.getOrNull(3)?.text()?.trim()?.ifBlank { status } ?: status
            completed = cells.getOrNull(4)?.selectFirst("input[type=checkbox][checked]") != null ||
                cells.getOrNull(4)?.selectFirst("input[type=checkbox]")?.hasAttr("checked") == true
            studentGrade = cells.getOrNull(5)?.text()?.trim()?.ifBlank { null } ?: studentGrade
            studentGradeNote = cells.getOrNull(6)?.text()?.trim()?.ifBlank { null } ?: studentGradeNote
            return@forEach // first data row only
        }

        // Submissions
        val submissions = mutableListOf<AssignmentSubmission>()
        val recipient = doc.selectFirst("#m_Content_RecipientGV")
        if (recipient != null && recipient.select("span.norecord").isEmpty()) {
            var index = 0
            for (row in recipient.select("tr")) {
                val cells = row.select("td")
                if (cells.size < 4) continue
                val timestamp = cells[0].text().trim()
                val user = cells[1].text().trim()
                if (timestamp.isBlank() && user.isBlank()) continue
                val comment = cells.getOrNull(2)?.text()?.trim()?.ifBlank { null }
                val docLink = cells.getOrNull(3)?.selectFirst("a")
                submissions += AssignmentSubmission(
                    id = "$index",
                    timestamp = timestamp,
                    user = user,
                    comment = comment,
                    documentName = docLink?.text()?.trim()?.ifBlank { null },
                    documentUrl = docLink?.attr("href")?.takeIf { it.isNotBlank() }?.let { absolutize(it) },
                )
                index++
            }
        }

        return AssignmentDetail(
            item = item.copy(
                title = title,
                team = hold,
                status = status,
                awaits = awaits,
                studentTime = studentTime,
                note = description.ifBlank { item.note },
                grade = studentGrade,
                gradeNote = studentGradeNote,
            ),
            description = description,
            files = files.distinctBy { it.second },
            responsible = responsible,
            grading = grading,
            submissions = submissions,
            completed = completed,
            studentGrade = studentGrade,
            studentGradeNote = studentGradeNote,
        )
    }

    private fun desktopCells(row: Element): List<Element> {
        val desktop = row.select("td.OnlyDesktop")
        if (desktop.isNotEmpty()) return desktop
        val nonMobile = row.select("td:not(.OnlyMobile)")
        if (nonMobile.isNotEmpty()) return nonMobile
        return row.select("td")
    }

    private fun absolutize(href: String): String = when {
        href.startsWith("http") -> href
        href.startsWith("/") -> "https://www.lectio.dk$href"
        else -> "https://www.lectio.dk/$href"
    }
}
