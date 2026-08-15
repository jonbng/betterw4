package dk.betterlectio.android.feature.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import dagger.hilt.android.AndroidEntryPoint
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.core.util.LectioDateUtils
import dk.betterlectio.android.feature.schedule.ScheduleRepository
import dk.betterlectio.android.feature.schedule.ScheduleWeek
import dk.betterlectio.android.wear.model.WearScheduleProtocol
import dk.betterlectio.android.wear.model.WearSyncStatus
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.LocalDate

@AndroidEntryPoint
class PhoneWearScheduleListenerService : WearableListenerService() {
    @Inject lateinit var repository: ScheduleRepository
    @Inject lateinit var publisher: PhoneWearSchedulePublisher

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != WearScheduleProtocol.REFRESH_PATH) return
        scope.launch { refreshSchedule() }
    }

    private suspend fun refreshSchedule() {
        val dates = listOf(LocalDate.now(), LocalDate.now().plusDays(7))
        val requestedWeeks = dates
            .map { LectioDateUtils.isoWeekYear(it) to LectioDateUtils.isoWeek(it) }
            .distinct()
        val weeks = mutableListOf<ScheduleWeek>()

        for ((year, week) in requestedWeeks) {
            when (val result = repository.loadWeek(year, week, forceRefresh = true)) {
                is AppResult.Success -> weeks += result.data
                is AppResult.Failure -> {
                    if (result.error.isAuthenticationFailure()) {
                        publisher.publishStatus(WearSyncStatus.AUTH_REQUIRED)
                        return
                    }
                    if (weeks.isEmpty()) {
                        publisher.publishStatus(
                            WearSyncStatus.ERROR,
                            result.error.userSafeMessage(),
                        )
                        return
                    }
                }
            }
        }

        publisher.publishWeeks(weeks)
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun AppError.isAuthenticationFailure(): Boolean =
        this is AppError.Unauthorized || this is AppError.SessionExpired

    private fun AppError.userSafeMessage(): String = when (this) {
        AppError.Offline -> "offline"
        is AppError.Network -> "network"
        AppError.RobotDetection -> "robot_detection"
        else -> "refresh_failed"
    }
}
