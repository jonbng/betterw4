package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.schedule.ScheduleWeek
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RoomScheduleRepository @Inject constructor(
    private val session: SessionController,
) {
    suspend fun listRoomsWithOccupancy(): AppResult<List<RoomParser.RoomWithOccupancy>> =
        AppResult.Success(emptyList())

    suspend fun loadPersonWeek(
        @Suppress("UNUSED_PARAMETER") entity: DirectoryEntity,
        year: Int,
        week: Int,
    ): AppResult<ScheduleWeek> {
        if (session.currentStudent?.isDemo == true) {
            return AppResult.Success(DemoData.scheduleWeek(year, week))
        }
        return AppResult.Success(ScheduleWeek(year = year, week = week, days = emptyList()))
    }

    suspend fun loadRoomWeek(
        @Suppress("UNUSED_PARAMETER") entity: DirectoryEntity,
        year: Int,
        week: Int,
    ): AppResult<ScheduleWeek> = AppResult.Success(ScheduleWeek(year, week, emptyList()))
}
