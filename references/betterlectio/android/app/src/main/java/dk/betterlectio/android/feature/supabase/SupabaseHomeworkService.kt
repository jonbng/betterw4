package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.feature.homework.HomeworkItem
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import timber.log.Timber
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

data class HomeworkSyncStatus(
    val entryId: String,
    val homeworkId: String?,
    val schoolId: Int?,
    val studentId: String?,
    val isDone: Boolean,
    val clientUpdatedAt: Instant,
    val lastModifiedBy: String?,
    val doneUpdatedAt: Instant?,
    val updatedAt: Instant?,
    val lessonDate: LocalDate?,
)

/**
 * Homework done sync via RPCs (iOS: `SupabaseHomeworkService`).
 * - `get_student_homework_statuses`
 * - `upsert_student_homework_status`
 */
@Singleton
class SupabaseHomeworkService @Inject constructor(
    private val manager: SupabaseManager,
) {
    suspend fun fetchStatuses(schoolId: Int, studentId: String): Map<String, HomeworkSyncStatus> {
        val client = manager.client ?: return emptyMap()
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return emptyMap()
        return try {
            val rows = client.postgrest.rpc(
                function = "get_student_homework_statuses",
                parameters = GetStatusesParams(
                    pSchoolId = schoolId,
                    pStudentId = studentId,
                ),
            ).decodeList<HomeworkStatusRow>()

            rows.mapNotNull { it.toStatus() }
                .associateBy { it.entryId }
                .also {
                    Timber.d("homework fetchStatuses returned %d statuses", it.size)
                }
        } catch (e: Exception) {
            Timber.w(e, "homework fetchStatuses failed school=%s student=%s", schoolId, studentId)
            emptyMap()
        }
    }

    suspend fun upsertStatus(
        student: Student,
        entry: HomeworkItem,
        isDone: Boolean,
        clientUpdatedAt: Instant = Instant.now(),
    ): Boolean {
        val client = manager.client ?: return false
        if (!isSyncableEntryId(entry.id)) {
            Timber.d("homework upsertStatus skipped: non-syncable entry=%s", entry.id)
            return false
        }
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return false
        return try {
            val items = buildList {
                if (entry.note.isNotBlank()) {
                    add(
                        HomeworkItemPayload(
                            id = "${entry.id}-note",
                            text = entry.note,
                            activityUrl = entry.href,
                        ),
                    )
                }
            }
            val params = UpsertStatusParams(
                pSchoolId = student.gymId,
                pStudentId = student.studentId,
                pEntryId = entry.id,
                pIsDone = isDone,
                pClientUpdatedAt = TIMESTAMP_FORMAT.format(clientUpdatedAt),
                pLastModifiedBy = "android",
                pLessonDate = entry.date?.format(DAY_FORMAT) ?: LocalDate.now().format(DAY_FORMAT),
                pDisplayDate = entry.date?.toString().orEmpty(),
                pHold = entry.team,
                pTitle = entry.activityTitle.takeIf { it.isNotBlank() },
                pTeacher = null,
                pRoom = null,
                pNote = entry.note.takeIf { it.isNotBlank() },
                pItemsJson = items,
            )
            client.postgrest.rpc(
                function = "upsert_student_homework_status",
                parameters = params,
            )
            Timber.d("homework upsertStatus done entry=%s", entry.id)
            true
        } catch (e: Exception) {
            Timber.w(e, "homework upsertStatus failed entry=%s", entry.id)
            false
        }
    }

    /** Convenience: done ids only (for merging into local prefs). */
    suspend fun fetchDoneEntryIds(schoolId: Int, studentId: String): Set<String> =
        fetchStatuses(schoolId, studentId)
            .filterValues { it.isDone }
            .keys

    @Serializable
    private data class GetStatusesParams(
        @SerialName("p_school_id") val pSchoolId: Int,
        @SerialName("p_student_id") val pStudentId: String,
    )

    @Serializable
    private data class UpsertStatusParams(
        @SerialName("p_school_id") val pSchoolId: Int,
        @SerialName("p_student_id") val pStudentId: String,
        @SerialName("p_entry_id") val pEntryId: String,
        @SerialName("p_is_done") val pIsDone: Boolean,
        @SerialName("p_client_updated_at") val pClientUpdatedAt: String,
        @SerialName("p_last_modified_by") val pLastModifiedBy: String,
        @SerialName("p_lesson_date") val pLessonDate: String,
        @SerialName("p_display_date") val pDisplayDate: String,
        @SerialName("p_hold") val pHold: String,
        @SerialName("p_title") val pTitle: String?,
        @SerialName("p_teacher") val pTeacher: String?,
        @SerialName("p_room") val pRoom: String?,
        @SerialName("p_note") val pNote: String?,
        @SerialName("p_items_json") val pItemsJson: List<HomeworkItemPayload>,
    )

    @Serializable
    private data class HomeworkItemPayload(
        val id: String,
        val text: String,
        @SerialName("file_url") val fileUrl: String? = null,
        @SerialName("activity_url") val activityUrl: String? = null,
        val note: String? = null,
    )

    @Serializable
    private data class HomeworkStatusRow(
        @SerialName("entry_id") val entryId: String? = null,
        @SerialName("homework_id") val homeworkId: String? = null,
        @SerialName("school_id") val schoolId: Int? = null,
        @SerialName("student_id") val studentId: String? = null,
        @SerialName("is_done") val isDone: Boolean = false,
        @SerialName("client_updated_at") val clientUpdatedAt: String? = null,
        @SerialName("last_modified_by") val lastModifiedBy: String? = null,
        @SerialName("done_updated_at") val doneUpdatedAt: String? = null,
        @SerialName("updated_at") val updatedAt: String? = null,
        @SerialName("lesson_date") val lessonDate: String? = null,
    ) {
        fun toStatus(): HomeworkSyncStatus? {
            val id = entryId?.takeIf { it.isNotBlank() } ?: return null
            val clientAt = parseTimestamp(clientUpdatedAt) ?: return null
            return HomeworkSyncStatus(
                entryId = id,
                homeworkId = homeworkId?.takeIf { it.isNotBlank() },
                schoolId = schoolId,
                studentId = studentId?.takeIf { it.isNotBlank() },
                isDone = isDone,
                clientUpdatedAt = clientAt,
                lastModifiedBy = lastModifiedBy?.takeIf { it.isNotBlank() },
                doneUpdatedAt = parseTimestamp(doneUpdatedAt),
                updatedAt = parseTimestamp(updatedAt),
                lessonDate = parseDay(lessonDate),
            )
        }
    }

    companion object {
        private val DAY_FORMAT: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
        private val TIMESTAMP_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

        /** iOS parity: only pure-numeric Lectio activity ids are syncable. */
        fun isSyncableEntryId(entryId: String): Boolean =
            entryId.isNotEmpty() && entryId.all { it.isDigit() }

        fun parseTimestamp(value: String?): Instant? {
            if (value.isNullOrBlank()) return null
            return runCatching { Instant.parse(value) }.getOrNull()
                ?: runCatching {
                    DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse(value, Instant::from)
                }.getOrNull()
        }

        fun parseDay(value: String?): LocalDate? {
            if (value.isNullOrBlank()) return null
            return runCatching { LocalDate.parse(value, DAY_FORMAT) }.getOrNull()
        }
    }
}
