package dk.betterlectio.android.feature.directory

import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.core.util.LectioDateUtils
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.schedule.ScheduleParser
import dk.betterlectio.android.feature.schedule.ScheduleWeek
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RoomScheduleRepository @Inject constructor(
    private val client: LectioClient,
    private val session: SessionController,
) {
    /**
     * Room list with live occupancy flags (Flutter rooms controller parity).
     * Sources: FindSkema type=lokale + SkemaAvanceret type=aktuelleallelokaler.
     */
    suspend fun listRoomsWithOccupancy(): AppResult<List<RoomParser.RoomWithOccupancy>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                listOf(
                    RoomParser.RoomWithOccupancy("R1", "201", "Bygning A", inUse = true),
                    RoomParser.RoomWithOccupancy("R2", "105", "Bygning B", inUse = false),
                    RoomParser.RoomWithOccupancy("R3", "Lab 1", "Naturfag", inUse = true),
                    RoomParser.RoomWithOccupancy("R4", "312", "Bygning C", inUse = false),
                ),
            )
        }

        val roomsHtml = when (val res = client.get("FindSkema.aspx?type=lokale", FetchPriority.Important)) {
            is AppResult.Failure -> return res
            is AppResult.Success -> res.data.body
        }
        val rooms = RoomParser.parseRooms(roomsHtml)

        val availHtml = when (
            val res = client.get(
                "SkemaAvanceret.aspx?type=aktuelleallelokaler&nosubnav=1&prevurl=FindSkemaAdv.aspx",
                FetchPriority.Important,
            )
        ) {
            is AppResult.Failure -> null
            is AppResult.Success -> res.data.body
        }
        val availabilities = availHtml?.let { RoomParser.parseAvailabilities(it) }.orEmpty()
        return AppResult.Success(RoomParser.mergeOccupancy(rooms, availabilities))
    }

    suspend fun loadRoomWeek(
        room: DirectoryEntity,
        year: Int = LectioDateUtils.isoWeekYear(),
        week: Int = LectioDateUtils.isoWeek(),
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.scheduleWeek(year, week))
        }
        val weekParam = "%02d%d".format(week, year)
        val path = "SkemaNy.aspx?type=lokale&nosubnav=1&id=${room.id}&week=$weekParam"
        return when (val res = client.get(path)) {
            is AppResult.Failure -> res
            is AppResult.Success -> AppResult.Success(
                ScheduleParser.parseWeek(res.data.body, year, week),
            )
        }
    }

    /**
     * Week schedule for a directory person (student or teacher).
     * Lectio: `SkemaNy.aspx?type=elev&elevid=` / `type=laerer&laererid=`.
     */
    suspend fun loadPersonWeek(
        entity: DirectoryEntity,
        year: Int = LectioDateUtils.isoWeekYear(),
        week: Int = LectioDateUtils.isoWeek(),
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.scheduleWeek(year, week))
        }
        val numericId = DirectoryParser.numericId(entity.id)
        if (numericId.isBlank()) {
            return AppResult.Failure(AppError.Unknown("Missing entity id for schedule"))
        }
        val weekParam = "%02d%d".format(week, year)
        val path = when (entity.kind) {
            DirectoryEntityKind.STUDENT ->
                "SkemaNy.aspx?type=elev&elevid=$numericId&week=$weekParam"
            DirectoryEntityKind.TEACHER ->
                "SkemaNy.aspx?type=laerer&laererid=$numericId&week=$weekParam"
            else -> return AppResult.Failure(AppError.Unknown("Entity has no person schedule"))
        }
        return when (val res = client.get(path, FetchPriority.Important)) {
            is AppResult.Failure -> res
            is AppResult.Success -> AppResult.Success(
                ScheduleParser.parseWeek(res.data.body, year, week),
            )
        }
    }
}
