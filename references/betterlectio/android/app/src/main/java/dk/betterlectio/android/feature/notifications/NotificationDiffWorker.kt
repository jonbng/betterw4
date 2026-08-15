package dk.betterlectio.android.feature.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import dk.betterlectio.android.R
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.assignments.AssignmentRepository
import dk.betterlectio.android.feature.live.LiveLessonNotifier
import dk.betterlectio.android.feature.live.LiveLessonScheduler
import dk.betterlectio.android.feature.messages.MessageFolder
import dk.betterlectio.android.feature.messages.MessageRepository
import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleRepository
import dk.betterlectio.android.feature.schedule.statusLabel
import dk.betterlectio.android.feature.schedule.timeLabel
import dk.betterlectio.android.feature.settings.SettingsStore
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.concurrent.TimeUnit
import java.util.Locale

class NotificationDiffWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface Deps {
        fun scheduleRepository(): ScheduleRepository
        fun messageRepository(): MessageRepository
        fun assignmentRepository(): AssignmentRepository
        fun settingsStore(): SettingsStore
        fun sessionController(): SessionController
        fun liveLessonNotifier(): LiveLessonNotifier
        fun liveLessonScheduler(): LiveLessonScheduler
    }

    override suspend fun doWork(): Result {
        val deps = EntryPointAccessors.fromApplication(
            applicationContext,
            Deps::class.java,
        )
        val session = deps.sessionController()
        val student = session.currentStudent
        if (student == null || student.isDemo) return Result.success()

        ensureChannel()
        val nm = applicationContext.getSystemService(NotificationManager::class.java)
        val settings = deps.settingsStore()
        val prefs = applicationContext.getSharedPreferences("notif_snapshots", Context.MODE_PRIVATE)
        val snapKey = "snap_${student.studentId}"
        val previous = prefs.getStringSet(snapKey, emptySet())?.toSet().orEmpty()
        val next = previous.toMutableSet()
        var notifId = 1000
        val ctx = applicationContext
        val scheduleResult = deps.scheduleRepository().loadWeek(forceRefresh = true)
        if (scheduleResult is AppResult.Success) {
            val todayEvents = scheduleResult.data.days
                .find { it.date == LocalDate.now() }
                ?.events
                .orEmpty()
            val now = LocalDateTime.now()
            deps.liveLessonNotifier().update(todayEvents, now)
            deps.liveLessonScheduler().scheduleBoundaries(todayEvents, now)
        }

        if (settings.notifEvents.value) {
            when (val week = scheduleResult) {
                is AppResult.Success -> {
                    val changed = week.data.days.flatMap { it.events }
                        .filter { it.status != EventStatus.NORMAL }
                    val keys = changed.map {
                        NotificationSnapshotDiff.eventKey(it.id, it.status.name)
                    }.toSet()
                    val fresh = NotificationSnapshotDiff.newIds(previous, keys)
                    changed.filter { NotificationSnapshotDiff.eventKey(it.id, it.status.name) in fresh }
                        .take(5)
                        .forEach { ev ->
                            val status = ev.statusLabel(ctx)?.lowercase(Locale.getDefault())
                                ?: ctx.getString(R.string.notif_module_changed_fallback)
                            val title = ctx.getString(R.string.notif_module_status, status)
                            val body = ctx.getString(
                                R.string.notif_event_line,
                                ev.title,
                                ev.timeLabel(ctx),
                            )
                            nm.notify(
                                notifId++,
                                NotificationCompat.Builder(ctx, CHANNEL_ID)
                                    .setSmallIcon(R.drawable.ic_notification)
                                    .setColor(ContextCompat.getColor(ctx, R.color.brand_blue))
                                    .setContentTitle(title)
                                    .setContentText(body)
                                    .setAutoCancel(true)
                                    .build(),
                            )
                            settings.appendNotificationHistory(
                                ctx.getString(R.string.notif_history_module, title, ev.title),
                            )
                        }
                    next += keys
                }
                else -> Unit
            }
        }

        if (settings.notifMessages.value) {
            when (val folder = deps.messageRepository().loadFolder(MessageFolder.UNREAD, forceRefresh = true)) {
                is AppResult.Success -> {
                    val keys = folder.data.map { NotificationSnapshotDiff.messageKey(it.id) }.toSet()
                    val fresh = NotificationSnapshotDiff.newIds(previous, keys)
                    if (fresh.isNotEmpty()) {
                        nm.notify(
                            notifId++,
                            NotificationCompat.Builder(ctx, CHANNEL_ID)
                                .setSmallIcon(R.drawable.ic_notification)
                                .setColor(ContextCompat.getColor(ctx, R.color.brand_blue))
                                .setContentTitle(ctx.getString(R.string.notif_new_messages_title))
                                .setContentText(
                                    ctx.getString(R.string.notif_new_messages_body, fresh.size),
                                )
                                .setAutoCancel(true)
                                .build(),
                        )
                        settings.appendNotificationHistory(
                            ctx.getString(R.string.notif_history_new_messages, fresh.size),
                        )
                    }
                    next += keys
                }
                else -> Unit
            }
        }

        if (settings.notifAssignments.value) {
            when (val a = deps.assignmentRepository().load(forceRefresh = true)) {
                is AppResult.Success -> {
                    val keys = a.data.map {
                        NotificationSnapshotDiff.assignmentKey(it.id, it.status)
                    }.toSet()
                    val fresh = NotificationSnapshotDiff.newIds(previous, keys)
                    a.data.filter {
                        NotificationSnapshotDiff.assignmentKey(it.id, it.status) in fresh
                    }.take(3).forEach { item ->
                        nm.notify(
                            notifId++,
                            NotificationCompat.Builder(ctx, CHANNEL_ID)
                                .setSmallIcon(R.drawable.ic_notification)
                                .setColor(ContextCompat.getColor(ctx, R.color.brand_blue))
                                .setContentTitle(ctx.getString(R.string.notif_assignment_title, item.title))
                                .setContentText(
                                    ctx.getString(R.string.notif_assignment_body, item.team, item.status),
                                )
                                .setAutoCancel(true)
                                .build(),
                        )
                        settings.appendNotificationHistory(
                            ctx.getString(R.string.notif_history_assignment, item.status, item.title),
                        )
                    }
                    next += keys
                }
                else -> Unit
            }
        }

        prefs.edit { putStringSet(snapKey, next) }
        return Result.success()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = applicationContext.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    applicationContext.getString(R.string.notif_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
    }

    companion object {
        const val CHANNEL_ID = "betterlectio"
        private const val WORK_NAME = "bl_notif_poll"

        fun enqueue(context: Context) {
            val req = PeriodicWorkRequestBuilder<NotificationDiffWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                req,
            )
        }
    }
}
