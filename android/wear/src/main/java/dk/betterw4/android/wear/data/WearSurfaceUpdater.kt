package dk.betterw4.android.wear.data

import android.content.ComponentName
import android.content.Context
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import dk.betterw4.android.wear.complication.ScheduleComplicationService
import dk.betterw4.android.wear.tile.ScheduleTileService

object WearSurfaceUpdater {
    fun requestUpdates(context: Context) {
        TileService.getUpdater(context)
            .requestUpdate(ScheduleTileService::class.java)
        ComplicationDataSourceUpdateRequester.create(
            context,
            ComponentName(context, ScheduleComplicationService::class.java),
        ).requestUpdateAll()
        WearBoundaryScheduler.schedule(context)
    }
}
