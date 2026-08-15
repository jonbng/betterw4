package dk.betterlectio.android.feature.widget

import dk.betterlectio.android.feature.schedule.EventStatus
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@Serializable
data class WidgetLesson(
    val id: String,
    val title: String,
    val startLabel: String,
    val timeRange: String,
    val room: String? = null,
    val status: String = EventStatus.NORMAL.name,
    val accentArgb: Long = 0xFF3362E1L,
    val startEpochMilli: Long? = null,
    val endEpochMilli: Long? = null,
    val isAllDay: Boolean = false,
)

@Serializable
data class WidgetSnapshot(
    val date: String,
    val dayLabel: String,
    val lessons: List<WidgetLesson> = emptyList(),
)

enum class WidgetFeaturedKind { CURRENT, NEXT }

enum class WidgetContentKind {
    /** No snapshot, or snapshot is for another day. */
    STALE,
    /** Snapshot for today with zero lessons. */
    FREE_DAY,
    /** Snapshot for today with lessons (may be finished). */
    CONTENT,
}

data class WidgetPresentation(
    val kind: WidgetContentKind,
    val dayLabel: String,
    val featuredKind: WidgetFeaturedKind? = null,
    val featured: WidgetLesson? = null,
    /** Lessons to list below the featured block (or the full day when nothing is featured). */
    val rows: List<WidgetLesson> = emptyList(),
)

object ScheduleWidgetCodec {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun encode(snapshot: WidgetSnapshot): String = json.encodeToString(snapshot)

    fun decode(raw: String?): WidgetSnapshot? {
        if (raw.isNullOrBlank()) return null
        return try {
            json.decodeFromString(WidgetSnapshot.serializer(), raw)
        } catch (_: Exception) {
            null
        }
    }
}

object ScheduleWidgetProjector {
    fun present(
        snapshot: WidgetSnapshot?,
        today: LocalDate = LocalDate.now(),
        nowEpochMilli: Long = System.currentTimeMillis(),
    ): WidgetPresentation {
        if (snapshot == null || snapshot.date != today.toString()) {
            return WidgetPresentation(
                kind = WidgetContentKind.STALE,
                dayLabel = snapshot?.dayLabel.orEmpty(),
            )
        }
        if (snapshot.lessons.isEmpty()) {
            return WidgetPresentation(
                kind = WidgetContentKind.FREE_DAY,
                dayLabel = snapshot.dayLabel,
            )
        }

        val ordered = snapshot.lessons
        val featuredPick = pickFeatured(ordered, nowEpochMilli)
        if (featuredPick == null) {
            return WidgetPresentation(
                kind = WidgetContentKind.CONTENT,
                dayLabel = snapshot.dayLabel,
                rows = ordered,
            )
        }
        val (kind, featured) = featuredPick
        val rows = ordered.filter { lesson ->
            if (lesson.id == featured.id) return@filter false
            val end = lesson.endEpochMilli
            when {
                lesson.isAllDay -> true
                end == null -> true
                else -> end > nowEpochMilli
            }
        }
        return WidgetPresentation(
            kind = WidgetContentKind.CONTENT,
            dayLabel = snapshot.dayLabel,
            featuredKind = kind,
            featured = featured,
            rows = rows,
        )
    }

    private fun pickFeatured(
        lessons: List<WidgetLesson>,
        nowEpochMilli: Long,
    ): Pair<WidgetFeaturedKind, WidgetLesson>? {
        val timed = lessons.filter { lesson ->
            !lesson.isAllDay &&
                lesson.status != EventStatus.CANCELLED.name &&
                lesson.startEpochMilli != null &&
                lesson.endEpochMilli != null &&
                lesson.endEpochMilli > lesson.startEpochMilli
        }

        val current = timed
            .filter {
                nowEpochMilli >= requireNotNull(it.startEpochMilli) &&
                    nowEpochMilli < requireNotNull(it.endEpochMilli)
            }
            .minByOrNull { it.startEpochMilli!! }
        if (current != null) return WidgetFeaturedKind.CURRENT to current

        val next = timed
            .filter { requireNotNull(it.startEpochMilli) > nowEpochMilli }
            .minByOrNull { it.startEpochMilli!! }
        return next?.let { WidgetFeaturedKind.NEXT to it }
    }

    fun startLabelFromEpoch(epochMilli: Long?, zoneId: ZoneId = ZoneId.systemDefault()): String? {
        if (epochMilli == null) return null
        val time = Instant.ofEpochMilli(epochMilli).atZone(zoneId).toLocalTime()
        return "%02d:%02d".format(time.hour, time.minute)
    }
}
