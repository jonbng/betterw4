package dk.betterw4.android.feature.live

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.schedule.ScheduleRepository

class LiveLessonRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val entry = EntryPointAccessors.fromApplication(
            applicationContext,
            LiveLessonEntryPoint::class.java,
        )
        val scheduleRepository = entry.scheduleRepository()
        val notifier = entry.liveLessonNotifier()
        val scheduler = entry.liveLessonScheduler()

        val today = W4Dates.today()
        val year = IsoDateUtils.isoWeekYear(today)
        val week = IsoDateUtils.isoWeek(today)
        val events = when (val res = scheduleRepository.loadWeek(year, week, forceRefresh = false)) {
            is AppResult.Success -> res.data.days.find { it.date == today }?.events.orEmpty()
            is AppResult.Failure -> emptyList()
        }
        val now = W4Dates.now()
        notifier.update(events, now)
        scheduler.scheduleBoundaries(events, now)
        return Result.success()
    }

    companion object {
        const val KEY_EVENT_ID = "event_id"
        const val KEY_KIND = "kind"
        const val KEY_TITLE = "title"
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface LiveLessonEntryPoint {
    fun scheduleRepository(): ScheduleRepository
    fun liveLessonNotifier(): LiveLessonNotifier
    fun liveLessonScheduler(): LiveLessonScheduler
}
