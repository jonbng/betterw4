package dk.betterw4.android.feature.trips

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class W4TripsRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun load(force: Boolean = false): AppResult<List<W4Trip>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                listOf(
                    W4Trip(
                        name = "Bergen weekend",
                        outgoing = "20-Sep-2026 08:00",
                        returning = "21-Sep-2026 18:00",
                        destination = "Bergen",
                        type = "Optional",
                        participants = "12",
                        status = "Planning",
                    ),
                ),
            )
        }
        val key = "trips_${student.studentId}"
        if (!force) {
            cache.get(key)?.let { return AppResult.Success(W4TripsParser.parse(it)) }
        }
        return when (val res = client.get(W4Urls.Routes.TRIPS)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4TripsParser.parse(res.data.body))
            }
            is AppResult.Failure -> res
        }
    }
}
