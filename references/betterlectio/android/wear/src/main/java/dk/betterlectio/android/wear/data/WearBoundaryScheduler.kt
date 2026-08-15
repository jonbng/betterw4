package dk.betterlectio.android.wear.data

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object WearBoundaryScheduler {
    private const val WORK_NAME = "wear-schedule-boundary"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun schedule(context: Context) {
        val appContext = context.applicationContext
        scope.launch {
            val snapshot = WearScheduleRepository(appContext).read().schedule ?: return@launch
            val now = System.currentTimeMillis()
            val eventBoundaries = snapshot.events
                .flatMap { listOfNotNull(it.startEpochMillis, it.endEpochMillis) }
                .filter { it > now }
            val zone = runCatching { ZoneId.of(snapshot.zoneId) }
                .getOrDefault(ZoneId.systemDefault())
            val dayRollover = Instant.ofEpochMilli(now)
                .atZone(zone)
                .toLocalDate()
                .plusDays(1)
                .atStartOfDay(zone)
                .toInstant()
                .toEpochMilli()
            val next = (eventBoundaries + dayRollover).minOrNull() ?: return@launch
            val delayMillis = (next - now + 1_000L).coerceAtLeast(1_000L)
            val request = OneTimeWorkRequestBuilder<WearBoundaryWorker>()
                .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
                .setInputData(Data.EMPTY)
                .build()
            WorkManager.getInstance(appContext).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }
}

class WearBoundaryWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        WearSurfaceUpdater.requestUpdates(applicationContext)
        WearScheduleRepository(applicationContext).requestRefresh()
        return Result.success()
    }
}
