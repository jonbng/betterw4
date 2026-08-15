package dk.betterlectio.android.feature.grades

import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Grades from `grade_report.aspx` / KarakterGV.
 *
 * Column identity and order are taken from the live header row — Lectio varies
 * which columns exist per school/term (e.g. "Afsluttende års-/standpunktskarakter").
 * A fixed column list silently shifts values and can swap årskarakter/eksamen.
 * Mirrors extension `parseKaraktererFromDOM` / `canonicalColumnKey`.
 */
object GradeParser {

    fun parse(html: String): GradesReport {
        val doc = Jsoup.parse(html)
        val columns = mutableListOf<GradeColumn>()
        val grades = mutableListOf<GradeRow>()

        val table = doc.getElementById("s_m_Content_Content_karakterView_KarakterGV")
            ?: doc.selectFirst("table[id*=KarakterGV], table[id*=Karakter]")

        if (table != null) {
            val rows = table.select("tr")
            if (rows.isNotEmpty()) {
                // Header: first two desktop <th> are Hold + Fag; rest are grade columns.
                val headerCells = desktopHeaderCells(rows[0])
                for (h in 2 until headerCells.size) {
                    val label = headerCells[h].text().replace(Regex("\\s+"), " ").trim()
                    if (label.isEmpty()) continue
                    columns += GradeColumn(key = canonicalColumnKey(label), label = label)
                }

                for (i in 1 until rows.size) {
                    val cells = desktopCells(rows[i])
                    if (cells.size < 2 + columns.size) continue

                    val teamCell = cells[0]
                    val teamSpan = teamCell.selectFirst("[data-lectiocontextcard], [data-lectioContextCard]")
                    val team = teamSpan?.text()?.trim() ?: teamCell.text().trim()
                    val teamId = teamSpan?.attr("data-lectiocontextcard")
                        ?.ifBlank { null }
                        ?: teamSpan?.attr("data-lectioContextCard")?.ifBlank { null }
                    val subject = cells[1].text().trim()

                    val gradeMap = linkedMapOf<String, GradeCellValue>()
                    for (c in columns.indices) {
                        val cell = cells.getOrNull(c + 2) ?: continue
                        val parsed = parseGradeCell(cell) ?: continue
                        gradeMap[columns[c].key] = parsed
                    }

                    grades += GradeRow(
                        team = team,
                        subject = subject.ifBlank { team },
                        teamId = teamId,
                        grades = gradeMap,
                    )
                }
            }
        }

        return GradesReport(
            columns = columns,
            grades = grades,
            notes = parseNotesStructured(doc),
            alerts = parseAlerts(doc),
        )
    }

    fun parseNotes(html: String): List<GradeNoteEntry> {
        val doc = Jsoup.parse(html)
        return parseNotesStructured(doc)
    }

    /**
     * Maps a Lectio header label to a stable key so the rest of the UI can
     * recognise well-known columns. Order of checks matters: "afsluttende" and
     * "eksamen" labels both contain "års"-ish wording.
     */
    fun canonicalColumnKey(raw: String): String {
        val t = raw.lowercase().replace(Regex("\\s+"), " ").trim()
        if (Regex("^1\\.?\\s*standpunkt").containsMatchIn(t)) return "1.standpunkt"
        if (Regex("^2\\.?\\s*standpunkt").containsMatchIn(t)) return "2.standpunkt"
        if (Regex("^3\\.?\\s*standpunkt").containsMatchIn(t)) return "3.standpunkt"
        if (t.contains("afsluttende")) return "afsluttende"
        if (t.contains("intern")) return "intern prøve"
        if (t.contains("eksamen")) return "eksamenskarakter"
        if (t.startsWith("årskarakter") || t.startsWith("aarskarakter")) return "årskarakter"
        val slug = t.replace(Regex("[^a-z0-9æøå]+"), "-").trim('-')
        return slug.ifEmpty { raw }
    }

    private fun parseAlerts(doc: org.jsoup.nodes.Document): List<String> {
        val ids = listOf(
            "s_m_Content_Content_karakterView_WrittenProtokolBlockLit",
            "s_m_Content_Content_karakterView_OralProtokolBlockLit",
        )
        return ids.mapNotNull { id ->
            doc.getElementById(id)?.text()?.trim()?.takeIf { it.isNotEmpty() }
        }
    }

    private fun parseNotesStructured(doc: org.jsoup.nodes.Document): List<GradeNoteEntry> {
        val grid = doc.getElementById("s_m_Content_Content_karakterView_KarakterNoterGrid")
            ?: doc.selectFirst("table[id*=KarakterNoter], table[id*=NoterGrid]")
            ?: return emptyList()

        return grid.select("tr").drop(1).mapNotNull { row ->
            val cells = desktopCells(row)
            if (cells.size < 4) return@mapNotNull null

            val hold = cells[0].text().trim()
            val gradeType = cells[1].text().replace(Regex("\\s+"), " ").trim()
            val grade = cells[2].text().trim()
            val insertedAt = cells[3].text().trim()
            // Note is usually the last desktop cell (may include wrap OnlyDesktop).
            val noteCell = cells.lastOrNull()
            val noteText = noteCell?.let { cell ->
                // Prefer last cell when there are ≥5 desktop cells; if only 4, no note body.
                if (cells.size >= 5) cell.wholeText().trim().ifEmpty { cell.text().trim() } else null
            }?.takeIf { it.isNotEmpty() && it != grade && it != insertedAt && it != hold && it != gradeType }

            if (hold.isEmpty() && gradeType.isEmpty()) return@mapNotNull null

            GradeNoteEntry(
                hold = hold,
                gradeType = gradeType,
                grade = grade,
                insertedAt = insertedAt,
                note = noteText,
            )
        }.distinct().take(100)
    }

    private fun parseGradeCell(cell: Element): GradeCellValue? {
        val titled = cell.selectFirst("div[title], span[title]")
        val valueEl = titled ?: cell.children().firstOrNull() ?: cell
        val text = valueEl.text().trim()
        if (text.isEmpty() || text == "--" || text == "–" || text == "—") return null

        val title = titled?.attr("title")
            ?.ifBlank { null }
            ?: cell.attr("title").ifBlank { null }

        return GradeCellValue(
            value = text,
            weight = extractMetadataValue(title, "Vægt:", "Weight:")
                ?.replace(",", ".")
                ?.toDoubleOrNull(),
            xprsSubject = extractMetadataValue(title, "XPRSFag:"),
            source = extractMetadataValue(title, "Kilde:", "Source:"),
        )
    }

    private fun extractMetadataValue(title: String?, vararg prefixes: String): String? {
        if (title.isNullOrBlank()) return null
        for (rawLine in title.lineSequence()) {
            val line = rawLine.trim()
            for (prefix in prefixes) {
                if (line.startsWith(prefix, ignoreCase = true)) {
                    val value = line.substring(prefix.length).trim()
                    if (value.isNotEmpty()) return value
                } else if (line.contains(prefix, ignoreCase = true) &&
                    (prefix.startsWith("Vægt") || prefix.startsWith("Weight"))
                ) {
                    // "Vægt: 1" mid-line fallback used by some titles
                    val after = line.substringAfter(':', missingDelimiterValue = "")
                        .trim()
                        .replace(",", ".")
                    if (after.isNotEmpty()) return after
                }
            }
        }
        return null
    }

    private fun desktopHeaderCells(row: Element): List<Element> {
        val desktop = row.select("th.OnlyDesktop")
        if (desktop.isNotEmpty()) return desktop
        val nonMobile = row.select("th:not(.OnlyMobile)")
        if (nonMobile.isNotEmpty()) return nonMobile
        return row.select("th")
    }

    private fun desktopCells(row: Element): List<Element> {
        // Prefer OnlyDesktop; include wrap.OnlyDesktop for notes grid.
        val desktop = row.select("td.OnlyDesktop, td.wrap.OnlyDesktop")
        if (desktop.isNotEmpty()) return desktop
        val nonMobile = row.select("td:not(.OnlyMobile)")
        if (nonMobile.isNotEmpty()) return nonMobile
        return row.select("td")
    }
}
