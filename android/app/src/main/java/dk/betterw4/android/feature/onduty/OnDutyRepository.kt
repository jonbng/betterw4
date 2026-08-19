package dk.betterw4.android.feature.onduty

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OnDutyRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun load(force: Boolean = false): AppResult<OnDutySnapshot> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoSnapshot())

        val today = loadToday(student.studentId, force)
        if (today is AppResult.Failure) return today
        val page = (today as AppResult.Success).data
        val upcoming = when (val schedule = loadSchedule(student.studentId, force)) {
            is AppResult.Success -> {
                W4OnDutyParser.upcomingDays(schedule.data)
                    .map { W4OnDutyParser.enrich(it, page.people) }
            }
            is AppResult.Failure -> emptyList()
        }
        return AppResult.Success(OnDutySnapshot(today = page, upcoming = upcoming))
    }

    private suspend fun loadToday(studentId: String, force: Boolean): AppResult<OnDutyPage> {
        val key = "onduty_$studentId"
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.ON_DUTY)) {
                    return AppResult.Success(W4OnDutyParser.parseToday(cached.value))
                }
            }
        }
        return when (val res = client.get(W4Urls.Routes.ON_DUTY)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4OnDutyParser.parseToday(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4OnDutyParser.parseToday(it)) }
                res
            }
        }
    }

    private suspend fun loadSchedule(studentId: String, force: Boolean): AppResult<OnDutySchedule> {
        val key = "onduty_schedule_$studentId"
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.ON_DUTY)) {
                    return AppResult.Success(W4OnDutyParser.parseSchedule(cached.value))
                }
            }
        }
        return when (val res = client.get(W4Urls.Routes.ON_DUTY_SCHEDULE)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4OnDutyParser.parseSchedule(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4OnDutyParser.parseSchedule(it)) }
                res
            }
        }
    }

    companion object {
        fun demoSnapshot(): OnDutySnapshot {
            val today = W4Dates.today()
            val houseLeader = OnDutyPerson(
                id = "nc00fff",
                name = "Frankie Fossum",
                role = "House Leader on Call",
                uwcId = "nc00fff",
                phone = "+47 12 34 56 78",
                email = "nc00fff@uwcrcn.no",
                location = "Haugland",
            )
            val nurse = OnDutyPerson(
                id = "nc00ccc",
                name = "Chris Chen",
                role = "Nurse on Call",
                uwcId = "nc00ccc",
                phone = "+47 98 76 54 32",
                email = "nc00ccc@uwcrcn.no",
            )
            return OnDutySnapshot(
                today = OnDutyPage(
                    title = "People on duty ${W4Dates.format(today)}",
                    date = today,
                    dateLabel = W4Dates.format(today),
                    groups = listOf(
                        OnDutyGroup("House Leader on Call", listOf(houseLeader)),
                        OnDutyGroup("Nurse on Call", listOf(nurse)),
                    ),
                ),
                upcoming = listOf(
                    OnDutyDay(
                        id = today.plusDays(1).toString(),
                        date = today.plusDays(1),
                        dateLabel = "Tomorrow",
                        groups = listOf(
                            OnDutyGroup(
                                "House Leader on call 15.00-23.00",
                                listOf(houseLeader.copy(id = "upcoming-house", role = "House Leader on call 15.00-23.00")),
                            ),
                        ),
                    ),
                    OnDutyDay(
                        id = today.plusDays(2).toString(),
                        date = today.plusDays(2),
                        dateLabel = today.plusDays(2).toString(),
                        groups = listOf(
                            OnDutyGroup(
                                "Weekend OVERNIGHT House Leader",
                                listOf(nurse.copy(id = "upcoming-overnight", role = "Weekend OVERNIGHT House Leader")),
                            ),
                        ),
                    ),
                ),
            )
        }
    }
}
