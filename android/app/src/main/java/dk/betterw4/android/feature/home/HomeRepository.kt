package dk.betterw4.android.feature.home

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.absence.W4AbsenceParser
import dk.betterw4.android.feature.campus.CampusStatus
import dk.betterw4.android.feature.campus.CampusStatusParser
import dk.betterw4.android.feature.campus.CampusStatusRepository
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

data class HomeSnapshot(
    val page: HomePage,
    val academicAbsences: Int = 0,
    val academicLatenesses: Int = 0,
    val eaAbsences: Int = 0,
    val eaLatenesses: Int = 0,
    val campus: CampusStatus? = null,
    val fetchedAtMs: Long = System.currentTimeMillis(),
    val demo: Boolean = false,
)

@Singleton
class HomeRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val campusStatus: CampusStatusRepository,
) {
    suspend fun load(force: Boolean = false): AppResult<HomeSnapshot> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoSnapshot())

        val key = "home_${student.studentId}"
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.HOME)) {
                    return AppResult.Success(parseSnapshot(cached.value, cached.updatedAtMs))
                }
            }
        }
        return when (val res = client.get(W4Urls.Routes.HOME)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                campusStatus.applyHtml(res.data.body)
                AppResult.Success(parseSnapshot(res.data.body, System.currentTimeMillis()))
            }
            is AppResult.Failure -> {
                cache.getWithMeta(key)?.let {
                    return AppResult.Success(parseSnapshot(it.value, it.updatedAtMs))
                }
                res
            }
        }
    }

    private fun parseSnapshot(html: String, fetchedAtMs: Long): HomeSnapshot {
        val page = W4HomeParser.parse(html)
        val meters = W4AbsenceParser.parseHomeMeters(html)
        return HomeSnapshot(
            page = page,
            academicAbsences = meters.academic?.absences ?: 0,
            academicLatenesses = meters.academic?.latenesses ?: 0,
            eaAbsences = meters.ea?.absences ?: 0,
            eaLatenesses = meters.ea?.latenesses ?: 0,
            campus = CampusStatusParser.parse(html),
            fetchedAtMs = fetchedAtMs,
        )
    }

    private fun demoSnapshot(): HomeSnapshot = HomeSnapshot(
        page = DemoData.homePage(),
        academicAbsences = 2,
        academicLatenesses = 1,
        campus = CampusStatus(onCampus = true),
        demo = true,
    )
}
