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
import dk.betterw4.android.feature.schedule.ScheduleRepository
import java.time.LocalDate
import java.time.LocalDateTime

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

        val year = IsoDateUtils.isoWeekYear()
        val week = IsoDateUtils.isoWeek()
        val events = when (val res = scheduleRepository.loadWeek(year, week, forceRefresh = false)) {
            is AppResult.Success -> {
                val today = LocalDate.now()
                res.data.days.find { it.date == today }?.events.orEmpty()
            }
            is AppResult.Failure -> emptyList()
        }
        val now = LocalDateTime.now()
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
