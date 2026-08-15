package dk.betterw4.android.feature.homework

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.core.cache.EntityOfflineStore
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.feature.demo.DemoData
import kotlinx.coroutines.launch
import java.time.Instant
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Homework list + done flags stored locally per student.
 */
@Singleton
class HomeworkRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
    @Named("entityOffline") private val offline: EntityOfflineStore,
    @ApplicationContext context: Context,
) {
    private val donePrefs = context.getSharedPreferences("homework_done", Context.MODE_PRIVATE)
    @Volatile private var lastHtml: String? = null
    private val scope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO,
    )

    suspend fun load(forceRefresh: Boolean = false): AppResult<List<HomeworkItem>> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)

        if (student.isDemo) {
            return AppResult.Success(DemoData.homework.map { it.copy(done = isDone(student.studentId, it.id)) })
        }
        val key = "homework_${student.studentId}"
        if (!forceRefresh) {
            cache.get(key)?.let { html ->
                lastHtml = html
                return AppResult.Success(parseW4(html, student.studentId))
            }
            offline.get(key)?.let { html ->
                lastHtml = html
                return AppResult.Success(parseW4(html, student.studentId))
            }
        }
        return when (val res = client.get(W4Urls.Routes.ASSESSMENTS)) {
            is AppResult.Failure -> {
                cache.get(key)?.let {
                    lastHtml = it
                    return AppResult.Success(parseW4(it, student.studentId))
                }
                offline.get(key)?.let {
                    lastHtml = it
                    return AppResult.Success(parseW4(it, student.studentId))
                }
                res
            }
            is AppResult.Success -> {
                lastHtml = res.data.body
                cache.put(key, res.data.body)
                offline.put(key, res.data.body)
                AppResult.Success(parseW4(res.data.body, student.studentId))
            }
        }
    }

    private fun parseW4(html: String, studentId: String): List<HomeworkItem> =
        W4AssessmentParser.parse(html).map { item ->
            item.copy(done = item.done || isDone(studentId, item.id))
        }

    suspend fun loadDetail(item: HomeworkItem): AppResult<HomeworkItem> {
        return AppResult.Success(
            item.copy(detailHtml = item.note.ifBlank { item.activityTitle }),
        )
    }

    fun isDone(id: String): Boolean {
        val studentId = session.currentStudent?.studentId ?: return false
        return isDone(studentId, id)
    }

    fun isDone(studentId: String, id: String): Boolean =
        donePrefs.getBoolean(donePrefsKey(studentId, id), false)

    fun toggleDone(id: String, entry: HomeworkItem? = null) {
        val student = session.currentStudent ?: return
        val next = !isDone(student.studentId, id)
        writeLocalDone(student.studentId, id, next, Instant.now())
        if (student.isDemo) return
        val item = entry ?: return
        scope.launch {
            val html = lastHtml ?: return@launch
            val urls = W4AssessmentParser.parseAjaxUrls(html) ?: return@launch
            val url = if (next) urls.confirm else urls.revert
            if (url.isBlank()) return@launch
            client.postAjax(url, W4AssessmentParser.fieldsForStatus(item))
        }
    }

    private fun writeLocalDone(studentId: String, id: String, done: Boolean, at: Instant) {
        donePrefs.edit {
            putBoolean(donePrefsKey(studentId, id), done)
            putLong(atPrefsKey(studentId, id), at.toEpochMilli())
        }
    }

    companion object {
        fun donePrefsKey(studentId: String, entryId: String): String = "$studentId|$entryId"

        fun atPrefsKey(studentId: String, entryId: String): String = "at_$studentId|$entryId"
    }
}
