package dk.betterlectio.android.wear.complication

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountDownTimeReference
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.NoDataComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import dk.betterlectio.android.wear.MainActivity
import dk.betterlectio.android.wear.R
import dk.betterlectio.android.wear.data.WearScheduleRepository
import dk.betterlectio.android.wear.model.CountdownKind
import dk.betterlectio.android.wear.model.WearCountdownProjector
import java.time.Instant
import java.util.concurrent.TimeUnit

class ScheduleComplicationService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData {
        val events = WearScheduleRepository(applicationContext).read().schedule?.events.orEmpty()
        val countdown = WearCountdownProjector.project(events, System.currentTimeMillis())
        val event = countdown.event ?: return NoDataComplicationData()
        val target = countdown.targetEpochMillis ?: return NoDataComplicationData()
        val timedText = TimeDifferenceComplicationText.Builder(
            style = TimeDifferenceStyle.SHORT_SINGLE_UNIT,
            countDownTimeReference = CountDownTimeReference(Instant.ofEpochMilli(target)),
        )
            .setMinimumTimeUnit(TimeUnit.MINUTES)
            .build()
        val description = PlainComplicationText.Builder(
            when (countdown.kind) {
                CountdownKind.CURRENT ->
                    getString(R.string.ends_in, countdown.minutes ?: 0)
                CountdownKind.NEXT ->
                    getString(R.string.starts_in, countdown.minutes ?: 0)
                CountdownKind.NONE -> getString(R.string.no_more_classes)
            } + ": ${event.title}",
        ).build()
        val title = PlainComplicationText.Builder(event.title).build()

        return when (request.complicationType) {
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(
                text = timedText,
                contentDescription = description,
            )
                .setTitle(title)
                .setTapAction(openAppAction())
                .build()
            else -> ShortTextComplicationData.Builder(
                text = timedText,
                contentDescription = description,
            )
                .setTitle(title)
                .setTapAction(openAppAction())
                .build()
        }
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData {
        val text = PlainComplicationText.Builder("12m").build()
        val description = PlainComplicationText.Builder(
            getString(R.string.complication_label),
        ).build()
        return when (type) {
            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(text, description)
                .setTitle(PlainComplicationText.Builder("Mathematics").build())
                .build()
            else -> ShortTextComplicationData.Builder(text, description)
                .setTitle(PlainComplicationText.Builder("Math").build())
                .build()
        }
    }

    private fun openAppAction(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}
