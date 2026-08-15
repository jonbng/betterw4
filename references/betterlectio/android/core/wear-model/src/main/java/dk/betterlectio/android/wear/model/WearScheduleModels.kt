package dk.betterlectio.android.wear.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.ceil

@Serializable
enum class WearEventStatus { NORMAL, CHANGED, CANCELLED }

@Serializable
enum class WearSyncStatus { READY, AUTH_REQUIRED, ERROR }

@Serializable
data class WearScheduleEvent(
    val id: String,
    val title: String,
    val team: String = "",
    val teacher: String? = null,
    val room: String? = null,
    val status: WearEventStatus = WearEventStatus.NORMAL,
    val startEpochMillis: Long? = null,
    val endEpochMillis: Long? = null,
    val dateEpochDay: Long,
    val isAllDay: Boolean = false,
)

@Serializable
data class WearScheduleSnapshot(
    val schemaVersion: Int = WearScheduleProtocol.SCHEMA_VERSION,
    val generatedAtEpochMillis: Long,
    val validUntilEpochMillis: Long,
    val zoneId: String,
    val status: WearSyncStatus = WearSyncStatus.READY,
    val statusMessage: String? = null,
    val events: List<WearScheduleEvent> = emptyList(),
) {
    fun isStale(nowEpochMillis: Long): Boolean = nowEpochMillis > validUntilEpochMillis
}

enum class CountdownKind { CURRENT, NEXT, NONE }

data class WearCountdown(
    val kind: CountdownKind,
    val event: WearScheduleEvent? = null,
    val targetEpochMillis: Long? = null,
    val minutes: Long? = null,
    val progress: Float = 0f,
) {
    companion object {
        val None = WearCountdown(CountdownKind.NONE)
    }
}

object WearCountdownProjector {
    fun project(
        events: List<WearScheduleEvent>,
        nowEpochMillis: Long,
    ): WearCountdown {
        val timed = events
            .asSequence()
            .filter {
                !it.isAllDay &&
                    it.status != WearEventStatus.CANCELLED &&
                    it.startEpochMillis != null &&
                    it.endEpochMillis != null &&
                    it.endEpochMillis > it.startEpochMillis
            }
            .sortedWith(compareBy({ it.startEpochMillis }, { it.endEpochMillis }, { it.id }))
            .toList()

        val current = timed
            .filter {
                nowEpochMillis >= requireNotNull(it.startEpochMillis) &&
                    nowEpochMillis < requireNotNull(it.endEpochMillis)
            }
            .minWithOrNull(compareBy({ it.endEpochMillis }, { it.startEpochMillis }, { it.id }))

        if (current != null) {
            val start = requireNotNull(current.startEpochMillis)
            val end = requireNotNull(current.endEpochMillis)
            val duration = (end - start).coerceAtLeast(1L)
            return WearCountdown(
                kind = CountdownKind.CURRENT,
                event = current,
                targetEpochMillis = end,
                minutes = minutesUntil(nowEpochMillis, end),
                progress = ((nowEpochMillis - start).toFloat() / duration)
                    .coerceIn(0f, 1f),
            )
        }

        val next = timed.firstOrNull { requireNotNull(it.startEpochMillis) > nowEpochMillis }
            ?: return WearCountdown.None
        val start = requireNotNull(next.startEpochMillis)
        return WearCountdown(
            kind = CountdownKind.NEXT,
            event = next,
            targetEpochMillis = start,
            minutes = minutesUntil(nowEpochMillis, start),
        )
    }

    private fun minutesUntil(nowEpochMillis: Long, targetEpochMillis: Long): Long =
        ceil((targetEpochMillis - nowEpochMillis).coerceAtLeast(0L) / 60_000.0).toLong()
}

object WearScheduleProtocol {
    const val SCHEMA_VERSION = 1
    const val SNAPSHOT_PATH = "/betterlectio/schedule/v1"
    const val REFRESH_PATH = "/betterlectio/schedule/refresh/v1"
    const val SNAPSHOT_JSON_KEY = "snapshot_json"
}

object WearScheduleCodec {
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    fun encode(snapshot: WearScheduleSnapshot): String =
        json.encodeToString(WearScheduleSnapshot.serializer(), snapshot)

    fun decode(encoded: String): WearScheduleSnapshot =
        json.decodeFromString(WearScheduleSnapshot.serializer(), encoded)
}
