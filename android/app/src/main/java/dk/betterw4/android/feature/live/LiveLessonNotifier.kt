package dk.betterw4.android.feature.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.MainActivity
import dk.betterw4.android.R
import dk.betterw4.android.core.analytics.AppTelemetry
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
        runCatching {
            val projection = LiveLessonBoundary.project(events, now)
            if (projection == null || !nm.areNotificationsEnabled()) {
                nm.cancel(notifId)
                return@runCatching
            }

            val copy = LiveLessonPresentation.present(
                projection,
                subjectOf = ::friendlyTitle,
                nextLabel = { context.getString(R.string.live_next_line, it) },
            )

            // Platform Live Update APIs on Android 16/17 have caused startup-fatal
            // failures on some devices. Keep the stable compat notification until
            // the platform path can be reintroduced behind device-tested guards.
            nm.notify(notifId, buildCompatNotification(projection, copy))
        }.onFailure { error ->
            AppTelemetry.captureException(
                error,
                mapOf(
                    "operation" to "live_lesson_notification",
                    "sdk_int" to Build.VERSION.SDK_INT,
                ),
            )
        }
    }

    fun clear() {
        runCatching { nm.cancel(notifId) }.onFailure { error ->
            AppTelemetry.captureException(
                error,
                mapOf(
                    "operation" to "clear_live_lesson_notification",
                    "sdk_int" to Build.VERSION.SDK_INT,
                ),
            )
        }
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
