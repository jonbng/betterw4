package dk.betterlectio.android.feature.live

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
import dk.betterlectio.android.MainActivity
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.settings.SettingsStore
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId
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

    fun update(events: List<ScheduleEvent>, now: LocalDateTime = LocalDateTime.now()) {
        val projection = LiveLessonBoundary.project(events, now)
        if (projection == null || !nm.areNotificationsEnabled()) {
            nm.cancel(notifId)
            return
        }

        val notification = when {
            Build.VERSION.SDK_INT >= 37 -> buildMetricLiveUpdate(projection)
            Build.VERSION.SDK_INT >= 36 -> buildProgressLiveUpdate(projection, now)
            else -> buildCompatNotification(projection)
        }
        try {
            nm.notify(notifId, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS can be revoked between the permission check and notify().
        }
    }

    fun clear() = nm.cancel(notifId)

    @RequiresApi(37)
    private fun buildMetricLiveUpdate(projection: LiveLessonBoundary.Projection): Notification {
        val timer = Notification.Metric.TimeDifference.forTimer(
            projection.target.atZone(ZoneId.systemDefault()).toInstant(),
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

        return basePlatformBuilder(projection)
            .setStyle(style)
            .build()
    }

    @RequiresApi(36)
    private fun buildProgressLiveUpdate(
        projection: LiveLessonBoundary.Projection,
        now: LocalDateTime,
    ): Notification {
        val style = Notification.ProgressStyle()
        if (projection.phase == LiveLessonBoundary.Phase.CURRENT) {
            val start = projection.event.start!!
            val end = projection.event.end!!
            val max = Duration.between(start, end).seconds.coerceIn(1L, Int.MAX_VALUE.toLong()).toInt()
            val elapsed = Duration.between(start, now).seconds.coerceIn(0L, max.toLong()).toInt()
            style
                .setProgressSegments(
                    listOf(
                        Notification.ProgressStyle.Segment(max)
                            .setColor(settings.colorForSubject(projection.event.team.ifBlank { projection.event.title }).toInt()),
                    ),
                )
                .setProgress(elapsed)
                .setStyledByProgress(true)
        } else {
            style.setProgressIndeterminate(true)
        }

        return basePlatformBuilder(projection)
            .setStyle(style)
            .build()
    }

    @RequiresApi(36)
    private fun basePlatformBuilder(projection: LiveLessonBoundary.Projection): Notification.Builder {
        val targetMillis = projection.target
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        return Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(subjectColor(projection.event))
            .setContentTitle(friendlyTitle(projection.event))
            .setContentText(detailText(projection))
            .setSubText(stateLabel(projection))
            .setContentIntent(openScheduleIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setRequestPromotedOngoing(true)
            .setWhen(targetMillis)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .addAction(0, context.getString(R.string.live_open_schedule), openScheduleIntent())
    }

    private fun buildCompatNotification(projection: LiveLessonBoundary.Projection): Notification {
        val targetMillis = projection.target
            .atZone(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        val bigText = buildString {
            append(detailText(projection))
            projection.event.teacher?.takeIf { it.isNotBlank() }?.let {
                appendLine()
                append(context.getString(R.string.live_teacher_line, it))
            }
            projection.nextLesson?.let {
                appendLine()
                append(
                    context.getString(
                        R.string.live_next_line,
                        friendlyTitle(it),
                        clockLabel(it.start),
                    ),
                )
            }
        }
        return NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(subjectColor(projection.event))
            .setContentTitle(friendlyTitle(projection.event))
            .setContentText(detailText(projection))
            .setSubText(stateLabel(projection))
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
            .addAction(0, context.getString(R.string.live_open_schedule), openScheduleIntent())
            .build()
    }

    private fun stateLabel(projection: LiveLessonBoundary.Projection): String =
        context.getString(
            if (projection.phase == LiveLessonBoundary.Phase.CURRENT) {
                R.string.live_lesson_in_progress
            } else {
                R.string.live_lesson_upcoming
            },
        )

    private fun detailText(projection: LiveLessonBoundary.Projection): String {
        val details = listOfNotNull(
            projection.event.room?.takeIf { it.isNotBlank() },
            projection.event.teacher?.takeIf { it.isNotBlank() },
        ).joinToString(" · ")
        return details.ifBlank {
            context.getString(
                if (projection.phase == LiveLessonBoundary.Phase.CURRENT) {
                    R.string.live_ends_at
                } else {
                    R.string.live_starts_at
                },
                clockLabel(projection.target),
            )
        }
    }

    private fun subjectColor(event: ScheduleEvent): Int {
        val key = event.team.ifBlank { event.title }
        return settings.colorForSubject(key).toInt()
    }

    private fun openScheduleIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun clockLabel(at: LocalDateTime?): String =
        at?.let { "%02d:%02d".format(it.hour, it.minute) }.orEmpty()

    private fun friendlyTitle(event: ScheduleEvent): String {
        val key = event.team.ifBlank { event.title }
        return settings.displayNameForSubject(key, fallback = event.title.ifBlank { key })
    }

    companion object {
        private const val CHANNEL = "live_lesson"
    }
}
