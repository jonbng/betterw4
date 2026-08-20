package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.campus.CampusStatusRepository
import dk.betterw4.android.feature.classes.MyClass
import dk.betterw4.android.feature.classes.MyClassRepository
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.directory.W4PeopleParser
import dk.betterw4.android.feature.settings.SettingsStore
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScheduleRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val campusStatus: CampusStatusRepository,
    private val schoolCalendar: SchoolCalendarRepository,
    private val settings: SettingsStore,
    private val myClasses: MyClassRepository,
) {
    /** Demo/local private events created this session (also used when Lectio POST is unavailable). */
    internal val localPrivate = LocalPrivateEvents()

    suspend fun loadWeek(
        year: Int = IsoDateUtils.isoWeekYear(),
        week: Int = IsoDateUtils.isoWeek(),
        forceRefresh: Boolean = false,
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        if (student.isDemo) {
            val demo = localPrivate.mergeIntoWeek(DemoData.scheduleWeek(year, week))
            return AppResult.Success(overlaySchoolCalendar(demo, year, week, forceRefresh))
        }

        val cacheKey = "schedule_${student.studentId}_${year}_$week"
        if (!forceRefresh) {
            cache.get(cacheKey)?.let { html ->
                val cached = localPrivate.mergeIntoWeek(W4TimetableParser.parseWeek(html, year, week))
                return AppResult.Success(overlaySchoolCalendar(cached, year, week, forceRefresh = false))
            }
        }

        val query = mapOf("year" to year.toString(), "week" to week.toString())
        val fetched = coroutineScope {
            val ac = async {
                client.get(
                    W4Urls.Routes.MY_TIMETABLE_INDEX,
                    query = query,
                    priority = FetchPriority.Important,
                )
            }
            val ea = async {
                client.get(
                    W4Urls.Routes.EA_TIMETABLE_INDEX,
                    query = query,
                    priority = FetchPriority.Opportunistic,
                )
            }
            val gcal = async { schoolCalendarEvents(year, week, forceRefresh) }
            Triple(ac.await(), ea.await(), gcal.await())
        }

        val acHtml = when (val ac = fetched.first) {
            is AppResult.Success -> {
                campusStatus.applyHtml(ac.data.body)
                cache.put(cacheKey, ac.data.body)
                ac.data.body
            }
            is AppResult.Failure -> cache.get(cacheKey)
        }
        if (acHtml == null) {
            return fetched.first as AppResult.Failure
        }
        val acWeek = W4TimetableParser.parseWeek(acHtml, year, week, source = "ac")
        val eaHtml = (fetched.second as? AppResult.Success)?.data?.body
        val merged = if (eaHtml != null) {
            W4TimetableParser.mergeWeeks(
                acWeek,
                W4TimetableParser.parseWeek(eaHtml, year, week, source = "ea"),
            )
        } else {
            acWeek
        }
        val withSchool = SchoolCalendar.mergeIntoWeek(merged, fetched.third)
        val weekData = localPrivate.mergeIntoWeek(withSchool)
        return AppResult.Success(weekData)
    }

    private suspend fun overlaySchoolCalendar(
        week: ScheduleWeek,
        year: Int,
        weekNum: Int,
        forceRefresh: Boolean,
    ): ScheduleWeek {
        val extra = schoolCalendarEvents(year, weekNum, forceRefresh)
        return SchoolCalendar.mergeIntoWeek(week, extra)
    }

    private suspend fun schoolCalendarEvents(
        year: Int,
        week: Int,
        forceRefresh: Boolean,
    ): List<ScheduleEvent> {
        if (!settings.showSchoolCalendar.value) return emptyList()
        return schoolCalendar.eventsForWeek(year, week, forceRefresh)
    }

    suspend fun loadLessonDetail(event: ScheduleEvent): AppResult<LessonDetail> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        if (SchoolCalendar.isSchoolCalendarEvent(event)) {
            return AppResult.Success(
                LessonDetail(
                    eventId = event.id,
                    title = event.title,
                    note = listOfNotNull(event.room, event.notes).joinToString("\n\n").ifBlank { null },
                    contentBlocks = listOfNotNull(
                        event.room?.let { LessonContentBlock("paragraph", it) },
                        event.notes?.let { LessonContentBlock("note", it) },
                    ),
                ),
            )
        }

        if (student.isDemo || event.id.startsWith("local-private")) {
            val detail = DemoData.lessonDetail(event)
            val people = peopleFromClass(demoClass(event))
            return AppResult.Success(
                detail.copy(
                    participants = people.ifEmpty { detail.participants },
                    holdId = ClassRoster.classId(event.href, event.team),
                ),
            )
        }

        val classId = ClassRoster.classId(event.href, event.team)
        val roster = if (classId != null) {
            (myClasses.loadClass(classId) as? AppResult.Success)?.data
        } else {
            null
        }
        val participants = peopleFromClass(roster).ifEmpty { teacherFallback(event) }
        val detail = LessonDetail(
            eventId = event.id,
            title = event.title,
            note = listOfNotNull(event.teacher, event.room, event.notes).joinToString(" · ").ifBlank { event.notes },
            homework = event.homework,
            contentBlocks = listOfNotNull(
                event.teacher?.let { LessonContentBlock("paragraph", it) },
                event.room?.let { LessonContentBlock("paragraph", it) },
                event.notes?.let { LessonContentBlock("note", it) },
                event.homework?.let { LessonContentBlock("paragraph", it, isHomework = true) },
            ),
            participants = participants,
            holdId = classId,
        )
        return AppResult.Success(detail)
    }

    private fun demoClass(event: ScheduleEvent): MyClass? {
        val classId = ClassRoster.classId(event.href, event.team) ?: return null
        return DemoData.myClasses.firstOrNull { it.id.equals(classId, ignoreCase = true) }
    }

    /** People enrolled in this class. Empty when W4 has no roster for the block. */
    private fun peopleFromClass(item: MyClass?): List<LessonParticipant> {
        if (item == null) return emptyList()
        return (item.teachers + item.students).map { LessonParticipant.fromDirectory(it.entity) }
    }

    private fun teacherFallback(event: ScheduleEvent): List<LessonParticipant> {
        val teacherId = event.teacherId?.lowercase()?.takeIf { it.isNotBlank() } ?: return emptyList()
        return listOf(
            LessonParticipant(
                id = teacherId,
                name = event.teacher?.takeIf { it.isNotBlank() } ?: teacherId,
                role = "Teacher",
                kind = DirectoryEntityKind.TEACHER,
                avatarUrl = W4PeopleParser.guessPhotoUrl(teacherId),
            ),
        )
    }

    suspend fun createPrivateEvent(draft: PrivateEventDraft): AppResult<ScheduleEvent> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        // Update path when draft carries an existing event id
        if (!draft.eventId.isNullOrBlank()) {
            return updatePrivateEvent(draft.eventId, draft)
        }

        if (student.isDemo) {
            val event = localPrivate.createFromDraft(draft)
            return AppResult.Success(event)
        }

        // W4 has no private-appointment form; keep a local overlay for the session.
        val event = localPrivate.createFromDraft(draft)
        return AppResult.Success(event)
    }

    /**
     * Update an existing private event on Lectio (Flutter PrivateCalendarEventController.update).
     */
    suspend fun updatePrivateEvent(eventId: String, draft: PrivateEventDraft): AppResult<ScheduleEvent> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        val updated = localPrivate.updateFromDraft(eventId, draft)
        return AppResult.Success(updated)
    }

    suspend fun deletePrivateEvent(event: ScheduleEvent): AppResult<Unit> {
        localPrivate.delete(event.id)
        return AppResult.Success(Unit)
    }

    fun localPrivateEventsSnapshot(): List<ScheduleEvent> = localPrivate.snapshot()

    fun clearLocalPrivateEventsForTest() {
        localPrivate.clear()
    }
}
