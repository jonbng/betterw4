package dk.betterw4.android.feature.notifications

import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.markAllNotificationEmailsRead
import dk.betterw4.android.core.w4.markAllNotificationsRead
import dk.betterw4.android.core.w4.markNotificationRead
import dk.betterw4.android.core.w4.refreshNotifications
import dk.betterw4.android.core.w4.session.SessionController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class W4NotificationRepository @Inject constructor(
    private val client: W4Client,
    private val session: SessionController,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _snapshot = MutableStateFlow(W4NotificationSnapshot())
    val snapshot: StateFlow<W4NotificationSnapshot> = _snapshot.asStateFlow()

    @Volatile
    private var dropdownOpen = false
    private var pollJob: Job? = null

    fun setDropdownOpen(open: Boolean) {
        dropdownOpen = open
    }

    fun startPolling() {
        if (pollJob?.isActive == true) return
        pollJob = scope.launch {
            refresh()
            while (isActive) {
                delay(POLL_MS)
                if (!dropdownOpen) refresh()
            }
        }
    }

    fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    suspend fun refresh(): AppResult<W4NotificationSnapshot> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val demo = demoSnapshot()
            _snapshot.value = demo
            return AppResult.Success(demo)
        }
        return when (val res = client.refreshNotifications()) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val parsed = W4NotificationParser.parse(res.data.body)
                _snapshot.value = parsed
                AppResult.Success(parsed)
            }
        }
    }

    suspend fun markRead(id: String): AppResult<W4NotificationSnapshot> {
        if (session.currentStudent?.isDemo == true) {
            _snapshot.value = _snapshot.value.copy(
                taskGroups = _snapshot.value.taskGroups.map { g ->
                    g.copy(items = g.items.filterNot { it.id == id })
                },
                emailGroups = _snapshot.value.emailGroups.map { g ->
                    g.copy(items = g.items.filterNot { it.id == id })
                },
                count = (_snapshot.value.count - 1).coerceAtLeast(0),
            )
            return AppResult.Success(_snapshot.value)
        }
        return when (val res = client.markNotificationRead(id)) {
            is AppResult.Failure -> {
                Timber.w("markNotificationRead failed id=%s", id)
                res
            }
            is AppResult.Success -> {
                val parsed = W4NotificationParser.parse(res.data.body)
                _snapshot.value = parsed
                AppResult.Success(parsed)
            }
        }
    }

    suspend fun markAllRead(): AppResult<W4NotificationSnapshot> {
        if (session.currentStudent?.isDemo == true) {
            _snapshot.value = W4NotificationSnapshot()
            return AppResult.Success(_snapshot.value)
        }
        return when (val res = client.markAllNotificationsRead()) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val parsed = W4NotificationParser.parse(res.data.body)
                _snapshot.value = parsed
                AppResult.Success(parsed)
            }
        }
    }

    suspend fun markAllEmailsRead(): AppResult<W4NotificationSnapshot> {
        if (session.currentStudent?.isDemo == true) {
            _snapshot.value = _snapshot.value.copy(emailGroups = emptyList())
            return AppResult.Success(_snapshot.value)
        }
        return when (val res = client.markAllNotificationEmailsRead()) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val parsed = W4NotificationParser.parse(res.data.body)
                _snapshot.value = parsed
                AppResult.Success(parsed)
            }
        }
    }

    private fun demoSnapshot() = W4NotificationSnapshot(
        count = 2,
        severity = W4NotificationSeverity.NEW,
        taskGroups = listOf(
            W4NotificationGroup(
                type = "assessment",
                title = "Assessments",
                severity = W4NotificationSeverity.OVERDUE,
                items = listOf(
                    W4NotificationItem(
                        id = "demo-1",
                        title = "Lab report",
                        subtitle = "overdue",
                        href = "index.php?r=academics/deadlines",
                        type = "assessment",
                        section = W4NotificationSection.TASK,
                        severity = W4NotificationSeverity.OVERDUE,
                    ),
                ),
            ),
        ),
        emailGroups = listOf(
            W4NotificationGroup(
                type = "email",
                title = "Inbox",
                severity = W4NotificationSeverity.NEW,
                items = listOf(
                    W4NotificationItem(
                        id = "demo-2",
                        title = "Welcome to W4",
                        href = "index.php?r=mailer/view&id=1",
                        type = "email",
                        section = W4NotificationSection.EMAIL,
                        severity = W4NotificationSeverity.NEW,
                    ),
                ),
            ),
        ),
    )

    companion object {
        const val POLL_MS = 60_000L
    }
}
