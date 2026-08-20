package dk.betterw4.android.feature.live

import dk.betterw4.android.feature.schedule.ScheduleEvent
import java.time.LocalDateTime

/**
 * Glanceable copy for the live-lesson notification.
 *
 * One fact per slot so lock screen / shade / status chip never repeat:
 * - [title]: subject · room
 * - [text]: teacher, else next lesson, else clock range
 * - [expandedText]: leftover facts (never repeats [text])
 * - [chipText]: room, truncated for the Live Update status chip
 */
data class LiveLessonCopy(
    val title: String,
    val text: String,
    val expandedText: String?,
    val chipText: String?,
)

object LiveLessonPresentation {
    const val CHIP_MAX_CHARS = 7

    fun present(
        projection: LiveLessonBoundary.Projection,
        subjectOf: (ScheduleEvent) -> String,
        nextLabel: (String) -> String,
    ): LiveLessonCopy {
        val event = projection.event
        val subject = subjectOf(event)
        val room = event.room.clean()
        val teacher = event.teacher.clean()
        val range = timeRange(event)
        val next = projection.nextLesson?.let { nextEvent ->
            val summary = listOfNotNull(
                subjectOf(nextEvent),
                nextEvent.room.clean(),
                clock(nextEvent.start),
            ).joinToString(" · ")
            nextLabel(summary)
        }

        val title = if (room != null) "$subject · $room" else subject
        val text = teacher ?: next ?: range.orEmpty()
        val expanded = listOfNotNull(range, next).filter { it.isNotEmpty() && it != text }
        return LiveLessonCopy(
            title = title,
            text = text,
            expandedText = expanded.takeIf { it.isNotEmpty() }?.joinToString("\n"),
            chipText = room?.let(::chipRoom),
        )
    }

    fun chipRoom(room: String): String {
        val first = room.split(" / ", "/", ",", " · ").first().trim()
        return first.take(CHIP_MAX_CHARS)
    }

    private fun String?.clean(): String? = this?.trim()?.takeIf { it.isNotEmpty() }

    private fun timeRange(event: ScheduleEvent): String? {
        val start = event.start ?: return null
        val end = event.end ?: return null
        return "${clock(start)} – ${clock(end)}"
    }

    private fun clock(at: LocalDateTime?): String? =
        at?.let { "%02d:%02d".format(it.hour, it.minute) }
}
