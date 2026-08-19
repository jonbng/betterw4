package dk.betterw4.android.feature.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import dk.betterw4.android.MainActivity
import dk.betterw4.android.R
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.homework.HomeworkRepository
import dk.betterw4.android.feature.live.LiveLessonNotifier
import dk.betterw4.android.feature.live.LiveLessonScheduler
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleRepository
import dk.betterw4.android.feature.settings.SettingsStore
import dk.betterw4.android.feature.trips.W4TripsRepository
import java.time.DayOfWeek
import java.util.concurrent.TimeUnit

class NotificationDiffWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface Deps {
        fun scheduleRepository(): ScheduleRepository
        fun homeworkRepository(): HomeworkRepository
        fun tripsRepository(): W4TripsRepository
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

        val settings = deps.settingsStore()
        val watchTimetable = settings.notifEvents.value
        val watchAssessments = settings.notifAssignments.value
        val watchTrips = settings.notifTrips.value
        if (!watchTimetable && !watchAssessments && !watchTrips) {
            return Result.success()
        }

        ensureChannel()
        val nm = applicationContext.getSystemService(NotificationManager::class.java)
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val snapKey = "snap_${student.studentId}"
        val previous = NotificationDiff.decode(prefs.getStringSet(snapKey, emptySet()).orEmpty())
        val now = W4Dates.now()
        val today = W4Dates.today()
        val ctx = applicationContext
        var nextLessons = previous.lessons
        var nextAssessments = previous.assessments
        var nextTrips = previous.trips
        var fetchedLessons = false
        var fetchedAssessments = false
        var fetchedTrips = false
        var notifId = 2000

        val scheduleResult = deps.scheduleRepository().loadWeek(forceRefresh = true)
        if (scheduleResult is AppResult.Failure && scheduleResult.error is AppError.Unauthorized) {
            return Result.success()
        }
        val weekEvents = mutableListOf<ScheduleEvent>()
        if (scheduleResult is AppResult.Success) {
            weekEvents += scheduleResult.data.days.flatMap { it.events }
            val todayEvents = scheduleResult.data.days.find { it.date == today }?.events.orEmpty()
            deps.liveLessonNotifier().update(todayEvents, now)
            deps.liveLessonScheduler().scheduleBoundaries(todayEvents, now)
        }
        if (needsNextWeek(now)) {
            val nextYearWeek = nextIsoWeek(now.toLocalDate())
            when (
                val next = deps.scheduleRepository().loadWeek(
                    year = nextYearWeek.first,
                    week = nextYearWeek.second,
                    forceRefresh = true,
                )
            ) {
                is AppResult.Success -> weekEvents += next.data.days.flatMap { it.events }
                is AppResult.Failure -> if (next.error is AppError.Unauthorized) return Result.success()
            }
        }
        if (watchTimetable) {
            nextLessons = NotificationDiff.watchLessons(weekEvents, now)
            fetchedLessons = scheduleResult is AppResult.Success
        }

        if (watchAssessments) {
            when (val homework = deps.homeworkRepository().load(forceRefresh = true)) {
                is AppResult.Success -> {
                    nextAssessments = NotificationDiff.watchAssessments(homework.data, today)
                    fetchedAssessments = true
                }
                is AppResult.Failure -> if (homework.error is AppError.Unauthorized) return Result.success()
            }
        }

        if (watchTrips) {
            when (val trips = deps.tripsRepository().load(force = true)) {
                is AppResult.Success -> {
                    nextTrips = NotificationDiff.watchTrips(trips.data.trips)
                    fetchedTrips = true
                }
                is AppResult.Failure -> if (trips.error is AppError.Unauthorized) return Result.success()
            }
        }

        val next = NotificationDiff.Snapshot(
            lessons = nextLessons,
            assessments = nextAssessments,
            trips = nextTrips,
        )
        val launch = launchIntent()
        val primedLessons = prefs.getBoolean("seeded_tt_${student.studentId}", false)
        val primedAssessments = prefs.getBoolean("seeded_asg_${student.studentId}", false)
        val primedTrips = prefs.getBoolean("seeded_trip_${student.studentId}", false)

        if (watchTimetable && primedLessons) {
            for (change in NotificationDiff.diffLessons(previous.lessons, nextLessons, now)) {
                val title = when (change.kind) {
                    NotificationDiff.LessonChangeKind.CANCELLED ->
                        ctx.getString(R.string.notif_lesson_cancelled)
                    NotificationDiff.LessonChangeKind.MOVED ->
                        ctx.getString(R.string.notif_lesson_moved)
                    NotificationDiff.LessonChangeKind.ROOM ->
                        ctx.getString(R.string.notif_lesson_room)
                    NotificationDiff.LessonChangeKind.CHANGED ->
                        ctx.getString(R.string.notif_lesson_changed)
                }
                val body = listOfNotNull(change.title, change.timeLabel, change.detail)
                    .filter { it.isNotBlank() }
                    .joinToString(" · ")
                notify(nm, notifId++, title, body, launch)
                settings.appendNotificationHistory("$title: ${change.title}")
            }
        }
        if (watchAssessments && primedAssessments) {
            for (change in NotificationDiff.diffAssessments(previous.assessments, nextAssessments)) {
                val title = when (change.kind) {
                    NotificationDiff.AssessmentChangeKind.NEW ->
                        ctx.getString(R.string.notif_assessment_new)
                    NotificationDiff.AssessmentChangeKind.OVERDUE ->
                        ctx.getString(R.string.notif_assessment_overdue)
                }
                val body = listOfNotNull(change.title, change.subtitle)
                    .filter { it.isNotBlank() }
                    .joinToString(" · ")
                notify(nm, notifId++, title, body, launch)
                settings.appendNotificationHistory("$title: ${change.title}")
            }
        }
        if (watchTrips && primedTrips) {
            for (change in NotificationDiff.diffTrips(previous.trips, nextTrips)) {
                val title = when (change.kind) {
                    NotificationDiff.TripChangeKind.NEW ->
                        ctx.getString(R.string.notif_trip_new)
                    NotificationDiff.TripChangeKind.STATUS ->
                        ctx.getString(R.string.notif_trip_status, tripStatusLabel(ctx, change.status))
                }
                notify(nm, notifId++, title, change.name, launch)
                settings.appendNotificationHistory("$title: ${change.name}")
            }
        }

        prefs.edit {
            putStringSet(snapKey, NotificationDiff.encode(next))
            if (fetchedLessons) putBoolean("seeded_tt_${student.studentId}", true)
            if (fetchedAssessments) putBoolean("seeded_asg_${student.studentId}", true)
            if (fetchedTrips) putBoolean("seeded_trip_${student.studentId}", true)
        }
        return Result.success()
    }

    private fun notify(
        nm: NotificationManager,
        id: Int,
        title: String,
        body: String,
        launch: PendingIntent,
    ) {
        val ctx = applicationContext
        try {
            nm.notify(
                id,
                NotificationCompat.Builder(ctx, CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(ContextCompat.getColor(ctx, R.color.brand_blue))
                    .setContentTitle(title)
                    .setContentText(body)
                    .setContentIntent(launch)
                    .setAutoCancel(true)
                    .build(),
            )
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS can be revoked between the check and notify().
        }
    }

    private fun launchIntent(): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(applicationContext, 0, intent, flags)
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
        const val CHANNEL_ID = "betterw4"
        private const val WORK_NAME = "bl_notif_poll"
        private const val PREFS = "notif_snapshots"

        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val req = PeriodicWorkRequestBuilder<NotificationDiffWorker>(15, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                req,
            )
        }

        internal fun needsNextWeek(now: java.time.LocalDateTime = W4Dates.now()): Boolean {
            val today = now.toLocalDate()
            val weekEnd = IsoDateUtils.weekStart(
                IsoDateUtils.isoWeekYear(today),
                IsoDateUtils.isoWeek(today),
            ).plusDays(7)
            return !now.plusHours(NotificationDiff.HORIZON_HOURS).toLocalDate().isBefore(weekEnd) ||
                today.dayOfWeek >= DayOfWeek.FRIDAY
        }

        internal fun nextIsoWeek(date: java.time.LocalDate): Pair<Int, Int> {
            val next = date.plusDays(7)
            return IsoDateUtils.isoWeekYear(next) to IsoDateUtils.isoWeek(next)
        }

        internal fun tripStatusLabel(context: Context, status: String): String = when (status) {
            "pending" -> context.getString(R.string.notif_trip_status_pending)
            "approved" -> context.getString(R.string.notif_trip_status_approved)
            "cancelled" -> context.getString(R.string.notif_trip_status_cancelled)
            "planning" -> context.getString(R.string.notif_trip_status_planning)
            else -> status
        }
    }
}
