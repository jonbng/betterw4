package dk.betterlectio.android.feature.wear

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.ScheduleWeek
import dk.betterlectio.android.wear.model.WearEventStatus
import dk.betterlectio.android.wear.model.WearScheduleCodec
import dk.betterlectio.android.wear.model.WearScheduleEvent
import dk.betterlectio.android.wear.model.WearScheduleProtocol
import dk.betterlectio.android.wear.model.WearScheduleSnapshot
import dk.betterlectio.android.wear.model.WearSyncStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PhoneWearSchedulePublisher @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    fun publishWeeks(
        weeks: Collection<ScheduleWeek>,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ) {
        publish(PhoneWearScheduleMapper.snapshot(weeks, now, zoneId))
    }

    fun publishStatus(
        status: WearSyncStatus,
        message: String? = null,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ) {
        publish(
            WearScheduleSnapshot(
                generatedAtEpochMillis = now.toEpochMilli(),
                validUntilEpochMillis = now.plusSeconds(STATUS_TTL_SECONDS).toEpochMilli(),
                zoneId = zoneId.id,
                status = status,
                statusMessage = message,
            ),
        )
    }

    private fun publish(snapshot: WearScheduleSnapshot) {
        val request = PutDataMapRequest.create(WearScheduleProtocol.SNAPSHOT_PATH).apply {
            dataMap.putString(
                WearScheduleProtocol.SNAPSHOT_JSON_KEY,
                WearScheduleCodec.encode(snapshot),
            )
            dataMap.putLong("generated_at", snapshot.generatedAtEpochMillis)
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(context).putDataItem(request)
    }

    private companion object {
        const val STATUS_TTL_SECONDS = 6 * 60 * 60L
    }
}

internal object PhoneWearScheduleMapper {
    private const val SNAPSHOT_DAYS = 7L

    fun snapshot(
        weeks: Collection<ScheduleWeek>,
        now: Instant,
        zoneId: ZoneId,
    ): WearScheduleSnapshot {
        val today = LocalDate.ofInstant(now, zoneId)
        val through = today.plusDays(SNAPSHOT_DAYS)
        val events = weeks
            .flatMap { week -> week.days.flatMap { it.events } }
            .filter { it.date in today..through }
            .distinctBy { it.id to it.start }
            .sortedWith(compareBy({ it.date }, { it.start }, { it.id }))
            .map { it.toWearEvent(zoneId) }
        return WearScheduleSnapshot(
            generatedAtEpochMillis = now.toEpochMilli(),
            validUntilEpochMillis = through
                .plusDays(1)
                .atStartOfDay(zoneId)
                .toInstant()
                .toEpochMilli(),
            zoneId = zoneId.id,
            events = events,
        )
    }

    private fun ScheduleEvent.toWearEvent(zoneId: ZoneId) = WearScheduleEvent(
        id = id,
        title = title,
        team = team,
        teacher = teacher,
        room = room,
        status = when (status) {
            EventStatus.NORMAL -> WearEventStatus.NORMAL
            EventStatus.CHANGED -> WearEventStatus.CHANGED
            EventStatus.CANCELLED -> WearEventStatus.CANCELLED
        },
        startEpochMillis = start?.atZone(zoneId)?.toInstant()?.toEpochMilli(),
        endEpochMillis = end?.atZone(zoneId)?.toInstant()?.toEpochMilli(),
        dateEpochDay = date.toEpochDay(),
        isAllDay = isAllDay,
    )
}
