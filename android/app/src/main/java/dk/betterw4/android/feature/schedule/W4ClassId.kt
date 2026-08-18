package dk.betterw4.android.feature.schedule

/**
 * W4 class identifiers as printed on the timetable brick and in My classes.
 *
 * Live capture (nc26jban, Aug 2026): `1DA13HMTAA`, `1EA16CECOX`, `1YA25SLALI`,
 * `1ZAUDXCORE`. The compact code is:
 *
 *     {year}{block}{room}{level}{subject}
 *
 *     1 DA13 H MTAA  →  1st year, block D, room A 1.3, Higher, Mathematics AA
 *     1 EA16 C ECOX  →  1st year, block E, room A 1.6, C level, Economics
 *     1 ZAUD X CORE  →  1st year, block Z, Auditorium, X level, Core meetings
 *
 * The brick itself shows only this code. The real subject name lives in
 * `div.period[title]` as `Class: <b>Economics</b>` and in My classes as the
 * `<dt>` heading.
 *
 * Advisor groups use a first name (`Dona`, `Josef`) instead of this shape.
 */
data class W4ClassId(
    val raw: String,
    val year: Int,
    val block: String,
    val roomCode: String,
    val level: Char,
    val subjectCode: String,
) {
    val levelLabel: String
        get() = when (level.uppercaseChar()) {
            'H' -> "HL"
            'S' -> "SL"
            'C' -> "C"
            'X' -> "X"
            else -> level.toString()
        }

    companion object {
        private val PATTERN = Regex(
            """^(\d)([A-Za-z])([A-Za-z]{1,3}\d{0,2})([HSCXhscx])([A-Za-z]{3,5})$""",
        )

        fun parse(raw: String): W4ClassId? {
            val trimmed = raw.trim()
            val match = PATTERN.matchEntire(trimmed) ?: return null
            return W4ClassId(
                raw = trimmed,
                year = match.groupValues[1].toInt(),
                block = match.groupValues[2].uppercase(),
                roomCode = match.groupValues[3].uppercase(),
                level = match.groupValues[4].uppercase()[0],
                subjectCode = match.groupValues[5].uppercase(),
            )
        }

        fun looksLike(raw: String): Boolean = parse(raw) != null
    }
}
