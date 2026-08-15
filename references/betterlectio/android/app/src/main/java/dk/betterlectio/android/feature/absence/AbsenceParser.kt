package dk.betterlectio.android.feature.absence

import dk.betterlectio.android.core.lectio.scrape.AspNetForm
import dk.betterlectio.android.core.util.LectioDateUtils
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.time.LocalDate
import java.time.LocalDateTime

/**
 * Absence overview + registrations.
 * Overview: Flutter `absence/scraping` (SFTabStudentAbsenceDataTable).
 * Registrations: Flutter/iOS FatabAbsenceFravaerGV + FatabMissingAarsagerGV
 * with activity details from schedule-brick tooltips (iOS StudentParser).
 */
object AbsenceParser {
    fun parseOverview(html: String): List<AbsenceTeamRow> {
        val doc = Jsoup.parse(html)
        val table = doc.getElementById("s_m_Content_Content_SFTabStudentAbsenceDataTable")
            ?: doc.selectFirst("table[id*=Absence]")
            ?: return emptyList()
        val rows = table.select("tr")
        // skip header rows (first ~3) and last total — Flutter extractAbsence
        if (rows.size <= 4) return emptyList()
        return rows.drop(3).dropLast(1).mapNotNull { parseTeamRow(it) }
    }

    fun parseSummaryPercents(html: String): Pair<Double?, Double?> {
        val doc = Jsoup.parse(html)
        fun pct(id: String): Double? {
            val t = doc.getElementById(id)?.text()
                ?.replace("%", "")
                ?.replace(",", ".")
                ?.trim()
                .orEmpty()
            return t.toDoubleOrNull()?.div(100.0)
        }
        // iOS StudentParser summary spans
        return pct("s_m_Content_Content_FremmoedeFravaer") to
            pct("s_m_Content_Content_SkriftligFravaer")
    }

    private fun parseTeamRow(row: Element): AbsenceTeamRow? {
        val cells = row.select("td")
        if (cells.size < 5) return null
        val teamCell = cells[0]
        val teamLink = teamCell.selectFirst("a")
        val team = teamLink?.text()?.trim() ?: teamCell.text().trim()
        if (team.isBlank()) return null
        val teamId = teamLink?.attr("href")?.let { href ->
            AspNetForm.queriesFromUrl(href)["holdelementid"]?.let { "HE$it" }
        }

        fun pct(i: Int): Double {
            val t = cells.getOrNull(i)?.text()?.replace("%", "")?.replace(",", ".")?.trim().orEmpty()
            return t.toDoubleOrNull()?.div(100.0) ?: 0.0
        }

        fun fraction(i: Int): AbsenceFraction {
            val t = cells.getOrNull(i)?.text()?.replace(",", ".")?.trim().orEmpty()
            if (t.isEmpty()) return AbsenceFraction()
            val parts = t.split("/")
            return AbsenceFraction(
                current = parts.getOrNull(0)?.toDoubleOrNull() ?: 0.0,
                total = parts.getOrNull(1)?.toDoubleOrNull() ?: 0.0,
            )
        }

        // Flutter: cells 1–8 alternating percent / fraction
        return AbsenceTeamRow(
            team = team,
            teamId = teamId,
            regularCurrentPercent = pct(1),
            regularCurrentModules = fraction(2),
            regularFinalPercent = pct(3),
            regularFinalModules = fraction(4),
            assignmentCurrentPercent = pct(5),
            assignmentCurrentTime = fraction(6),
            assignmentFinalPercent = pct(7),
            assignmentFinalTime = fraction(8),
        )
    }

    fun parseRegistrations(html: String): List<AbsenceRegistration> {
        val doc = Jsoup.parse(html)
        val out = mutableListOf<AbsenceRegistration>()

        val registered = doc.getElementById("s_m_Content_Content_FatabAbsenceFravaerGV")
        if (registered != null) {
            out += parseCauseTable(registered, missingCause = false)
        }
        val missing = doc.getElementById("s_m_Content_Content_FatabMissingAarsagerGV")
        if (missing != null) {
            out += parseCauseTable(missing, missingCause = true)
        }

        // Fallback for simplified fixtures / alternate layouts
        if (out.isEmpty()) {
            val table = doc.selectFirst("table[id*=Absence], table[id*=fravaer], table[id*=Fravaer], table")
                ?: return emptyList()
            return table.select("tr").drop(1).mapIndexedNotNull { i, row ->
                val cells = desktopCells(row)
                if (cells.size < 3) return@mapIndexedNotNull null
                val id = extractRegistrationId(row) ?: "reg-$i"
                AbsenceRegistration(
                    id = id,
                    date = LectioDateUtils.parseLectioDate(cells[0].text())?.toLocalDate(),
                    team = cells.getOrNull(1)?.text()?.trim().orEmpty(),
                    cause = cells.getOrNull(2)?.text()?.trim().orEmpty()
                        .ifBlank { cells.getOrNull(6)?.text()?.trim().orEmpty() },
                    status = cells.getOrNull(3)?.text()?.trim().orEmpty(),
                )
            }
        }
        return AbsencePresentation.sortNewestFirst(out)
    }

    private fun parseCauseTable(table: Element, missingCause: Boolean): List<AbsenceRegistration> {
        return table.select("tr").mapNotNull { row ->
            // Skip header rows (iOS: has th)
            if (row.select("th").isNotEmpty()) return@mapNotNull null
            val cells = desktopCells(row)
            if (cells.size < 4) return@mapNotNull null

            val week = cells.getOrNull(0)?.text()?.trim().orEmpty()
            val activityCell = cells.getOrNull(1)
            val activity = activityCell?.selectFirst("a.s2skemabrik, a.s2bgbox")
            val activityText = activity?.text()?.trim()
                ?: activityCell?.text()?.trim().orEmpty()
            val details = parseActivityDetails(activity, activityText)

            val percent = cells.getOrNull(2)?.text()
                ?.replace("%", "")
                ?.replace(",", ".")
                ?.trim()
                ?.toDoubleOrNull()
                ?.div(100.0)

            val typeCell = cells.getOrNull(3)
            val typeText = typeCell?.text()?.trim().orEmpty()
            val hasOk = typeCell?.selectFirst("img[src*=ok.gif]") != null
            val isApproved = hasOk || typeText.contains("Godskrevet", ignoreCase = true)
            val status = when {
                isApproved -> "Godskrevet"
                typeText.contains("Fravær", true) -> "Fravær"
                typeText.isNotBlank() -> typeText
                else -> "Fravær"
            }

            val registeredRaw = cells.getOrNull(4)?.text()?.trim().orEmpty()
            // First line is date/time; second may be teacher initials
            val registeredFirstLine = registeredRaw.lineSequence().firstOrNull()?.trim().orEmpty()
            val registeredAt = parseRegisteredAt(registeredFirstLine.ifBlank { registeredRaw })

            val remark = cells.getOrNull(5)?.text()?.trim().orEmpty()

            // Cause column: registered table col 6 (wholeText keeps newlines from <br>)
            val causeCell = cells.getOrNull(6)
            val causeText = causeCell?.wholeText()?.trim().orEmpty()
                .ifBlank { causeCell?.text()?.trim().orEmpty() }
            val causeLines = causeText.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
            val cause = when {
                missingCause -> ""
                else -> AbsenceCauses.all.firstOrNull { c ->
                    causeText.startsWith(c, ignoreCase = true)
                } ?: causeLines.firstOrNull().orEmpty()
            }
            val note = if (missingCause) {
                ""
            } else {
                // Prefer second line; else text after matched cause name
                when {
                    causeLines.size > 1 -> causeLines.drop(1).joinToString(" ")
                    cause.isNotBlank() && causeText.length > cause.length ->
                        causeText.removePrefix(cause).trim().trimStart(':', '-', '–')
                    else -> ""
                }
            }

            val id = extractRegistrationId(row) ?: return@mapNotNull null

            val hold = details.hold.ifBlank {
                // Fallback: "fr 10/10 1. modul - 1g4 da • Ka • 24"
                extractHoldFromActivityText(activityText)
            }

            val date: LocalDate? = details.dateFromTooltip
                ?: registeredAt?.toLocalDate()

            AbsenceRegistration(
                id = id,
                date = date,
                team = hold.ifBlank { activityText },
                cause = cause,
                status = status,
                week = week,
                activityTitle = activityText,
                percent = percent,
                registeredAt = registeredAt,
                note = note,
                missingCause = missingCause,
                teacher = details.teacher,
                room = details.room,
                dateTimeLabel = details.dateTimeLabel.ifBlank {
                    registeredFirstLine
                },
                lessonTitle = details.title,
                remark = remark,
                isApproved = isApproved,
            )
        }
    }

    private data class ActivityDetails(
        val title: String = "",
        val hold: String = "",
        val teacher: String = "",
        val room: String = "",
        val dateTimeLabel: String = "",
        val dateFromTooltip: LocalDate? = null,
    )

    /**
     * iOS [StudentParser.parseActivityDetails] — tooltip lines + activity text fallback.
     */
    private fun parseActivityDetails(link: Element?, activityText: String): ActivityDetails {
        if (link == null) {
            return ActivityDetails(hold = extractHoldFromActivityText(activityText))
        }
        val tooltip = link.attr("data-tooltip")
        val lines = tooltip.lines().map { it.trim() }.filter { it.isNotEmpty() }

        var title = ""
        var dateTimeLabel = ""
        var hold = ""
        var teacher = ""
        var room = ""
        var dateFromTooltip: LocalDate? = null

        lines.forEachIndexed { index, line ->
            when {
                line.startsWith("Hold:", ignoreCase = true) ->
                    hold = line.substringAfter(':').trim()
                line.startsWith("Lærer:", ignoreCase = true) ||
                    line.startsWith("Lærere:", ignoreCase = true) -> {
                    val teacherPart = line.substringAfter(':').trim()
                    // "Name (Abbrev)" → Abbrev
                    teacher = Regex("""\(([^)]+)\)\s*$""").find(teacherPart)?.groupValues?.get(1)
                        ?: teacherPart
                }
                line.startsWith("Lokale:", ignoreCase = true) ||
                    line.startsWith("Lokaler:", ignoreCase = true) ->
                    room = line.substringAfter(':').trim()
                line.contains("/") && (
                    line.contains("til", ignoreCase = true) ||
                        Regex("""\d{1,2}/\d{1,2}""").containsMatchIn(line)
                    ) -> {
                    dateTimeLabel = line
                    dateFromTooltip = parseDateFromDateTimeLabel(line)
                }
                // Free title is first non-prefixed, non-date line
                index == 0 && !line.contains("/") -> title = line
            }
        }

        if (hold.isEmpty()) {
            hold = extractHoldFromActivityText(activityText)
        }
        if (teacher.isEmpty() || room.isEmpty()) {
            val parts = activityText.split("•").map { it.trim() }
            // "… - hold" then • teacher • room
            if (parts.size >= 2 && teacher.isEmpty()) teacher = parts.getOrNull(1).orEmpty()
            if (parts.size >= 3 && room.isEmpty()) room = parts.getOrNull(2).orEmpty()
        }

        return ActivityDetails(
            title = title,
            hold = hold,
            teacher = teacher,
            room = room,
            dateTimeLabel = dateTimeLabel,
            dateFromTooltip = dateFromTooltip,
        )
    }

    private fun extractHoldFromActivityText(activityText: String): String {
        // "fr 10/10 1. modul - 1g4 da • Ka • 24"
        val afterDash = activityText.substringAfter(" - ", "").trim()
        if (afterDash.isNotEmpty()) {
            return afterDash.substringBefore("•").trim()
        }
        return activityText.substringBefore("•").trim()
    }

    private fun parseDateFromDateTimeLabel(label: String): LocalDate? {
        // "10/10-2025 08:10 til 09:50" or "10/10-2025 08:12"
        val cleaned = label.replace(Regex("""\s+til\s+.*"""), "").trim()
        return LectioDateUtils.parseLectioDate(cleaned)?.toLocalDate()
            ?: run {
                val dateToken = cleaned.split(Regex("""\s+""")).firstOrNull().orEmpty()
                LectioDateUtils.parseLectioDate(dateToken)?.toLocalDate()
            }
    }

    private fun extractRegistrationId(row: Element): String? {
        // Flutter: prefer edit-button query `id` over absid on the activity brick
        row.select("a[href]").forEach { a ->
            val href = a.attr("href")
            AspNetForm.queriesFromUrl(href)["id"]?.takeIf { it.isNotBlank() }?.let { return it }
            Regex("""[?&]id=(\d+)""").find(href)?.let { return it.groupValues[1] }
        }
        row.select("a[href]").forEach { a ->
            val href = a.attr("href")
            Regex("""absid=(\d+)""").find(href)?.let { return it.groupValues[1] }
            Regex("""aftaleid=(\d+)""").find(href)?.let { return it.groupValues[1] }
        }
        return null
    }

    private fun parseRegisteredAt(raw: String): LocalDateTime? {
        // "dd/MM-yyyy HH:mm …" — take first two tokens (date + time)
        val parts = raw.trim().split(Regex("""\s+"""))
        if (parts.size >= 2) {
            LectioDateUtils.parseLectioDate("${parts[0]} ${parts[1]}")?.let { return it }
        }
        return LectioDateUtils.parseLectioDate(raw)
    }

    private fun desktopCells(row: Element): List<Element> {
        // iOS: td:not(.OnlyMobile) so activity cell (no class) is included
        val nonMobile = row.select("td:not(.OnlyMobile)")
        if (nonMobile.isNotEmpty()) return nonMobile
        val desktop = row.select("td.OnlyDesktop")
        if (desktop.isNotEmpty()) return desktop
        return row.select("td")
    }
}
