package dk.betterw4.android.feature.trips

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
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
    suspend fun load(force: Boolean = false): AppResult<W4TripList> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                W4TripList(
                    title = "My trips",
                    trips = listOf(
                        W4Trip(
                            id = "trip-demo",
                            name = "Bergen weekend",
                            outgoing = "20-Sep-2026 08:00",
                            returning = "21-Sep-2026 18:00",
                            destination = "Bergen",
                            type = "Optional",
                            participants = "12",
                            status = "Planning",
                        ),
                    ),
                    canPlanNewTrip = true,
                ),
            )
        }
        val key = "trips_${student.studentId}"
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.TRIPS)) {
                    return AppResult.Success(W4TripsParser.parseList(cached.value))
                }
            }
        }
        return when (val res = client.get(W4Urls.Routes.TRIPS)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4TripsParser.parseList(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4TripsParser.parseList(it)) }
                res
            }
        }
    }

    suspend fun loadTravel(force: Boolean = false): AppResult<TravelPage> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                TravelPage(
                    title = "My travel forms",
                    forms = listOf(
                        TravelForm("travel-autumn", "To school in autumn", "Submitted", journey = TravelJourney.TO_SCHOOL_AUTUMN),
                        TravelForm("travel-winter", "Home for winter", "Not started", journey = TravelJourney.HOME_WINTER),
                        TravelForm("travel-back", "Back after winter", "Not started", journey = TravelJourney.BACK_AFTER_WINTER),
                        TravelForm("travel-summer", "Home for summer", "Not started", journey = TravelJourney.HOME_SUMMER),
                    ),
                    manageContactsLabel = "Manage my travel contacts",
                ),
            )
        }
        val key = "travel_${student.studentId}"
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.TRAVEL)) {
                    return AppResult.Success(W4TripsParser.parseTravel(cached.value))
                }
            }
        }
        return when (val res = client.get(W4Urls.Routes.TRAVEL)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4TripsParser.parseTravel(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4TripsParser.parseTravel(it)) }
                res
            }
        }
    }
}
