package dk.betterw4.android.feature.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.MainActivity
import dk.betterw4.android.R
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.SchoolCalendar
import dk.betterw4.android.feature.settings.SettingsStore
import java.time.LocalDateTime
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Native Android Live Update for the current or imminently upcoming lesson.
 */
@Singleton
class LiveLessonNotifier @Inject constructor(
    @ApplicationContext private val context: Context,
    private val settings: SettingsStore,
) {
    private val nm = context.getSystemService(NotificationManager::class.java)
    private val notifId = 42

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    context.getString(R.string.live_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }

    fun update(events: List<ScheduleEvent>, now: LocalDateTime = W4Dates.now()) {
        val projection = LiveLessonBoundary.project(events, now)
        if (projection == null || !nm.areNotificationsEnabled()) {
            nm.cancel(notifId)
            return
        }

        val copy = LiveLessonPresentation.present(
            projection,
            subjectOf = ::friendlyTitle,
            nextLabel = { context.getString(R.string.live_next_line, it) },
        )
        val notification = when {
            Build.VERSION.SDK_INT >= 37 -> buildMetricLiveUpdate(projection, copy)
            Build.VERSION.SDK_INT >= 36 -> buildPromotedNotification(projection, copy)
            else -> buildCompatNotification(projection, copy)
        }
        try {
            nm.notify(notifId, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS can be revoked between the permission check and notify().
        }
    }

    fun clear() = nm.cancel(notifId)

    @RequiresApi(37)
    private fun buildMetricLiveUpdate(
        projection: LiveLessonBoundary.Projection,
        copy: LiveLessonCopy,
    ): Notification {
        val timer = Notification.Metric.TimeDifference.forTimer(
            projection.target.atZone(W4Dates.ZONE).toInstant(),
            Notification.Metric.TimeDifference.FORMAT_ADAPTIVE,
        )
        val metricLabel = context.getString(
            if (projection.phase == LiveLessonBoundary.Phase.CURRENT) {
                R.string.live_metric_ends_in
            } else {
                R.string.live_metric_starts_in
            },
        )
        val style = Notification.MetricStyle()
            .addMetric(Notification.Metric(timer, metricLabel))
            .setCriticalMetric(0)

        return basePlatformBuilder(projection, copy, metricOwnsCardTime = true)
            .setStyle(style)
            .build()
    }

    @RequiresApi(36)
    private fun buildPromotedNotification(
        projection: LiveLessonBoundary.Projection,
        copy: LiveLessonCopy,
    ): Notification {
        val builder = basePlatformBuilder(projection, copy, metricOwnsCardTime = false)
        copy.expandedText?.let { expanded ->
            // Promoted Live Updates stay expanded, so BigText must keep the
            // primary line (teacher / next) and only append leftover facts.
            builder.setStyle(Notification.BigTextStyle().bigText("${copy.text}\n$expanded"))
        }
        return builder.build()
    }

    @RequiresApi(36)
    private fun basePlatformBuilder(
        projection: LiveLessonBoundary.Projection,
        copy: LiveLessonCopy,
        metricOwnsCardTime: Boolean,
    ): Notification.Builder {
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(subjectColor(projection.event))
            .setContentTitle(copy.title)
            .setContentText(copy.text)
            .setContentIntent(openScheduleIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setRequestPromotedOngoing(true)
        applyTimeSurfaces(builder, projection, copy, metricOwnsCardTime)
        return builder
    }

    @RequiresApi(36)
    private fun applyTimeSurfaces(
        builder: Notification.Builder,
        projection: LiveLessonBoundary.Projection,
        copy: LiveLessonCopy,
        metricOwnsCardTime: Boolean,
    ) {
        val targetMillis = projection.target
            .atZone(W4Dates.ZONE)
            .toInstant()
            .toEpochMilli()
        builder.setWhen(targetMillis)
        copy.chipText?.let { builder.setShortCriticalText(it) }

        // MetricStyle already ticks on the card. Chronometer is only needed as the
        // card clock (pre-metric) or as the status chip when there is no room.
        val chronometerInCard = !metricOwnsCardTime
        val chronometerOnChip = copy.chipText == null
        val useChronometer = chronometerInCard || chronometerOnChip
        builder.setShowWhen(chronometerInCard)
        builder.setUsesChronometer(useChronometer)
        builder.setChronometerCountDown(useChronometer)
    }

    private fun buildCompatNotification(
        projection: LiveLessonBoundary.Projection,
        copy: LiveLessonCopy,
    ): Notification {
        val targetMillis = projection.target
            .atZone(W4Dates.ZONE)
            .toInstant()
            .toEpochMilli()
        val bigText = copy.expandedText?.let { "${copy.text}\n$it" } ?: copy.text
        return NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(subjectColor(projection.event))
            .setContentTitle(copy.title)
            .setContentText(copy.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setContentIntent(openScheduleIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setWhen(targetMillis)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .build()
    }

    private fun subjectColor(event: ScheduleEvent): Int =
        settings.accentArgbFor(event).toInt()

    private fun openScheduleIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun friendlyTitle(event: ScheduleEvent): String {
        if (SchoolCalendar.isSchoolCalendarEvent(event)) return event.title
        val key = event.team.ifBlank { event.title }
        return settings.displayNameForSubject(key, fallback = event.title.ifBlank { key })
    }

    companion object {
        private const val CHANNEL = "live_lesson"
    }
}
