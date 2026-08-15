package dk.betterlectio.android.feature.homework

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.core.cache.EntityOfflineStore
import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.supabase.HomeworkSyncStatus
import dk.betterlectio.android.feature.supabase.SupabaseHomeworkService
import dk.betterlectio.android.feature.supabase.SupabaseManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Homework list + done flags.
 * Local prefs + optional Supabase LWW merge (iOS: HomeworkViewModel + HomeworkStore).
 */
@Singleton
class HomeworkRepository @Inject constructor(
    private val client: LectioClient,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val supabaseManager: SupabaseManager,
    private val supabaseHomework: SupabaseHomeworkService,
    @Named("entityOffline") private val offline: EntityOfflineStore,
    @ApplicationContext context: Context,
) {
    private val donePrefs = context.getSharedPreferences("homework_done", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** In-flight optimistic writes: entryId → pending (iOS pendingWritesByEntryId). */
    private val pendingWrites = ConcurrentHashMap<String, PendingHomeworkWrite>()

    private data class PendingHomeworkWrite(
        val isDone: Boolean,
        val clientUpdatedAt: Instant,
        val studentId: String,
    )

    suspend fun load(forceRefresh: Boolean = false): AppResult<List<HomeworkItem>> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        // Best-effort remote statuses with LWW merge (never blocks offline)
        if (supabaseManager.isConfigured && !student.isDemo) {
            val remote = supabaseHomework.fetchStatuses(student.gymId, student.studentId)
            mergeRemoteStatuses(student.studentId, remote)
        }

        if (student.isDemo) {
            return AppResult.Success(DemoData.homework.map { it.copy(done = isDone(student.studentId, it.id)) })
        }
        val key = "homework_${student.studentId}"
        if (!forceRefresh) {
            cache.get(key)?.let { html ->
                return AppResult.Success(
                    HomeworkParser.parse(html).map { it.copy(done = isDone(student.studentId, it.id)) },
                )
            }
            offline.get(key)?.let { html ->
                return AppResult.Success(
                    HomeworkParser.parse(html).map { it.copy(done = isDone(student.studentId, it.id)) },
                )
            }
        }
        return when (val res = client.get("material_lektieoversigt.aspx")) {
            is AppResult.Failure -> {
                cache.get(key)?.let {
                    return AppResult.Success(
                        HomeworkParser.parse(it).map { h -> h.copy(done = isDone(student.studentId, h.id)) },
                    )
                }
                offline.get(key)?.let {
                    return AppResult.Success(
                        HomeworkParser.parse(it).map { h -> h.copy(done = isDone(student.studentId, h.id)) },
                    )
                }
                res
            }
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                offline.put(key, res.data.body)
                AppResult.Success(
                    HomeworkParser.parse(res.data.body).map { it.copy(done = isDone(student.studentId, it.id)) },
                )
            }
        }
    }

    suspend fun loadDetail(item: HomeworkItem): AppResult<HomeworkItem> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val html = item.detailHtml
                ?: DemoData.homeworkDetailHtml(item)
            return AppResult.Success(HomeworkDetailLoader.mergeDetail(item, html))
        }
        val href = item.href?.trim().orEmpty()
        if (href.isBlank()) {
            return AppResult.Success(item)
        }
        val path = href
            .removePrefix("https://www.lectio.dk/lectio/${student.gymId}/")
            .removePrefix("/")
        val cacheKey = "homework_detail_${item.id}"
        cache.get(cacheKey)?.let {
            return AppResult.Success(HomeworkDetailLoader.mergeDetail(item, it))
        }
        return when (val res = client.get(path)) {
            is AppResult.Failure -> AppResult.Success(item)
            is AppResult.Success -> {
                cache.put(cacheKey, res.data.body)
                offline.put(cacheKey, res.data.body)
                AppResult.Success(HomeworkDetailLoader.mergeDetail(item, res.data.body))
            }
        }
    }

    fun isDone(id: String): Boolean {
        val studentId = session.currentStudent?.studentId ?: return false
        return isDone(studentId, id)
    }

    fun isDone(studentId: String, id: String): Boolean {
        pendingWrites[id]?.let { pending ->
            if (pending.studentId == studentId) return pending.isDone
        }
        return donePrefs.getBoolean(donePrefsKey(studentId, id), false)
    }

    fun toggleDone(id: String, entry: HomeworkItem? = null) {
        val student = session.currentStudent ?: return
        val next = !isDone(student.studentId, id)
        val clientUpdatedAt = Instant.now()
        // Always persist locally (scoped per student)
        writeLocalDone(student.studentId, id, next, clientUpdatedAt)

        if (student.isDemo) return
        if (!supabaseManager.isConfigured) return
        if (!SupabaseHomeworkService.isSyncableEntryId(id)) return

        pendingWrites[id] = PendingHomeworkWrite(
            isDone = next,
            clientUpdatedAt = clientUpdatedAt,
            studentId = student.studentId,
        )
        val item = entry ?: HomeworkItem(id = id, note = "", activityTitle = "", date = null, done = next)
        scope.launch {
            val didWrite = supabaseHomework.upsertStatus(
                student = student,
                entry = item.copy(done = next),
                isDone = next,
                clientUpdatedAt = clientUpdatedAt,
            )
            val refreshed = supabaseHomework.fetchStatuses(student.gymId, student.studentId)
            val pending = pendingWrites[id]
            if (pending != null &&
                shouldDropPendingAfterRemote(
                    pendingClientUpdatedAt = pending.clientUpdatedAt,
                    thisWriteAt = clientUpdatedAt,
                    remoteClientUpdatedAt = refreshed[id]?.clientUpdatedAt,
                    didWrite = didWrite,
                )
            ) {
                pendingWrites.remove(id)
            }
            mergeRemoteStatuses(student.studentId, refreshed)
        }
    }

    /**
     * LWW merge: remote wins when `remote.clientUpdatedAt >= local.updatedAt`.
     * Pending optimistic writes still win in [isDone] until acknowledged.
     */
    private fun mergeRemoteStatuses(studentId: String, remote: Map<String, HomeworkSyncStatus>) {
        for ((entryId, status) in remote) {
            if (!SupabaseHomeworkService.isSyncableEntryId(entryId)) continue
            val pending = pendingWrites[entryId]
            if (pending != null && pending.studentId == studentId) {
                // Acknowledge when remote is at least as new as our write
                if (!status.clientUpdatedAt.isBefore(pending.clientUpdatedAt)) {
                    pendingWrites.remove(entryId)
                    writeLocalDone(studentId, entryId, status.isDone, status.clientUpdatedAt)
                }
                continue
            }
            val localAt = localUpdatedAt(studentId, entryId)
            if (localAt == null || !status.clientUpdatedAt.isBefore(localAt)) {
                writeLocalDone(studentId, entryId, status.isDone, status.clientUpdatedAt)
            }
        }
    }

    private fun localUpdatedAt(studentId: String, id: String): Instant? {
        val millis = donePrefs.getLong(atPrefsKey(studentId, id), -1L)
        return if (millis > 0) Instant.ofEpochMilli(millis) else null
    }

    private fun writeLocalDone(studentId: String, id: String, done: Boolean, at: Instant) {
        donePrefs.edit {
            putBoolean(donePrefsKey(studentId, id), done)
            putLong(atPrefsKey(studentId, id), at.toEpochMilli())
        }
    }

    companion object {
        /** Exposed for unit tests. */
        fun isSyncableEntryId(entryId: String): Boolean =
            SupabaseHomeworkService.isSyncableEntryId(entryId)

        fun donePrefsKey(studentId: String, entryId: String): String = "$studentId|$entryId"

        fun atPrefsKey(studentId: String, entryId: String): String = "at_$studentId|$entryId"

        /**
         * After a remote upsert+fetch for a specific optimistic write, decide whether to drop pending.
         * Keep pending when write succeeded but remote has not yet acknowledged this timestamp.
         */
        fun shouldDropPendingAfterRemote(
            pendingClientUpdatedAt: Instant,
            thisWriteAt: Instant,
            remoteClientUpdatedAt: Instant?,
            didWrite: Boolean,
        ): Boolean {
            if (pendingClientUpdatedAt != thisWriteAt) return false
            if (remoteClientUpdatedAt != null && !remoteClientUpdatedAt.isBefore(thisWriteAt)) return true
            if (!didWrite) return true
            return false
        }
    }
}
