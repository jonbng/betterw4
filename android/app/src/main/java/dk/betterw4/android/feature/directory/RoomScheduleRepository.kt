package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.schedule.ScheduleWeek
import dk.betterw4.android.feature.schedule.TimetableWeekCache
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RoomScheduleRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun listRoomsWithOccupancy(): AppResult<List<RoomParser.RoomWithOccupancy>> =
        AppResult.Success(emptyList())

    /**
     * Week schedule for a directory person (student or staff).
     *
     * W4: `academics/timetable/timetable&uwc_id=` plus the matching EA route.
     * `mytimetable&uwc_id=` is ignored and always returns the signed-in student.
     */
    fun cachedPersonWeek(
        entity: DirectoryEntity,
        year: Int,
        week: Int,
    ): ScheduleWeek? {
        val student = session.currentStudent ?: return null
        if (student.isDemo) return DemoData.scheduleWeek(year, week)
        val uwcId = W4TimetableTargets.uwcId(entity.id) ?: return null
        return TimetableWeekCache.read(
            cache,
            TimetableWeekCache.personAcKey(uwcId, year, week),
            TimetableWeekCache.personEaKey(uwcId, year, week),
            year,
            week,
        )?.week
    }

    fun cachedRoomWeek(
        roomId: String,
        year: Int,
        week: Int,
    ): ScheduleWeek? {
        val student = session.currentStudent ?: return null
        if (student.isDemo) return DemoData.scheduleWeek(year, week)
        val id = W4TimetableTargets.roomId(roomId)
        if (id.isBlank()) return null
        return TimetableWeekCache.read(
            cache,
            TimetableWeekCache.roomAcKey(id, year, week),
            eaKey = null,
            year,
            week,
        )?.week
    }

    suspend fun loadPersonWeek(
        entity: DirectoryEntity,
        year: Int,
        week: Int,
        forceRefresh: Boolean = false,
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.scheduleWeek(year, week))
        }
        if (entity.kind != DirectoryEntityKind.STUDENT &&
            entity.kind != DirectoryEntityKind.TEACHER
        ) {
            return AppResult.Failure(AppError.Unknown("Entity has no person schedule"))
        }
        val uwcId = W4TimetableTargets.uwcId(entity.id)
            ?: return AppResult.Failure(AppError.Unknown("Missing UWC id for schedule"))
        return fetchMergedWeek(
            acRoute = W4Urls.Routes.PERSON_TIMETABLE_INDEX,
            eaRoute = W4Urls.Routes.EA_PERSON_TIMETABLE_INDEX,
            query = W4TimetableTargets.weekQuery("uwc_id", uwcId, year, week),
            year = year,
            week = week,
            acCacheKey = TimetableWeekCache.personAcKey(uwcId, year, week),
            eaCacheKey = TimetableWeekCache.personEaKey(uwcId, year, week),
            forceRefresh = forceRefresh,
        )
    }

    suspend fun loadRoomWeek(
        roomId: String,
        year: Int,
        week: Int,
        forceRefresh: Boolean = false,
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.scheduleWeek(year, week))
        }
        val id = W4TimetableTargets.roomId(roomId)
        if (id.isBlank()) {
            return AppResult.Failure(AppError.Unknown("Missing room id for schedule"))
        }
        return fetchMergedWeek(
            acRoute = W4Urls.Routes.ROOM_TIMETABLE_INDEX,
            eaRoute = null,
            query = W4TimetableTargets.weekQuery("room_id", id, year, week),
            year = year,
            week = week,
            acCacheKey = TimetableWeekCache.roomAcKey(id, year, week),
            eaCacheKey = null,
            forceRefresh = forceRefresh,
        )
    }

    private suspend fun fetchMergedWeek(
        acRoute: String,
        eaRoute: String?,
        query: Map<String, String>,
        year: Int,
        week: Int,
        acCacheKey: String,
        eaCacheKey: String?,
        forceRefresh: Boolean,
    ): AppResult<ScheduleWeek> {
        val cached = TimetableWeekCache.read(cache, acCacheKey, eaCacheKey, year, week)
        if (!forceRefresh && cached != null && cached.isFresh) {
            return AppResult.Success(cached.week)
        }
        return coroutineScope {
            val acDeferred = async {
                client.get(acRoute, query = query, priority = FetchPriority.Important)
            }
            val eaDeferred = eaRoute?.let { route ->
                async {
                    client.get(route, query = query, priority = FetchPriority.Opportunistic)
                }
            }
            val acResult = acDeferred.await()
            val acHtml = when (acResult) {
                is AppResult.Success -> acResult.data.body
                is AppResult.Failure -> cache.get(acCacheKey)
                    ?: return@coroutineScope acResult
            }
            val eaHtml = eaDeferred?.let { deferred ->
                (deferred.await() as? AppResult.Success)?.data?.body
            }
            if (acResult is AppResult.Success) {
                TimetableWeekCache.write(cache, acCacheKey, acHtml, eaCacheKey, eaHtml)
            }
            val merged = TimetableWeekCache.mergeHtml(acHtml, eaHtml, year, week)
                ?: return@coroutineScope AppResult.Failure(AppError.Unknown("Empty timetable page"))
            AppResult.Success(merged)
        }
    }
}

internal object W4TimetableTargets {
    fun weekQuery(idKey: String, id: String, year: Int, week: Int): Map<String, String> =
        mapOf(
            idKey to id,
            "year" to year.toString(),
            "week" to week.toString(),
        )

    fun uwcId(raw: String): String? =
        W4Html.UWC_ID.find(raw.trim())?.groupValues?.get(1)?.lowercase()

    /**
     * Classroom links use `room_id=a16` for "A 1.6". Named rooms (`Lib`, `TR`)
     * are already the id — leave those alone.
     */
    fun roomId(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""
        if (' ' !in trimmed && '.' !in trimmed) return trimmed
        return trimmed.lowercase().replace(" ", "").replace(".", "")
    }
}
