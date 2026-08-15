package dk.betterlectio.android.feature.grades

/**
 * Pure helpers for weighted per-column averages and type filtering.
 *
 * Deliberate rules (extension `computeColumnAverages` / `gradeToNumber`):
 * - Average is always **for one column** — never mix grade types into one snit.
 * - Weight from cell metadata, default 1.0; skip weight ≤ 0.
 * - Only Danish 7-step scale grades count toward averages.
 * - Display uses Danish decimal comma.
 */
object GradeAverage {

    /** Preferred default column when opening the grades page. */
    val PREFERRED_COLUMN_ORDER = listOf(
        "1.standpunkt",
        "2.standpunkt",
        "3.standpunkt",
        "afsluttende",
        "intern prøve",
        "årskarakter",
        "eksamenskarakter",
    )

    /** Most-final grade first — for representative-grade helpers. */
    private val REPRESENTATIVE_PRIORITY = listOf(
        "eksamenskarakter",
        "årskarakter",
        "afsluttende",
        "intern prøve",
        "3.standpunkt",
        "2.standpunkt",
        "1.standpunkt",
    )

    private val SEVEN_STEP: Map<String, Double> = mapOf(
        "12" to 12.0,
        "10" to 10.0,
        "7" to 7.0,
        "4" to 4.0,
        "02" to 2.0,
        "00" to 0.0,
        "-3" to -3.0,
        // Common unpadded forms
        "2" to 2.0,
        "0" to 0.0,
    )

    /**
     * Short chip / header label for a column key.
     * Unknown keys fall back to [GradeColumn.label] or a truncated key.
     */
    fun shortLabel(column: GradeColumn): String = shortLabelForKey(column.key, column.label)

    fun shortLabelForKey(key: String, fallbackLabel: String = key): String = when (key) {
        "1.standpunkt" -> "1.SP"
        "2.standpunkt" -> "2.SP"
        "3.standpunkt" -> "3.SP"
        "afsluttende" -> "Afsl."
        "intern prøve" -> "Int."
        "årskarakter" -> "Års"
        "eksamenskarakter" -> "Eks."
        else -> {
            val label = fallbackLabel.replace(Regex("\\s+"), " ").trim()
            if (label.length <= 10) label else label.take(9) + "…"
        }
    }

    /** Pick default selected column key (null = Alle only when nothing better). */
    fun defaultColumnKey(columns: List<GradeColumn>, rows: List<GradeRow>): String? {
        for (key in PREFERRED_COLUMN_ORDER) {
            if (columns.any { it.key == key } && rows.any { it.cell(key) != null }) {
                return key
            }
        }
        for (col in columns) {
            if (rows.any { it.cell(col.key) != null }) return col.key
        }
        return columns.firstOrNull()?.key
    }

    fun filterRows(rows: List<GradeRow>, columnKey: String?): List<GradeRow> {
        if (columnKey == null) return rows.filter { it.grades.isNotEmpty() }
        return rows.filter { it.cell(columnKey) != null }
    }

    fun displayGrade(row: GradeRow, columnKey: String?): String {
        if (columnKey == null) {
            return row.gradeSummary.ifBlank { "—" }
        }
        return row.cell(columnKey)?.value?.ifBlank { "—" } ?: "—"
    }

    /**
     * Weighted average for a single column. Returns null when no 7-step values.
     */
    fun weightedAverage(rows: List<GradeRow>, columnKey: String): Double? {
        var sum = 0.0
        var weight = 0.0
        for (row in rows) {
            val cell = row.cell(columnKey) ?: continue
            val n = gradeToNumber(cell.value) ?: continue
            val w = (cell.weight ?: 1.0).coerceAtLeast(0.0)
            if (w <= 0.0) continue
            sum += n * w
            weight += w
        }
        if (weight <= 0.0) return null
        return sum / weight
    }

    fun weightedAverageDisplay(rows: List<GradeRow>, columnKey: String): String? {
        val avg = weightedAverage(rows, columnKey) ?: return null
        return formatAverage(avg)
    }

    /**
     * Per-column weighted averages for every column that has at least one
     * numeric grade. Used for the "Alle" multi-stat summary — never a single
     * mixed average across types.
     */
    fun columnAverages(
        rows: List<GradeRow>,
        columns: List<GradeColumn>,
    ): List<Pair<GradeColumn, String>> {
        return columns.mapNotNull { col ->
            val display = weightedAverageDisplay(rows, col.key) ?: return@mapNotNull null
            col to display
        }
    }

    /**
     * Map a grade string to its 7-step numeric value. Non-scale values return null.
     * Trailing `*` (converted grades) is stripped before lookup.
     */
    fun gradeToNumber(raw: String): Double? {
        val cleaned = raw.trim().removeSuffix("*").trim()
        if (cleaned.isEmpty()) return null
        SEVEN_STEP[cleaned]?.let { return it }
        // Accept "7,0" / "7.0" only when they map to a known step
        val normalized = cleaned.replace(',', '.')
        val asDouble = normalized.toDoubleOrNull() ?: return null
        // Only exact 7-step values
        val asIntLike = if (asDouble == asDouble.toLong().toDouble()) {
            asDouble.toLong().toString()
        } else {
            return null
        }
        // Map 2→02, 0→00 for lookup
        return when (asIntLike) {
            "2" -> 2.0
            "0" -> 0.0
            else -> SEVEN_STEP[asIntLike]
        }
    }

    fun formatAverage(avg: Double): String =
        String.format(java.util.Locale.US, "%.2f", avg).replace('.', ',')

    /** Shorten ", Skriftlig" / ", Mundtlig" suffixes like iOS. */
    fun displaySubject(subject: String): String {
        val trimmed = subject.trim()
        val lower = trimmed.lowercase()
        if (lower.endsWith(", mundtlig")) {
            return trimmed.dropLast(", mundtlig".length).trimEnd() + " (M)"
        }
        if (lower.endsWith(", skriftlig")) {
            return trimmed.dropLast(", skriftlig".length).trimEnd() + " (S)"
        }
        return trimmed
    }

    /**
     * Progress 0…1 on Danish 7-trin scale (−3…12). Null if not a scale grade.
     */
    fun progressForGrade(value: String?): Float? {
        val n = value?.let { gradeToNumber(it) } ?: return null
        val clamped = n.coerceIn(-3.0, 12.0)
        return ((clamped + 3.0) / 15.0).toFloat()
    }

    /**
     * One representative grade per subject for distribution-style views:
     * most-final available cell.
     */
    fun representativeGrade(row: GradeRow): GradeCellValue? {
        for (key in REPRESENTATIVE_PRIORITY) {
            row.cell(key)?.let { return it }
        }
        return row.grades.values.firstOrNull()
    }

    fun notesForHold(notes: List<GradeNoteEntry>, hold: String): List<GradeNoteEntry> {
        val target = hold.trim()
        if (target.isEmpty()) return emptyList()
        return notes.filter { it.hold.trim().equals(target, ignoreCase = true) }
    }
}
