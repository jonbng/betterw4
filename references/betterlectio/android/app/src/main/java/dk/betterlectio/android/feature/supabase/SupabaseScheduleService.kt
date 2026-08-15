package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.feature.schedule.LessonDetail
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import timber.log.Timber
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Schedule week sync to Supabase (iOS: `SupabaseScheduleService`).
 * Writes through ownership-validating RPCs so schedule replacement is atomic.
 */
@Singleton
class SupabaseScheduleService @Inject constructor(
    private val manager: SupabaseManager,
) {
    suspend fun syncWeek(studentId: String, weekKey: String, events: List<ScheduleEvent>) {
        val client = manager.client ?: run {
            Timber.i("Supabase not configured, skipping schedule sync")
            return
        }
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return

        try {
            val now = TIMESTAMP_FORMAT.format(Instant.now())
            val payload = events.map { event ->
                SupabaseLessonRecord(
                    lessonKey = ScheduleIdentity.lessonKey(event, studentId),
                    lessonDate = event.date.format(DAY_FORMAT),
                    startTime = event.start?.let { "%02d:%02d".format(it.hour, it.minute) }.orEmpty(),
                    endTime = event.end?.let { "%02d:%02d".format(it.hour, it.minute) }.orEmpty(),
                    title = event.title,
                    teacher = event.teacher,
                    room = event.room,
                    status = event.status.name.lowercase(),
                    notes = event.notes,
                    homework = event.homework,
                    sourceUpdatedAt = now,
                )
            }

            val result = client.postgrest.rpc(
                function = "sync_student_week",
                parameters = SyncWeekParams(
                    studentId = studentId,
                    weekKey = weekKey,
                    lessons = payload,
                ),
            ).decodeAs<SyncWeekResult>()

            Timber.i(
                "Synced week %s to Supabase upserted=%d linked=%d removed=%d",
                weekKey,
                result.upserted,
                result.linked,
                result.removed,
            )
        } catch (e: Exception) {
            Timber.w(e, "Supabase schedule sync failed for week %s", weekKey)
        }
    }

    /**
     * Syncs lesson content (homework / notes / blocks) to remote `lessons.content`
     * (iOS: `syncLessonContent`).
     */
    suspend fun syncLessonContent(studentId: String, lessonKey: String, detail: LessonDetail) {
        val client = manager.client ?: return
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return
        try {
            client.postgrest.rpc(
                function = "update_student_lesson_content",
                parameters = UpdateLessonContentParams(
                    studentId = studentId,
                    lessonKey = lessonKey,
                    content = LessonContentPayload.fromDetail(detail),
                    clientUpdatedAt = TIMESTAMP_FORMAT.format(Instant.now()),
                ),
            )
            Timber.d("Synced lesson content for key=%s student=%s", lessonKey, studentId)
        } catch (e: Exception) {
            Timber.w(e, "Failed to sync lesson content for %s", lessonKey)
        }
    }

    @Serializable
    internal data class SyncWeekParams(
        @SerialName("p_student_id") val studentId: String,
        @SerialName("p_week_key") val weekKey: String,
        @SerialName("p_lessons") val lessons: List<SupabaseLessonRecord>,
    )

    @Serializable
    internal data class SyncWeekResult(
        val upserted: Int,
        val linked: Int,
        val removed: Int,
    )

    @Serializable
    internal data class UpdateLessonContentParams(
        @SerialName("p_student_id") val studentId: String,
        @SerialName("p_lesson_key") val lessonKey: String,
        @SerialName("p_content") val content: LessonContentPayload,
        @SerialName("p_client_updated_at") val clientUpdatedAt: String,
    )

    /**
     * Shape compatible with iOS `LessonContent` JSON stored on `lessons.content`.
     */
    @Serializable
    data class LessonContentPayload(
        val teacherNote: String? = null,
        val items: List<LessonContentItemPayload> = emptyList(),
    ) {
        companion object {
            fun fromDetail(detail: LessonDetail): LessonContentPayload {
                val note = detail.note?.takeIf { it.isNotBlank() }
                val homeworkText = detail.homework?.takeIf { it.isNotBlank() }
                val items = buildList {
                    if (!homeworkText.isNullOrBlank()) {
                        add(
                            LessonContentItemPayload(
                                id = "${detail.eventId}-hw",
                                title = null,
                                note = null,
                                blocks = listOf(
                                    ContentBlockPayload(
                                        type = "paragraph",
                                        inlines = listOf(InlinePayload(type = "text", text = homeworkText)),
                                    ),
                                ),
                                links = detail.resources.map {
                                    LessonLinkPayload(
                                        title = it.title,
                                        url = it.url,
                                        type = if (it.isFile) "file" else "external",
                                    )
                                },
                                isHomework = true,
                            ),
                        )
                    }
                    detail.contentBlocks.forEachIndexed { index, block ->
                        if (block.text.isBlank()) return@forEachIndexed
                        add(
                            LessonContentItemPayload(
                                id = "${detail.eventId}-b$index",
                                title = if (block.kind == "heading") block.text else null,
                                note = if (block.kind == "note") block.text else null,
                                blocks = listOf(
                                    ContentBlockPayload(
                                        type = block.kind.ifBlank { "paragraph" },
                                        inlines = listOf(InlinePayload(type = "text", text = block.text)),
                                    ),
                                ),
                                links = emptyList(),
                                isHomework = false,
                            ),
                        )
                    }
                }
                return LessonContentPayload(teacherNote = note, items = items)
            }
        }
    }

    @Serializable
    data class LessonContentItemPayload(
        val id: String,
        val title: String? = null,
        val note: String? = null,
        val blocks: List<ContentBlockPayload> = emptyList(),
        val links: List<LessonLinkPayload> = emptyList(),
        val isHomework: Boolean = true,
    )

    @Serializable
    data class ContentBlockPayload(
        val type: String,
        val inlines: List<InlinePayload> = emptyList(),
    )

    @Serializable
    data class InlinePayload(
        val type: String,
        val text: String? = null,
        val url: String? = null,
    )

    @Serializable
    data class LessonLinkPayload(
        val title: String,
        val url: String,
        val type: String,
    )

    @Serializable
    internal data class SupabaseLessonRecord(
        @SerialName("lesson_key") val lessonKey: String,
        @SerialName("lesson_date") val lessonDate: String,
        @SerialName("start_time") val startTime: String,
        @SerialName("end_time") val endTime: String,
        val title: String,
        val teacher: String? = null,
        val room: String? = null,
        val status: String,
        val notes: String? = null,
        val homework: String? = null,
        @SerialName("source_updated_at") val sourceUpdatedAt: String,
    )

    companion object {
        private val DAY_FORMAT: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
        private val TIMESTAMP_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)
    }
}
