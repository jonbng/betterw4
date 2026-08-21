package dk.betterw4.android.feature.schedule

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import timber.log.Timber
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Device-local custom timetable events. W4 has no private-appointment form, so
 * these never leave the phone. Scoped per student so two accounts on one device
 * cannot see each other's events. Survives logout and cache clear on purpose —
 * they are user data, not a W4 page cache.
 */
@Singleton
class CustomEventStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(studentId: String): List<ScheduleEvent> {
        val raw = prefs.getString(key(studentId), null) ?: return emptyList()
        return decode(raw)
    }

    fun save(studentId: String, events: List<ScheduleEvent>) {
        prefs.edit {
            putString(key(studentId), encode(events))
        }
    }

    companion object {
        private const val PREFS = "bw4_custom_events"
        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        fun key(studentId: String): String = "events::$studentId"

        fun encode(events: List<ScheduleEvent>): String =
            json.encodeToString(events.mapNotNull(StoredCustomEvent::from))

        fun decode(raw: String): List<ScheduleEvent> = runCatching {
            json.decodeFromString<List<StoredCustomEvent>>(raw).map { it.toScheduleEvent() }
        }.getOrElse { error ->
            Timber.w(error, "Failed to decode custom events")
            emptyList()
        }
    }
}

@Serializable
data class StoredCustomEvent(
    val id: String,
    val title: String,
    val notes: String? = null,
    val start: String,
    val end: String,
    val isAllDay: Boolean = false,
) {
    fun toScheduleEvent(): ScheduleEvent {
        val startAt = parseDateTime(start)
        val endAt = parseDateTime(end) ?: startAt
        return ScheduleEvent(
            id = id,
            title = title,
            team = PRIVATE_EVENT_TEAM_TOKEN,
            notes = notes?.ifBlank { null },
            start = startAt,
            end = endAt,
            date = startAt?.toLocalDate() ?: java.time.LocalDate.now(),
            isAllDay = isAllDay,
            source = CustomEvents.SOURCE,
        )
    }

    companion object {
        private val iso = DateTimeFormatter.ISO_LOCAL_DATE_TIME

        fun from(event: ScheduleEvent): StoredCustomEvent? {
            val start = event.start ?: return null
            val end = event.end ?: start
            return StoredCustomEvent(
                id = event.id,
                title = event.title,
                notes = event.notes,
                start = iso.format(start),
                end = iso.format(end),
                isAllDay = event.isAllDay,
            )
        }

        private fun parseDateTime(raw: String): LocalDateTime? =
            runCatching { LocalDateTime.parse(raw, iso) }.getOrNull()
    }
}

/** Identity for device-local custom events (not W4, not the college calendar). */
object CustomEvents {
    const val SOURCE = "local"
    const val ID_PREFIX = "local-"
    const val ARGB = 0xFF5E35B1L

    fun isCustomEvent(event: ScheduleEvent): Boolean {
        if (event.source.equals(SOURCE, ignoreCase = true)) return true
        if (event.id.startsWith(ID_PREFIX, ignoreCase = true)) return true
        if (event.team.equals(PRIVATE_EVENT_TEAM_TOKEN, ignoreCase = true)) return true
        return false
    }

    /** Next 15-minute slot on [date]; 08:00 when [date] is not today. */
    fun defaultStart(
        date: java.time.LocalDate,
        now: java.time.LocalDateTime,
    ): java.time.LocalDateTime {
        if (date != now.toLocalDate()) return date.atTime(8, 0)
        return roundUpToQuarter(now)
    }

    fun roundUpToQuarter(now: java.time.LocalDateTime): java.time.LocalDateTime {
        val base = now.withSecond(0).withNano(0)
        val rem = base.minute % 15
        val rounded = if (rem == 0 && now.second == 0 && now.nano == 0) {
            base.plusMinutes(15)
        } else {
            base.plusMinutes((15 - rem).toLong())
        }
        return if (rounded.toLocalDate() != now.toLocalDate()) {
            now.toLocalDate().atTime(23, 45)
        } else {
            rounded
        }
    }
}
