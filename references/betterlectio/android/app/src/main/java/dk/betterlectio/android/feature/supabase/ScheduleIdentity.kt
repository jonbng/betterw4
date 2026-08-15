package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.feature.schedule.ScheduleEvent
import java.security.MessageDigest
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** iOS parity: `ScheduleIdentity` for Supabase lesson keys / week keys. */
object ScheduleIdentity {
    private val dayFormat: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE

    fun weekKey(year: Int, week: Int): String =
        "%04d-W%02d".format(year, week)

    fun weekKey(date: LocalDate): String {
        // ISO week fields
        val weekFields = java.time.temporal.WeekFields.ISO
        val year = date.get(weekFields.weekBasedYear())
        val week = date.get(weekFields.weekOfWeekBasedYear())
        return weekKey(year, week)
    }

    fun lessonKey(event: ScheduleEvent, studentId: String): String {
        if (event.id.isNotBlank()) return event.id

        val start = event.start?.let { "%02d:%02d".format(it.hour, it.minute) }.orEmpty()
        val end = event.end?.let { "%02d:%02d".format(it.hour, it.minute) }.orEmpty()
        val base = listOf(
            studentId,
            event.date.format(dayFormat),
            start.lowercase(Locale.US),
            end.lowercase(Locale.US),
            event.title.trim().lowercase(Locale.US),
            (event.teacher ?: "").trim().lowercase(Locale.US),
            (event.room ?: "").trim().lowercase(Locale.US),
            if (event.isAllDay) "allday" else "",
        ).joinToString("|")

        val digest = MessageDigest.getInstance("SHA-256").digest(base.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
