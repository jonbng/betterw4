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
    private val customEvents: CustomEventStore,
) {
    /** Device-local custom events, hydrated from [customEvents] per student. */
    internal val localPrivate = LocalPrivateEvents()
    private var hydratedStudentId: String? = null

    private fun hydrateCustomEvents() {
        val id = session.currentStudent?.studentId ?: return
        if (hydratedStudentId == id) return
        localPrivate.replaceAll(customEvents.load(id))
        hydratedStudentId = id
    }

    private fun persistCustomEvents() {
        val id = session.currentStudent?.studentId ?: return
        customEvents.save(id, localPrivate.snapshot())
    }

    suspend fun loadWeek(
        year: Int = IsoDateUtils.isoWeekYear(),
        week: Int = IsoDateUtils.isoWeek(),
        forceRefresh: Boolean = false,
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        hydrateCustomEvents()

        if (student.isDemo) {
            val demo = localPrivate.mergeIntoWeek(DemoData.scheduleWeek(year, week))
            return AppResult.Success(overlaySchoolCalendar(demo, year, week, forceRefresh))
        }

        val acKey = TimetableWeekCache.ownAcKey(student.studentId, year, week)
        val eaKey = TimetableWeekCache.ownEaKey(student.studentId, year, week)
        val cached = TimetableWeekCache.read(cache, acKey, eaKey, year, week)
        if (!forceRefresh && cached != null && cached.isFresh) {
            val overlaid = overlaySchoolCalendar(cached.week, year, week, forceRefresh = false)
            return AppResult.Success(localPrivate.mergeIntoWeek(overlaid))
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
                ac.data.body
            }
            is AppResult.Failure -> cache.get(acKey)
        }
        if (acHtml == null) {
            return fetched.first as AppResult.Failure
        }
        val eaHtml = (fetched.second as? AppResult.Success)?.data?.body
        if (fetched.first is AppResult.Success) {
            TimetableWeekCache.write(cache, acKey, acHtml, eaKey, eaHtml)
        }
        val merged = TimetableWeekCache.mergeHtml(acHtml, eaHtml, year, week)
            ?: return fetched.first as AppResult.Failure
        val withSchool = SchoolCalendar.mergeIntoWeek(merged, fetched.third)
        val weekData = localPrivate.mergeIntoWeek(withSchool)
        return AppResult.Success(weekData)
    }

    /**
     * Disk copy of this week, with no network. Null when this student has never
     * opened that week. Used to paint the grid before [loadWeek] refreshes it.
     */
    suspend fun cachedWeek(
        year: Int = IsoDateUtils.isoWeekYear(),
        week: Int = IsoDateUtils.isoWeek(),
    ): ScheduleWeek? {
        val student = session.currentStudent ?: return null
        hydrateCustomEvents()
        if (student.isDemo) {
            val demo = localPrivate.mergeIntoWeek(DemoData.scheduleWeek(year, week))
            return overlaySchoolCalendar(demo, year, week, forceRefresh = false)
        }
        val cached = TimetableWeekCache.read(
            cache,
            TimetableWeekCache.ownAcKey(student.studentId, year, week),
            TimetableWeekCache.ownEaKey(student.studentId, year, week),
            year,
            week,
        ) ?: return null
        val overlaid = overlaySchoolCalendar(cached.week, year, week, forceRefresh = false)
        return localPrivate.mergeIntoWeek(overlaid)
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

        if (SchoolCalendar.isSchoolCalendarEvent(event) || PrivateEventIds.isPrivateEvent(event)) {
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

        if (student.isDemo) {
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
        session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)

        // Update path when draft carries an existing event id
        if (!draft.eventId.isNullOrBlank()) {
            return updatePrivateEvent(draft.eventId, draft)
        }

        hydrateCustomEvents()
        // W4 has no private-appointment form; keep events on the device.
        val event = localPrivate.createFromDraft(draft)
        persistCustomEvents()
        return AppResult.Success(event)
    }

    /**
     * Replace an existing device-local custom event.
     */
    suspend fun updatePrivateEvent(eventId: String, draft: PrivateEventDraft): AppResult<ScheduleEvent> {
        session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)

        hydrateCustomEvents()
        val updated = localPrivate.updateFromDraft(eventId, draft)
        persistCustomEvents()
        return AppResult.Success(updated)
    }

    suspend fun deletePrivateEvent(event: ScheduleEvent): AppResult<Unit> {
        hydrateCustomEvents()
        localPrivate.delete(event.id)
        persistCustomEvents()
        return AppResult.Success(Unit)
    }

    fun localPrivateEventsSnapshot(): List<ScheduleEvent> = localPrivate.snapshot()

    /** Re-lay persisted custom events over a week already in memory. No network. */
    fun overlayLocal(week: ScheduleWeek): ScheduleWeek {
        hydrateCustomEvents()
        return localPrivate.remesh(week)
    }

    fun clearLocalPrivateEventsForTest() {
        localPrivate.clear()
        hydratedStudentId = null
    }
}
