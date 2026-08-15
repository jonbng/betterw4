package dk.betterlectio.android.feature.live

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import timber.log.Timber
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Schedules boundary refreshes at lesson start/end via AlarmManager + WorkManager fallback.
 */
@Singleton
class LiveLessonScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    fun scheduleBoundaries(
        events: List<ScheduleEvent>,
        now: LocalDateTime = LocalDateTime.now(),
    ) {
        val next = LiveLessonBoundary.nextRefreshBoundary(events, now) ?: run {
            cancel()
            return
        }
        val delayMs = java.time.Duration.between(now, next.at).toMillis().coerceAtLeast(1_000L)
        // Cap to 12h so we recompute often enough
        val workDelay = delayMs.coerceAtMost(TimeUnit.HOURS.toMillis(12))

        val data = workDataOf(
            LiveLessonRefreshWorker.KEY_EVENT_ID to next.eventId,
            LiveLessonRefreshWorker.KEY_KIND to next.kind.name,
            LiveLessonRefreshWorker.KEY_TITLE to next.title,
        )
        val req = OneTimeWorkRequestBuilder<LiveLessonRefreshWorker>()
            .setInitialDelay(workDelay, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .addTag(WORK_TAG)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            req,
        )

        // Exact-ish alarm for faster wake when permitted
        try {
            val am = context.getSystemService(AlarmManager::class.java) ?: return
            val pi = alarmIntent()
            val triggerAt = next.at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        } catch (e: Exception) {
            Timber.w(e, "Live lesson alarm schedule failed; WorkManager only")
        }
    }

    fun cancel() {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        am.cancel(alarmIntent())
    }

    private fun alarmIntent(): PendingIntent = PendingIntent.getBroadcast(
        context,
        ALARM_REQUEST_CODE,
        Intent(context, LiveLessonAlarmReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val WORK_NAME = "live_lesson_boundary"
        const val WORK_TAG = "live_lesson"
        private const val ALARM_REQUEST_CODE = 4401
    }
}
