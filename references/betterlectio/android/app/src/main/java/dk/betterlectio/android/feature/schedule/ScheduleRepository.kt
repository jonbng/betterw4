package dk.betterlectio.android.feature.schedule

import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.scrape.SmartPostback
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.core.util.LectioDateUtils
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.directory.DirectoryEntity
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.directory.DirectoryRepository
import dk.betterlectio.android.feature.supabase.ScheduleIdentity
import dk.betterlectio.android.feature.supabase.SupabaseScheduleService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScheduleRepository @Inject constructor(
    private val client: LectioClient,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val supabaseSchedule: SupabaseScheduleService,
    private val directoryRepo: DirectoryRepository,
) {
    private val syncScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    /** Demo/local private events created this session (also used when Lectio POST is unavailable). */
    internal val localPrivate = LocalPrivateEvents()

    suspend fun loadWeek(
        year: Int = LectioDateUtils.isoWeekYear(),
        week: Int = LectioDateUtils.isoWeek(),
        forceRefresh: Boolean = false,
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        if (student.isDemo) {
            return AppResult.Success(localPrivate.mergeIntoWeek(DemoData.scheduleWeek(year, week)))
        }

        val cacheKey = "schedule_${student.studentId}_${year}_$week"
        if (!forceRefresh) {
            cache.get(cacheKey)?.let { html ->
                return AppResult.Success(
                    localPrivate.mergeIntoWeek(ScheduleParser.parseWeek(html, year, week)),
                )
            }
        }

        val weekParam = "%02d%d".format(week, year)
        val path =
            "SkemaNy.aspx?type=elev&elevid=${student.studentId}&week=$weekParam"

        return when (val res = client.get(path, FetchPriority.Important)) {
            is AppResult.Failure -> {
                cache.get(cacheKey)?.let { html ->
                    return AppResult.Success(
                        localPrivate.mergeIntoWeek(ScheduleParser.parseWeek(html, year, week)),
                    )
                }
                res
            }
            is AppResult.Success -> {
                cache.put(cacheKey, res.data.body)
                val weekData = localPrivate.mergeIntoWeek(ScheduleParser.parseWeek(res.data.body, year, week))
                // Best-effort remote schedule sync (iOS: SupabaseScheduleService.syncWeek)
                val events = weekData.days.flatMap { it.events }
                val weekKey = ScheduleIdentity.weekKey(year, week)
                syncScope.launch {
                    supabaseSchedule.syncWeek(student.studentId, weekKey, events)
                }
                AppResult.Success(weekData)
            }
        }
    }

    suspend fun loadLessonDetail(event: ScheduleEvent): AppResult<LessonDetail> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        if (student.isDemo || event.id.startsWith("local-private")) {
            return AppResult.Success(DemoData.lessonDetail(event))
        }

        // iOS always fetches aktivitetforside2 — brick href is often aktivitetforside.aspx (no content).
        val absId = event.id.removePrefix("ABS").removePrefix("PRV")
        val path =
            "aktivitet/aktivitetforside2.aspx?absid=$absId&elevid=${student.studentId}&prevurl=skemany.aspx"

        return when (val res = client.get(path, FetchPriority.Important)) {
            is AppResult.Failure -> {
                val fallback = LessonDetail(
                    eventId = event.id,
                    title = event.title,
                    note = event.notes,
                    homework = event.homework,
                    contentBlocks = listOfNotNull(
                        event.notes?.let { LessonContentBlock("note", it) },
                        event.homework?.let {
                            LessonContentBlock("paragraph", it, isHomework = true)
                        },
                    ),
                )
                // Still best-effort push whatever we have locally
                syncLessonContentBestEffort(student.studentId, event, fallback)
                AppResult.Success(fallback)
            }
            is AppResult.Success -> {
                cache.put("lesson_${event.id}", res.data.body)
                var detail = LessonDetailParser.parse(res.data.body, event.id, event.title).let { parsed ->
                    parsed.copy(
                        note = parsed.note ?: event.notes,
                        homework = parsed.homework ?: event.homework,
                    )
                }
                detail = attachParticipants(detail)
                syncLessonContentBestEffort(student.studentId, event, detail)
                AppResult.Success(detail)
            }
        }
    }

    /** Extension: members.aspx via holdelementid — never fail the whole detail if members fail. */
    private suspend fun attachParticipants(detail: LessonDetail): LessonDetail {
        val holdId = detail.holdId ?: return detail
        val hold = DirectoryEntity(
            id = holdId,
            name = detail.title,
            kind = DirectoryEntityKind.HOLD,
        )
        return when (val members = directoryRepo.loadMembers(hold)) {
            is AppResult.Success -> detail.copy(
                participants = members.data.map { LessonParticipant.fromDirectory(it) },
            )
            is AppResult.Failure -> detail
        }
    }

    private fun syncLessonContentBestEffort(
        studentId: String,
        event: ScheduleEvent,
        detail: LessonDetail,
    ) {
        val lessonKey = ScheduleIdentity.lessonKey(event, studentId)
        syncScope.launch {
            supabaseSchedule.syncLessonContent(studentId, lessonKey, detail)
        }
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

        // Live: GET form + smart POST — fail when Lectio rejects (no silent local-only success)
        return when (val page = client.get("privat_aftale.aspx", FetchPriority.Important)) {
            is AppResult.Failure -> page
            is AppResult.Success -> {
                val html = page.data.body
                val fields = resolvePrivateEventFields(html, draft)
                when (val post = client.postForm("privat_aftale.aspx", fields, FetchPriority.Important)) {
                    is AppResult.Failure -> post
                    is AppResult.Success -> {
                        if (!PrivateEventResponse.isAccepted(post.data.body)) {
                            return AppResult.Failure(
                                AppError.Unknown("Lectio afviste den private aftale"),
                            )
                        }
                        cache.clearAll()
                        // Prefer Lectio AFT{id} so create→edit posts back to privat_aftale.aspx
                        val numeric = PrivateEventIds.extractAftaleIdFromResponse(post.data.body)
                        val storageId = if (numeric != null) {
                            PrivateEventIds.storageId(numeric)
                        } else {
                            "local-private-${System.currentTimeMillis()}"
                        }
                        val event = localPrivate.createFromDraft(draft, id = storageId)
                        AppResult.Success(event)
                    }
                }
            }
        }
    }

    /**
     * Update an existing private event on Lectio (Flutter PrivateCalendarEventController.update).
     */
    suspend fun updatePrivateEvent(eventId: String, draft: PrivateEventDraft): AppResult<ScheduleEvent> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        // Demo-only local ids: no Lectio. AFT/PRIV always go live even if also in local overlay.
        val path = PrivateEventIds.updatePath(eventId)
        if (student.isDemo || (eventId.startsWith("local-private") && path == null)) {
            val updated = localPrivate.updateFromDraft(eventId, draft)
            return AppResult.Success(updated)
        }
        if (path == null) {
            return AppResult.Failure(
                AppError.Unknown("Ugyldigt privat-aftale-id: $eventId"),
            )
        }
        return when (val page = client.get(path, FetchPriority.Important)) {
            is AppResult.Failure -> page
            is AppResult.Success -> {
                val fields = resolvePrivateEventFields(page.data.body, draft)
                when (val post = client.postForm(path, fields, FetchPriority.Important)) {
                    is AppResult.Failure -> post
                    is AppResult.Success -> {
                        if (!PrivateEventResponse.isAccepted(post.data.body)) {
                            return AppResult.Failure(
                                AppError.Unknown("Lectio afviste opdatering af privat aftale"),
                            )
                        }
                        cache.clearAll()
                        val storageId = PrivateEventIds.numericAftaleId(eventId)
                            ?.let { PrivateEventIds.storageId(it) }
                            ?: eventId
                        // Keep overlay in sync under canonical AFT id
                        if (eventId != storageId) localPrivate.delete(eventId)
                        val updated = localPrivate.updateFromDraft(storageId, draft)
                        AppResult.Success(updated)
                    }
                }
            }
        }
    }

    private fun resolvePrivateEventFields(html: String, draft: PrivateEventDraft): Map<String, String> {
        val titleField = SmartPostback.findFieldName(html, listOf("titel", "title", "titelTextBox"))
            ?: "m\$Content\$titelTextBox\$tb"
        val noteField = SmartPostback.findFieldName(html, listOf("comment", "note", "commentTextBox"))
            ?: "m\$Content\$commentTextBox\$tb"
        val startDateField = SmartPostback.findFieldName(html, listOf("startdate", "_date"))
            ?: "m\$Content\$startdateCtrl\$_date\$tb"
        val startTimeField = SmartPostback.findFieldName(html, listOf("startdateCtrl_time", "starttime"))
            ?: "m\$Content\$startdateCtrl\$startdateCtrl_time\$tb"
        val endDateField = SmartPostback.findFieldName(html, listOf("enddate", "slut"))
            ?: "m\$Content\$enddateCtrl\$_date\$tb"
        val endTimeField = SmartPostback.findFieldName(html, listOf("enddateCtrl_time", "endtime"))
            ?: "m\$Content\$enddateCtrl\$enddateCtrl_time\$tb"
        val extra = PrivateEventResponse.fieldOverrides(
            title = draft.title,
            startDate = draft.startDate,
            startTime = draft.startTime,
            endDate = draft.endDate,
            endTime = draft.endTime,
            note = draft.note,
            titleField = titleField,
            noteField = noteField,
            startDateField = startDateField,
            startTimeField = startTimeField,
            endDateField = endDateField,
            endTimeField = endTimeField,
        )
        return SmartPostback.resolve(
            html = html,
            preferredTargets = listOf(
                "m\$Content\$savebuttonsCtrl\$svbtn",
                "m\$Content\$savebtn",
                "s\$m\$Content\$savebuttonsCtrl\$svbtn",
            ),
            extra = extra,
            nameContainsAny = listOf("save", "gem", "svbtn"),
        ).fields
    }

    /**
     * Delete a private/local event. Demo and local-private ids mutate the in-memory list.
     * Live Lectio events require a successful postback; failures surface to the UI.
     */
    suspend fun deletePrivateEvent(event: ScheduleEvent): AppResult<Unit> {
        val numeric = PrivateEventIds.numericAftaleId(event.id)
        if (event.id.startsWith("local-private") || session.currentStudent?.isDemo == true || numeric == null) {
            localPrivate.delete(event.id)
            return AppResult.Success(Unit)
        }
        val path = PrivateEventIds.updatePath(event.id) ?: "privat_aftale.aspx?aftaleid=$numeric"
        when (val page = client.get(path, FetchPriority.Important)) {
            is AppResult.Success -> {
                val resolved = SmartPostback.resolve(
                    html = page.data.body,
                    preferredTargets = listOf(
                        "m\$Content\$deleteBtn",
                        "m\$Content\$sletbtn",
                        "s\$m\$Content\$deleteBtn",
                        "m\$Content\$savebuttonsCtrl\$db",
                    ),
                    extra = mapOf("aftaleid" to numeric),
                    nameContainsAny = listOf("delete", "slet"),
                )
                return when (val post = client.postForm(path, resolved.fields)) {
                    is AppResult.Success -> {
                        localPrivate.delete(event.id)
                        AppResult.Success(Unit)
                    }
                    is AppResult.Failure -> post
                }
            }
            is AppResult.Failure -> {
                return when (
                    val post = client.postback(
                        path,
                        "m\$Content\$deleteBtn",
                        mapOf("aftaleid" to numeric),
                    )
                ) {
                    is AppResult.Success -> {
                        localPrivate.delete(event.id)
                        AppResult.Success(Unit)
                    }
                    is AppResult.Failure -> post
                }
            }
        }
    }

    fun localPrivateEventsSnapshot(): List<ScheduleEvent> = localPrivate.snapshot()

    fun clearLocalPrivateEventsForTest() {
        localPrivate.clear()
    }
}
