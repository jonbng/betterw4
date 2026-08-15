package dk.betterw4.android.feature.schedule

import java.time.LocalDate
import java.time.LocalDateTime

/**
 * Lectio tooltip leftovers used by multi-day tests. W4 timetables use [W4TimetableParser].
 */
object ScheduleParser {
    data class TooltipFields(
        val start: LocalDateTime?,
        val end: LocalDateTime?,
        val title: String? = null,
        val isAllDay: Boolean = false,
    )

    fun parseTooltip(tooltip: String, @Suppress("UNUSED_PARAMETER") date: LocalDate): TooltipFields {
        val match = RANGE.find(tooltip)
        if (match == null) {
            return TooltipFields(start = null, end = null, title = tooltip.lines().firstOrNull())
        }
        val (d1, m1, y1, h1, min1, d2, m2, y2, h2, min2) = match.destructured
        return TooltipFields(
            start = LocalDateTime.of(y1.toInt(), m1.toInt(), d1.toInt(), h1.toInt(), min1.toInt()),
            end = LocalDateTime.of(y2.toInt(), m2.toInt(), d2.toInt(), h2.toInt(), min2.toInt()),
            title = tooltip.lines().firstOrNull { it.isNotBlank() },
        )
    }

    private val RANGE = Regex(
        """(\d{1,2})/(\d{1,2})-(\d{4})\s+(\d{2}):(\d{2})\s+til\s+(\d{1,2})/(\d{1,2})-(\d{4})\s+(\d{2}):(\d{2})""",
    )
}
