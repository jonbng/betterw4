package dk.betterw4.android.feature.messages

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.offline.OfflineMessageStore
import dk.betterw4.android.feature.settings.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MessageRepository @Inject constructor(
    private val w4: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val settings: SettingsStore,
    @Suppress("unused") private val offlineMessages: OfflineMessageStore,
    @ApplicationContext private val appContext: Context,
) {
    private val _unreadCount = MutableStateFlow(0)
    val unreadCount: StateFlow<Int> = _unreadCount.asStateFlow()

    /** Demo-mutable state; same instance production demo mode uses. Exposed for tests via companion. */
    internal val demoState = DemoMessageState()

    fun isDemoSession(): Boolean = session.currentStudent?.isDemo == true

    suspend fun loadFolder(
        folder: MessageFolder = MessageFolder.INBOX,
        forceRefresh: Boolean = false,
    ): AppResult<List<MessageThread>> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val list = demoState.listForFolder(folder)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(list)
        }
        val w4Folder = if (folder.id == MessageFolder.SENT.id) folder else MessageFolder.INBOX
        return loadW4Folder(w4Folder, student.studentId, forceRefresh)
    }

    private suspend fun loadW4Folder(
        folder: MessageFolder,
        studentId: String,
        forceRefresh: Boolean,
    ): AppResult<List<MessageThread>> {
        val sent = folder.id == MessageFolder.SENT.id
        val route = if (sent) W4Urls.Routes.MAILER_ARCHIVE else W4Urls.Routes.MAILER_INBOX
        val key = listCacheKey(studentId, folder.id)
        if (!forceRefresh) {
            cache.get(key)?.let { cached ->
                val parsed = W4MailerParser.parseInbox(cached, folder.id)
                return AppResult.Success(parsed)
            }
        }
        return when (val res = w4.get(route)) {
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4MailerParser.parseInbox(it, folder.id)) }
                res
            }
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                val parsed = W4MailerParser.parseInbox(res.data.body, folder.id)
                if (!sent) _unreadCount.value = parsed.count { it.unread }
                AppResult.Success(parsed)
            }
        }
    }

    suspend fun refreshUnreadBadge() {
        loadFolder(MessageFolder.INBOX, forceRefresh = true)
    }

    suspend fun loadThread(
        thread: MessageThread,
        @Suppress("UNUSED_PARAMETER") forceNetwork: Boolean = false,
    ): AppResult<MessageThreadDetail> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(demoState.loadDetail(thread.id))
        }
        return loadW4Thread(thread)
    }

    private suspend fun loadW4Thread(thread: MessageThread): AppResult<MessageThreadDetail> {
        val res = if (!thread.href.isNullOrBlank()) {
            w4.get(thread.href)
        } else {
            w4.get(W4Urls.Routes.MAILER_VIEW, query = mapOf("id" to thread.id))
        }
        val html = when (res) {
            is AppResult.Failure -> return res
            is AppResult.Success -> res.data.body
        }
        val inner = W4Html.contentInner(html) ?: html
        return AppResult.Success(
            MessageThreadDetail(
                thread = thread.copy(unread = false),
                entries = listOf(
                    ThreadEntry(
                        id = thread.id,
                        topic = thread.topic,
                        contentHtml = inner,
                        senderName = thread.sender,
                        sentAt = thread.dateChanged,
                    ),
                ),
            ),
        )
    }

    suspend fun reply(
        thread: MessageThread,
        body: String,
        attachments: List<ComposeAttachment> = emptyList(),
        @Suppress("UNUSED_PARAMETER") recipientIdsForSignature: List<String> = emptyList(),
    ): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            val attNote = if (attachments.isEmpty()) "" else " (+${attachments.size} files)"
            settings.appendNotificationHistory("Reply sent (demo): ${thread.topic}$attNote")
            return AppResult.Success(Unit)
        }
        return unsupportedWrite()
    }

    suspend fun setReaction(
        @Suppress("UNUSED_PARAMETER") thread: MessageThread,
        @Suppress("UNUSED_PARAMETER") target: MessageLocator,
        @Suppress("UNUSED_PARAMETER") emoji: MessageReactionEmoji?,
    ): AppResult<MessageThreadDetail> {
        if (session.currentStudent?.isDemo == true) {
            return AppResult.Failure(AppError.Unknown("Demo reactions are handled locally"))
        }
        return unsupportedWrite()
    }

    suspend fun beginMessageEdit(
        @Suppress("UNUSED_PARAMETER") thread: MessageThread,
        @Suppress("UNUSED_PARAMETER") locator: MessageLocator,
    ): AppResult<MessageEditDraft> {
        return AppResult.Failure(AppError.Unknown("Redigering er ikke tilgængelig"))
    }

    suspend fun saveMessageEdit(
        @Suppress("UNUSED_PARAMETER") draft: MessageEditDraft,
        @Suppress("UNUSED_PARAMETER") title: String,
        @Suppress("UNUSED_PARAMETER") body: String,
    ): AppResult<MessageThreadDetail> = unsupportedWrite()

    suspend fun searchRecipients(query: String): AppResult<List<MessageRecipient>> {
        if (session.currentStudent?.isDemo == true) {
            val q = query.trim().lowercase()
            return AppResult.Success(
                DemoData.directory
                    .filter { q.isEmpty() || it.name.lowercase().contains(q) }
                    .map { MessageRecipient(it.id, it.name, it.kind.name) },
            )
        }
        return AppResult.Success(emptyList())
    }

    suspend fun markRead(thread: MessageThread): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            demoState.markRead(thread.id)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(Unit)
        }
        invalidateListCaches(thread.folderId)
        return AppResult.Success(Unit)
    }

    suspend fun markUnread(thread: MessageThread): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            demoState.markUnread(thread.id)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(Unit)
        }
        invalidateListCaches(thread.folderId)
        return AppResult.Success(Unit)
    }

    private fun invalidateListCaches(folderId: String) {
        val studentId = session.currentStudent?.studentId ?: return
        cache.remove(listCacheKey(studentId, folderId))
        cache.remove(listCacheKey(studentId, MessageFolder.INBOX.id))
    }

    suspend fun deleteThread(thread: MessageThread): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            demoState.delete(thread.id)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(Unit)
        }
        return unsupportedWrite()
    }

    suspend fun toggleFlag(thread: MessageThread): AppResult<MessageThread> {
        if (session.currentStudent?.isDemo == true) {
            val updated = demoState.toggleFlag(thread.id)
                ?: return AppResult.Success(thread.copy(flagged = !thread.flagged))
            return AppResult.Success(updated)
        }
        return AppResult.Success(thread.copy(flagged = !thread.flagged))
    }

    suspend fun compose(draft: ComposeMessageDraft): AppResult<Unit> {
        if (draft.subject.isBlank() || draft.recipientIds.isEmpty()) {
            return AppResult.Failure(AppError.Unknown("Emne og modtager er påkrævet"))
        }
        if (session.currentStudent?.isDemo == true) {
            val attNote = if (draft.attachments.isEmpty()) {
                ""
            } else {
                " (+${draft.attachments.joinToString { it.displayName }})"
            }
            settings.appendNotificationHistory(
                "New message (demo) to ${draft.recipientNames.joinToString()}: ${draft.subject}$attNote",
            )
            return AppResult.Success(Unit)
        }
        return unsupportedWrite()
    }

    fun resolveAttachmentMeta(uri: Uri): ComposeAttachment {
        val resolver = appContext.contentResolver
        var name = "fil"
        var size: Long? = null
        resolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (cursor.moveToFirst()) {
                if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: name
                if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) size = cursor.getLong(sizeIdx)
            }
        }
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        return ComposeAttachment(
            uri = uri,
            displayName = name,
            mimeType = mime,
            sizeBytes = size,
        )
    }

    private fun unsupportedWrite(): AppResult.Failure =
        AppResult.Failure(AppError.Unknown("Sending is not supported on W4 yet"))

    companion object {
        const val COMPOSE_PATH = "mailer/send"

        fun listCacheKey(studentId: String, folderId: String) =
            "messages_${studentId}_${folderId}"

        fun threadCacheKey(studentId: String, normalizedId: String) =
            "message_thread_${studentId}_${normalizedId}"
    }
}
