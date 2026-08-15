package dk.betterlectio.android.wear.tile

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.protolayout.TimelineBuilders.Timeline
import androidx.wear.protolayout.layout.column
import androidx.wear.protolayout.material3.MaterialScope
import androidx.wear.protolayout.material3.primaryLayout
import androidx.wear.protolayout.material3.text
import androidx.wear.protolayout.material3.textEdgeButton
import androidx.wear.protolayout.modifiers.clickable
import androidx.wear.protolayout.types.layoutString
import androidx.wear.tiles.Material3TileService
import androidx.wear.tiles.RequestBuilders.TileRequest
import androidx.wear.tiles.TileBuilders.Tile
import androidx.wear.tiles.tile
import dk.betterlectio.android.wear.MainActivity
import dk.betterlectio.android.wear.R
import dk.betterlectio.android.wear.data.WearScheduleRepository
import dk.betterlectio.android.wear.model.CountdownKind
import dk.betterlectio.android.wear.model.WearCountdownProjector
import dk.betterlectio.android.wear.model.WearScheduleEvent
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.time.Duration.Companion.minutes

class ScheduleTileService : Material3TileService() {
    override suspend fun MaterialScope.tileResponse(requestParams: TileRequest): Tile {
        val cached = WearScheduleRepository(applicationContext).read()
        val events = cached.schedule?.events.orEmpty()
        val now = System.currentTimeMillis()
        val countdown = WearCountdownProjector.project(events, now)
        val mainLines = buildList {
            add(
                when (countdown.kind) {
                    CountdownKind.CURRENT ->
                        getString(R.string.ends_in, countdown.minutes ?: 0)
                    CountdownKind.NEXT ->
                        getString(R.string.starts_in, countdown.minutes ?: 0)
                    CountdownKind.NONE -> getString(R.string.no_more_classes)
                },
            )
            countdown.event?.title?.let(::add)
            events.asSequence()
                .filter { (it.endEpochMillis ?: Long.MAX_VALUE) > now }
                .filterNot { it.id == countdown.event?.id }
                .sortedBy { it.startEpochMillis ?: Long.MAX_VALUE }
                .take(2)
                .map { it.tileLine(cached.schedule?.zoneId) }
                .forEach(::add)
        }
        val openAction = protoLayoutScope.clickable(
            pendingIntent = PendingIntent.getActivity(
                this@ScheduleTileService,
                0,
                Intent(this@ScheduleTileService, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
            id = "open_schedule",
        )

        val layout = primaryLayout(
            titleSlot = { text("BetterLectio".layoutString) },
            mainSlot = {
                column(
                    *mainLines.map { line -> text(line.layoutString) }.toTypedArray(),
                )
            },
            bottomSlot = {
                textEdgeButton(
                    onClick = openAction,
                    labelContent = { text(getString(R.string.schedule).layoutString) },
                )
            },
        )
        return tile(
            timeline = Timeline.fromLayoutElement(layout),
            freshness = 1.minutes,
        )
    }

    private fun WearScheduleEvent.tileLine(zoneId: String?): String {
        val time = startEpochMillis?.let { epoch ->
            DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
                .withLocale(Locale.getDefault())
                .withZone(runCatching { ZoneId.of(zoneId) }.getOrDefault(ZoneId.systemDefault()))
                .format(Instant.ofEpochMilli(epoch))
        }.orEmpty()
        return listOf(time, title).filter { it.isNotBlank() }.joinToString(" · ")
    }
}
