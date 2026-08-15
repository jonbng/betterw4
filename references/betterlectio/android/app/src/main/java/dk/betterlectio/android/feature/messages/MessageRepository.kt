package dk.betterlectio.android.feature.messages

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.scrape.SmartPostback
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.directory.DirectoryRepository
import dk.betterlectio.android.feature.offline.OfflineMessageStore
import dk.betterlectio.android.feature.settings.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MessageRepository @Inject constructor(
    private val client: LectioClient,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val directoryRepository: DirectoryRepository,
    private val settings: SettingsStore,
    private val offlineMessages: OfflineMessageStore,
    private val documentUpload: DocumentUpload,
    @ApplicationContext private val appContext: Context,
) {
    private val _unreadCount = MutableStateFlow(0)
    val unreadCount: StateFlow<Int> = _unreadCount.asStateFlow()

    /** Demo-mutable state; same instance production demo mode uses. Exposed for tests via companion. */
    internal val demoState = DemoMessageState()

    fun isDemoSession(): Boolean = session.currentStudent?.isDemo == true

    suspend fun loadFolder(
        folder: MessageFolder = MessageFolder.NEWEST,
        forceRefresh: Boolean = false,
    ): AppResult<List<MessageThread>> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val list = demoState.listForFolder(folder)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(list)
        }

        val key = listCacheKey(student.studentId, folder.id)
        if (!forceRefresh) {
            cache.get(key)?.let { cached ->
                // Never trust empty/error cache (e.g. old type=liste fejlhandled pages).
                if (MessageParser.looksLikeThreadList(cached)) {
                    val parsed = MessageParser.parseThreadList(cached, folder.id)
                    if (parsed.isNotEmpty()) {
                        if (folder.id == MessageFolder.UNREAD.id) _unreadCount.value = parsed.size
                        return AppResult.Success(parsed)
                    }
                } else {
                    cache.remove(key)
                }
            }
            val roomCached = offlineMessages.loadFolder(student.studentId, folder.id)
            if (roomCached.isNotEmpty()) {
                if (folder.id == MessageFolder.UNREAD.id) _unreadCount.value = roomCached.count { it.unread }
                return AppResult.Success(roomCached)
            }
        } else {
            cache.remove(key)
        }

        // iOS parity: Lectio rejects `type=liste`. Load via GET?mappeid= then POST folder switch.
        return when (val res = fetchFolderHtml(folder.id)) {
            is AppResult.Failure -> {
                cache.get(key)?.let {
                    val parsed = MessageParser.parseThreadList(it, folder.id)
                    if (parsed.isNotEmpty()) return AppResult.Success(parsed)
                }
                val roomCached = offlineMessages.loadFolder(student.studentId, folder.id)
                if (roomCached.isNotEmpty()) return AppResult.Success(roomCached)
                res
            }
            is AppResult.Success -> {
                val html = res.data
                if (isLectioErrorPage(html) || !MessageParser.looksLikeThreadList(html)) {
                    return AppResult.Failure(
                        AppError.Unknown("Kunne ikke hente beskeder (Lectio fejlside)"),
                    )
                }
                val parsed = MessageParser.parseThreadList(html, folder.id)
                // Only cache when we got a real list page (empty folder is OK if HTML is list UI).
                cache.put(key, html)
                offlineMessages.saveFolder(student.studentId, folder.id, parsed)
                if (folder.id == MessageFolder.UNREAD.id) _unreadCount.value = parsed.size
                timber.log.Timber.d(
                    "messages list folder=%s threads=%d html=%d",
                    folder.id,
                    parsed.size,
                    html.length,
                )
                AppResult.Success(parsed)
            }
        }
    }

    /**
     * iOS [LectioHTTPClient+Messages.fetchMessages]: empty EVENTARGUMENT folder switch.
     */
    private suspend fun fetchFolderHtml(folderId: String): AppResult<String> =
        postBeskederListPageBack(folderId, eventArgument = "")

    /**
     * iOS `postBeskederListPageBack`:
     * GET `beskeder2.aspx?mappeid=X` → POST form with folders=X, __EVENTTARGET=__Page,
     * and the given __EVENTARGUMENT (empty = list, `$LB2$_MC_$_id` = open thread, …).
     */
    private suspend fun postBeskederListPageBack(
        folderId: String,
        eventArgument: String,
        extra: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
    ): AppResult<String> {
        val seedPath = folderListSeedPath(folderId)
        val postPath = folderListPostPath(folderId)
        val page = client.get(seedPath, priority)
        val seedHtml = when (page) {
            is AppResult.Failure -> return AppResult.Failure(page.error)
            is AppResult.Success -> page.data.body
        }
        if (isLectioErrorPage(seedHtml)) {
            return AppResult.Failure(AppError.Unknown("Kunne ikke hente beskeder (Lectio fejlside)"))
        }
        val resolved = SmartPostback.resolve(
            html = seedHtml,
            preferredTargets = listOf(MessagePostbackFields.PAGE_EVENT_TARGET),
            extra = mapOf(
                "__EVENTARGUMENT" to eventArgument,
                MessagePostbackFields.FOLDERS_FIELD to folderId,
            ) + extra,
            nameContainsAny = emptyList(),
        )
        val fields = resolved.fields.toMutableMap()
        fields["__EVENTTARGET"] = MessagePostbackFields.PAGE_EVENT_TARGET
        fields["__EVENTARGUMENT"] = eventArgument
        fields[MessagePostbackFields.FOLDERS_FIELD] = folderId
        return when (val post = client.postForm(postPath, fields, priority)) {
            is AppResult.Failure -> {
                // Seed GET can already hold usable content (folder list); not for open-thread.
                if (eventArgument.isEmpty() && !isLectioErrorPage(seedHtml)) {
                    AppResult.Success(seedHtml)
                } else {
                    AppResult.Failure(post.error)
                }
            }
            is AppResult.Success -> {
                val body = post.data.body
                if (isLectioErrorPage(body)) {
                    if (eventArgument.isEmpty() && !isLectioErrorPage(seedHtml)) {
                        AppResult.Success(seedHtml)
                    } else {
                        AppResult.Failure(AppError.Unknown("Kunne ikke hente beskeder (Lectio fejlside)"))
                    }
                } else {
                    AppResult.Success(body)
                }
            }
        }
    }



    suspend fun refreshUnreadBadge() {
        loadFolder(MessageFolder.UNREAD, forceRefresh = true)
    }

    /**
     * @param forceNetwork Skip HTML cache (e.g. unread open). Cached opens never hit Lectio,
     * so the server would not mark the thread read — iOS always posts the open/read path.
     */
    suspend fun loadThread(
        thread: MessageThread,
        forceNetwork: Boolean = false,
    ): AppResult<MessageThreadDetail> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            // Merge live demo list (flag/unread) into detail so reopen keeps mutations
            return AppResult.Success(demoState.loadDetail(thread.id))
        }

        val cacheKey = threadCacheKey(student.studentId, thread.normalizedId)
        // Unread opens must reach Lectio ($LB2$_MC_$_…) so the thread is marked read.
        if (!forceNetwork && !thread.unread) {
            cache.get(cacheKey)?.let { cached ->
                // Drop poisoned cache: older builds stored list HTML after failed open postbacks.
                if (MessageParser.looksLikeThreadDetail(cached)) {
                    return AppResult.Success(MessageParser.parseThreadDetail(cached, thread))
                }
                cache.remove(cacheKey)
            }
        } else {
            cache.remove(cacheKey)
        }

        val eventArg = openThreadEventArgument(thread)
        timber.log.Timber.d(
            "messages open thread normId=%s folder=%s eventArg=%s",
            thread.normalizedId,
            thread.folderId,
            eventArg,
        )

        // iOS fetchMessageThread / Flutter MessageController.get: list postback opens thread
        // (not type=showthread). Flutter posts the full `$LB2$_MC_$_…` id; iOS rebuilds it.
        return when (
            val res = postBeskederListPageBack(
                folderId = thread.folderId,
                eventArgument = eventArg,
                priority = FetchPriority.Important,
            )
        ) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val html = res.data
                if (!MessageParser.looksLikeThreadDetail(html)) {
                    timber.log.Timber.w(
                        "messages open did not return thread HTML (len=%d) arg=%s",
                        html.length,
                        eventArg,
                    )
                    return AppResult.Failure(
                        AppError.Unknown("Kunne ikke åbne beskeden"),
                    )
                }
                cache.put(cacheKey, html)
                AppResult.Success(MessageParser.parseThreadDetail(html, thread))
            }
        }
    }

    suspend fun reply(
        thread: MessageThread,
        body: String,
        attachments: List<ComposeAttachment> = emptyList(),
        recipientIdsForSignature: List<String> = emptyList(),
    ): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            val attNote = if (attachments.isEmpty()) "" else " (+${attachments.size} filer)"
            settings.appendNotificationHistory("Svar sendt (demo): ${thread.topic}$attNote")
            return AppResult.Success(Unit)
        }
        // Seed reply form from the same iOS thread-open HTML (not type=showthread).
        return when (
            val page = postBeskederListPageBack(
                folderId = thread.folderId,
                eventArgument = openThreadEventArgument(thread),
                priority = FetchPriority.Important,
            )
        ) {
            is AppResult.Failure -> page
            is AppResult.Success -> {
                var html = page.data
                val priority = FetchPriority.Important
                val postPath = folderListPostPath(thread.folderId)

                // Optional attachments before send
                when (val attached = attachAll(html, postPath, attachments, priority)) {
                    is AppResult.Failure -> return attached
                    is AppResult.Success -> html = attached.data
                }

                val finalBody = MessageSignature.appendIfNeeded(
                    body = body,
                    recipientIds = recipientIdsForSignature,
                    disableSignature = settings.disableSignature.value,
                )
                val contentField = SmartPostback.findFieldName(
                    html,
                    listOf(
                        "EditModeContentBBTB",
                        "WriteContent",
                        "CreateNewAnswer",
                        "MessageBody",
                        "txtMessage",
                    ),
                ) ?: MessagePostbackFields.replyVariants.first().contentField
                val titleField = SmartPostback.findFieldName(
                    html,
                    listOf("EditModeHeaderTitleTB", "MessagesSubject"),
                ) ?: MessagePostbackFields.replyVariants.first().titleField
                val titleValue = SmartPostback.existingFieldValue(html, titleField)
                    ?.takeIf { it.isNotBlank() }
                    ?: "Re: ${thread.topic}"
                val sendTarget = MessagePostbackFields.findSendMessageTarget(html)
                timber.log.Timber.d(
                    "messages reply target=%s contentField=%s bodyLen=%d",
                    sendTarget,
                    contentField,
                    finalBody.length,
                )
                val preferredTargets = listOf(sendTarget) +
                    MessagePostbackFields.replyVariants.map { it.sendTarget }
                val resolved = SmartPostback.resolve(
                    html = html,
                    preferredTargets = preferredTargets.distinct(),
                    extra = mapOf(
                        contentField to finalBody,
                        titleField to titleValue,
                    ),
                    nameContainsAny = listOf("SendAnswer", "Send", "Svar", "CreateNewAnswer", "SendMessage"),
                )
                when (
                    val post = client.postForm(postPath, resolved.fields, priority)
                ) {
                    is AppResult.Success -> {
                        val responseHtml = post.data.body
                        if (isLectioErrorPage(responseHtml)) {
                            return AppResult.Failure(
                                AppError.Unknown("Kunne ikke sende svar (Lectio fejlside)"),
                            )
                        }
                        if (!looksLikeReplySendSuccess(responseHtml, finalBody)) {
                            timber.log.Timber.w(
                                "messages reply response did not look successful (len=%d)",
                                responseHtml.length,
                            )
                            return AppResult.Failure(
                                AppError.Unknown("Kunne ikke sende svar – prøv igen"),
                            )
                        }
                        // Drop stale open-thread cache so the new reply is visible on reload.
                        val studentId = session.currentStudent?.studentId
                        if (studentId != null) {
                            val key = threadCacheKey(studentId, thread.normalizedId)
                            cache.remove(key)
                            if (MessageParser.looksLikeThreadDetail(responseHtml)) {
                                cache.put(key, responseHtml)
                            }
                        }
                        invalidateMessageListCache()
                        settings.appendNotificationHistory("Svar sendt: ${thread.topic}")
                        AppResult.Success(Unit)
                    }
                    is AppResult.Failure -> post
                }
            }
        }
    }

    /**
     * Sets, changes, or clears the signed-in user's reaction using only Lectio.
     * Every mutation starts from a freshly opened thread so row targets and
     * ViewState cannot be stale.
     */
    suspend fun setReaction(
        thread: MessageThread,
        target: MessageLocator,
        emoji: MessageReactionEmoji?,
    ): AppResult<MessageThreadDetail> {
        if (session.currentStudent?.isDemo == true) {
            return AppResult.Failure(AppError.Unknown("Demo reactions are handled locally"))
        }
        val page = postBeskederListPageBack(
            folderId = thread.folderId,
            eventArgument = openThreadEventArgument(thread),
            priority = FetchPriority.Important,
        )
        if (page is AppResult.Failure) return page
        val initialHtml = (page as AppResult.Success).data
        if (!MessageParser.looksLikeThreadDetail(initialHtml)) {
            return AppResult.Failure(AppError.Parsing("Kunne ikke åbne beskedtråden"))
        }
        val initialDetail = MessageParser.parseThreadDetail(initialHtml, thread)
        if (initialDetail.entries.none { it.locator == target }) {
            return AppResult.Failure(AppError.Parsing("Den valgte besked findes ikke længere"))
        }
        val envelope = emoji?.let { MessageReactionProtocol.Envelope.Set(it, target) }
            ?: MessageReactionProtocol.Envelope.Clear(target)
        val showSignature = !MessageSignature.shouldSkipSignature(
            recipientIds = initialDetail.receiverEntityIds,
            disableSignature = settings.disableSignature.value,
        )
        val body = MessageReactionProtocol.carrierBody(envelope, showSignature)
        val editTarget = initialDetail.ownReactionCarrierTargets[target]
        val response = if (editTarget.isNullOrBlank()) {
            sendRawThreadReply(initialHtml, thread, body)
        } else {
            editReactionCarrier(initialHtml, thread, editTarget, body)
        }
        if (response is AppResult.Failure) return response
        val responseHtml = (response as AppResult.Success).data
        if (isLectioErrorPage(responseHtml) || !MessageParser.looksLikeThreadDetail(responseHtml)) {
            return AppResult.Failure(AppError.Unknown("Lectio bekræftede ikke reaktionen"))
        }
        val detail = MessageParser.parseThreadDetail(responseHtml, thread)
        val resolved = detail.entries.firstOrNull { it.locator == target }
            ?: return AppResult.Failure(AppError.Unknown("Reaktionen kunne ikke genfindes"))
        if (resolved.ownReaction != emoji || target !in detail.ownReactionCarrierTargets) {
            return AppResult.Failure(AppError.Unknown("Lectio bekræftede ikke reaktionen"))
        }
        val studentId = session.currentStudent?.studentId
        if (studentId != null) {
            cache.remove(threadCacheKey(studentId, thread.normalizedId))
            cache.put(threadCacheKey(studentId, thread.normalizedId), responseHtml)
        }
        invalidateMessageListCache()
        return AppResult.Success(detail)
    }

    private suspend fun sendRawThreadReply(
        html: String,
        thread: MessageThread,
        body: String,
    ): AppResult<String> {
        val contentField = SmartPostback.findFieldName(
            html,
            listOf("EditModeContentBBTB", "WriteContent", "CreateNewAnswer", "MessageBody"),
        ) ?: return AppResult.Failure(AppError.Parsing("Kunne ikke finde reaktionsfeltet"))
        val titleField = SmartPostback.findFieldName(html, listOf("EditModeHeaderTitleTB", "MessagesSubject"))
            ?: return AppResult.Failure(AppError.Parsing("Kunne ikke finde reaktionstitlen"))
        val title = SmartPostback.existingFieldValue(html, titleField)
            ?.takeIf { it.isNotBlank() }
            ?: "Re: ${thread.topic}"
        val sendTarget = MessagePostbackFields.findSendMessageTarget(html)
        if (sendTarget.isBlank()) {
            return AppResult.Failure(AppError.Parsing("Kunne ikke finde send-knappen"))
        }
        val post = SmartPostback.resolve(
            html = html,
            preferredTargets = listOf(sendTarget),
            extra = mapOf(contentField to body, titleField to title),
            nameContainsAny = listOf("SendMessage", "SendAnswer"),
        )
        return when (val result = client.postForm(folderListPostPath(thread.folderId), post.fields)) {
            is AppResult.Failure -> result
            is AppResult.Success -> AppResult.Success(result.data.body)
        }
    }

    private suspend fun editReactionCarrier(
        html: String,
        thread: MessageThread,
        editTarget: String,
        body: String,
    ): AppResult<String> {
        val openFields = SmartPostback.resolve(html, listOf(editTarget)).fields
        val openResult = client.postForm(folderListPostPath(thread.folderId), openFields)
        if (openResult is AppResult.Failure) return openResult
        val editHtml = (openResult as AppResult.Success).data.body
        val fields = parseReactionEditFields(editHtml, editTarget)
            ?: return AppResult.Failure(AppError.Parsing("Kunne ikke åbne reaktionen til redigering"))
        val save = SmartPostback.resolve(
            html = editHtml,
            preferredTargets = listOf(fields.saveTarget),
            extra = mapOf(fields.titleField to fields.title, fields.bodyField to body),
        )
        return when (val result = client.postForm(folderListPostPath(thread.folderId), save.fields)) {
            is AppResult.Failure -> result
            is AppResult.Success -> AppResult.Success(result.data.body)
        }
    }

    suspend fun beginMessageEdit(
        thread: MessageThread,
        locator: MessageLocator,
    ): AppResult<MessageEditDraft> {
        if (session.currentStudent?.isDemo == true) {
            return AppResult.Failure(AppError.Unknown("Redigering er ikke tilgængelig i demo"))
        }
        val fresh = postBeskederListPageBack(
            folderId = thread.folderId,
            eventArgument = openThreadEventArgument(thread),
            priority = FetchPriority.Important,
        )
        if (fresh is AppResult.Failure) return fresh
        val html = (fresh as AppResult.Success).data
        val detail = MessageParser.parseThreadDetail(html, thread)
        val target = detail.entries.firstOrNull { it.locator == locator }
            ?.editPostbackTarget.orEmpty()
        if (target.isBlank()) {
            return AppResult.Failure(AppError.Unknown("Beskeden kan ikke længere redigeres"))
        }
        val open = client.postForm(
            MessageEditProtocol.formAction(html, folderListPostPath(thread.folderId)),
            SmartPostback.resolve(html, listOf(target)).fields,
            FetchPriority.Important,
        )
        if (open is AppResult.Failure) return open
        val editHtml = (open as AppResult.Success).data.body
        val fields = MessageEditProtocol.parseFields(editHtml, target)
            ?: return AppResult.Failure(AppError.Parsing("Kunne ikke åbne beskeden til redigering"))
        val (body, signature) = MessageEditProtocol.splitSignature(fields.body)
        return AppResult.Success(
            MessageEditDraft(
                thread = thread,
                locator = locator,
                title = fields.title,
                body = body,
                signatureSuffix = signature,
                editHtml = editHtml,
                formAction = MessageEditProtocol.formAction(editHtml, folderListPostPath(thread.folderId)),
                titleField = fields.titleField,
                bodyField = fields.bodyField,
                saveTarget = fields.saveTarget,
            ),
        )
    }

    suspend fun saveMessageEdit(
        draft: MessageEditDraft,
        title: String,
        body: String,
    ): AppResult<MessageThreadDetail> {
        if (title.length > 100 || body.length + draft.signatureSuffix.length > 100_000) {
            return AppResult.Failure(AppError.Parsing("Beskeden overskrider Lectios tegnbegrænsning"))
        }
        val post = SmartPostback.resolve(
            html = draft.editHtml,
            preferredTargets = listOf(draft.saveTarget),
            extra = mapOf(
                draft.titleField to title,
                draft.bodyField to (body + draft.signatureSuffix),
            ),
        )
        return when (val result = client.postForm(draft.formAction, post.fields)) {
            is AppResult.Failure -> result
            is AppResult.Success -> {
                val html = result.data.body
                if (isLectioErrorPage(html) || !MessageParser.looksLikeThreadDetail(html)) {
                    AppResult.Failure(AppError.Unknown("Lectio bekræftede ikke redigeringen"))
                } else {
                    val studentId = session.currentStudent?.studentId
                    if (studentId != null) {
                        cache.remove(threadCacheKey(studentId, draft.thread.normalizedId))
                    }
                    invalidateMessageListCache()
                    AppResult.Success(MessageParser.parseThreadDetail(html, draft.thread))
                }
            }
        }
    }

    private fun parseReactionEditFields(html: String, editTarget: String): MessageEditProtocol.Fields? =
        MessageEditProtocol.parseFields(html, editTarget)

    /**
     * Reply succeeded if Lectio still shows the thread and our text appears in it
     * (message body is echoed into the thread after a successful SendMessageBtn postback).
     */
    internal fun looksLikeReplySendSuccess(html: String, sentBody: String): Boolean {
        if (isLectioErrorPage(html)) return false
        if (!MessageParser.looksLikeThreadDetail(html)) return false
        val snippet = sentBody.trim().lineSequence().firstOrNull { it.isNotBlank() }
            ?.take(40)
            .orEmpty()
        if (snippet.isEmpty()) return true
        return html.contains(snippet)
    }

    suspend fun searchRecipients(query: String): AppResult<List<MessageRecipient>> {
        if (session.currentStudent?.isDemo == true) {
            val q = query.trim().lowercase()
            return AppResult.Success(
                DemoData.directory
                    .filter {
                        it.kind == DirectoryEntityKind.STUDENT ||
                            it.kind == DirectoryEntityKind.TEACHER
                    }
                    .filter { q.isEmpty() || it.name.lowercase().contains(q) }
                    .map { MessageRecipient(it.id, it.name, it.kind.name) },
            )
        }
        // Students + teachers (extension compose directory includes both)
        return when (val res = directoryRepository.search(query, kind = null)) {
            is AppResult.Failure -> res
            is AppResult.Success -> AppResult.Success(
                res.data
                    .filter {
                        it.kind == DirectoryEntityKind.STUDENT ||
                            it.kind == DirectoryEntityKind.TEACHER
                    }
                    .map { MessageRecipient(it.id, it.name, it.kind.name) },
            )
        }
    }

    suspend fun markRead(thread: MessageThread): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            demoState.markRead(thread.id)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(Unit)
        }
        // Lectio/extension: __Page + READMESSAGE_<normalizedId> + folders
        postListPageEvent(
            folderId = thread.folderId,
            eventArgument = MessagePostbackFields.readMessageArg(thread.normalizedId),
            fallbackTargets = MessagePostbackFields.markReadTargets,
            threadId = thread.normalizedId,
        )
        // Drop list HTML that still encodes unread so a later non-force load
        // cannot resurrect the badge/row styling before Ulæst is refreshed.
        invalidateListCaches(thread.folderId)
        return AppResult.Success(Unit)
    }

    suspend fun markUnread(thread: MessageThread): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            demoState.markUnread(thread.id)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(Unit)
        }
        // Lectio/extension: __Page + UNREADMESSAGE_<normalizedId> + folders
        postListPageEvent(
            folderId = thread.folderId,
            eventArgument = MessagePostbackFields.unreadMessageArg(thread.normalizedId),
            fallbackTargets = MessagePostbackFields.markUnreadTargets,
            threadId = thread.normalizedId,
        )
        invalidateListCaches(thread.folderId)
        return AppResult.Success(Unit)
    }

    private fun invalidateListCaches(folderId: String) {
        val studentId = session.currentStudent?.studentId ?: return
        cache.remove(listCacheKey(studentId, folderId))
        if (folderId != MessageFolder.UNREAD.id) {
            cache.remove(listCacheKey(studentId, MessageFolder.UNREAD.id))
        }
    }

    suspend fun deleteThread(thread: MessageThread): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            demoState.delete(thread.id)
            _unreadCount.value = demoState.unreadCount()
            return AppResult.Success(Unit)
        }
        // Flutter: HIDEMESSAGE_<normalizedId>
        postListPageEvent(
            folderId = thread.folderId,
            eventArgument = MessagePostbackFields.hideMessageArg(thread.normalizedId),
            fallbackTargets = MessagePostbackFields.deleteTargets,
            threadId = thread.normalizedId,
        )
        return AppResult.Success(Unit)
    }

    /** Toggle flag (demo mutates list; live best-effort postback). */
    suspend fun toggleFlag(thread: MessageThread): AppResult<MessageThread> {
        if (session.currentStudent?.isDemo == true) {
            val updated = demoState.toggleFlag(thread.id)
                ?: return AppResult.Success(thread.copy(flagged = !thread.flagged))
            return AppResult.Success(updated)
        }
        val next = !thread.flagged
        // iOS: FLAGMESSAGE_<id>
        postListPageEvent(
            folderId = thread.folderId,
            eventArgument = MessagePostbackFields.flagMessageArg(thread.normalizedId),
            fallbackTargets = MessagePostbackFields.flagTargets,
            threadId = thread.normalizedId,
            extra = mapOf("flag" to if (next) "1" else "0"),
        )
        return AppResult.Success(thread.copy(flagged = next))
    }

    /**
     * Best-effort list-page action (read/flag/delete). Prefer iOS EVENTARGUMENT path;
     * fall back to legacy button names if the postback fails.
     */
    private suspend fun postListPageEvent(
        folderId: String,
        eventArgument: String,
        fallbackTargets: List<String>,
        threadId: String,
        extra: Map<String, String> = emptyMap(),
    ) {
        when (postBeskederListPageBack(folderId, eventArgument, extra)) {
            is AppResult.Success -> return
            is AppResult.Failure -> { /* try legacy targets */ }
        }
        val postPath = folderListPostPath(folderId)
        val fallbackExtra = mapOf("threadid" to threadId) + extra + mapOf(
            MessagePostbackFields.FOLDERS_FIELD to folderId,
        )
        for (target in fallbackTargets) {
            if (client.postback(postPath, target, fallbackExtra) is AppResult.Success) break
        }
    }

    /**
     * Multi-step Lectio compose (iOS `sendNewMessage` / extension `sendMessageViaIframe`):
     * 1. GET messages page
     * 2. POST NewMessageLnk / NewMessageThreadBtn → compose form
     * 3. POST AddRecipientBtn for each recipient (inp + inpid) + no-reply when set
     * 4. Upload each file to dokumentupload.aspx + attach postback
     * 5. POST SendMessageBtn with title + body[+signature] + no-reply
     *
     * ViewState is sequential — each step uses the previous response HTML.
     */
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
                "Ny besked (demo) til ${draft.recipientNames.joinToString()}: ${draft.subject}$attNote",
            )
            return AppResult.Success(Unit)
        }

        val path = COMPOSE_PATH
        val priority = FetchPriority.Important

        // Step 1: seed list page (never one-shot query types Lectio rejects)
        val seed = when (val page = client.get(path, priority)) {
            is AppResult.Failure -> return page
            is AppResult.Success -> page.data.body
        }
        if (isLectioErrorPage(seed)) {
            return AppResult.Failure(AppError.Unknown("Kunne ikke åbne beskeder (Lectio fejlside)"))
        }

        // Step 2: open compose form
        val openTarget = MessagePostbackFields.findNewMessageTarget(seed)
        var html = when (
            val opened = postFromHtml(path, seed, openTarget, emptyMap(), priority)
        ) {
            is AppResult.Failure -> return opened
            is AppResult.Success -> opened.data
        }
        if (!MessagePostbackFields.looksLikeComposeForm(html)) {
            val retry = postFromHtml(
                path,
                seed,
                MessagePostbackFields.NEW_MESSAGE_LNK,
                emptyMap(),
                priority,
            )
            when (retry) {
                is AppResult.Failure -> return AppResult.Failure(
                    AppError.Unknown("Kunne ikke åbne ny-besked formularen"),
                )
                is AppResult.Success -> {
                    html = retry.data
                    if (!MessagePostbackFields.looksLikeComposeForm(html)) {
                        return AppResult.Failure(
                            AppError.Unknown("Kunne ikke åbne ny-besked formularen"),
                        )
                    }
                }
            }
        }

        val noReplyName = MessagePostbackFields.findNoReplyCheckboxName(html)

        // Step 3: add each recipient
        val names = draft.recipientNames
        draft.recipientIds.forEachIndexed { index, recipientId ->
            val name = names.getOrNull(index).orEmpty()
            val extra = MessagePostbackFields.withNoReply(
                extra = mapOf(
                    MessagePostbackFields.RECIPIENT_INP to name,
                    MessagePostbackFields.RECIPIENT_INPID to recipientId,
                    MessagePostbackFields.COMPOSE_TITLE to "",
                    MessagePostbackFields.COMPOSE_BODY to "",
                    MessagePostbackFields.COMPOSE_ATTACHMENT_DOC_ID to "",
                ),
                repliesNotAllowed = draft.repliesNotAllowed,
                checkboxName = noReplyName,
            )
            when (
                val added = postFromHtml(
                    path = path,
                    html = html,
                    eventTarget = MessagePostbackFields.ADD_RECIPIENT_BTN,
                    extra = extra,
                    priority = priority,
                )
            ) {
                is AppResult.Failure -> return added
                is AppResult.Success -> html = added.data
            }
        }

        // Step 4: upload + attach files
        when (val attached = attachAll(html, path, draft.attachments, priority, draft.repliesNotAllowed, noReplyName)) {
            is AppResult.Failure -> return attached
            is AppResult.Success -> html = attached.data
        }

        // Step 5: send
        val finalBody = MessageSignature.appendIfNeeded(
            body = draft.body,
            recipientIds = draft.recipientIds,
            disableSignature = settings.disableSignature.value,
        )
        val titleField = SmartPostback.findFieldName(
            html,
            listOf("EditModeHeaderTitleTB", "MessagesSubject"),
        ) ?: MessagePostbackFields.COMPOSE_TITLE
        val bodyField = SmartPostback.findFieldName(
            html,
            listOf("EditModeContentBBTB", "WriteContent"),
        ) ?: MessagePostbackFields.COMPOSE_BODY
        val sendExtra = MessagePostbackFields.withNoReply(
            extra = mapOf(
                MessagePostbackFields.RECIPIENT_INP to "",
                MessagePostbackFields.RECIPIENT_INPID to "",
                titleField to draft.subject,
                bodyField to finalBody,
            ),
            repliesNotAllowed = draft.repliesNotAllowed,
            checkboxName = noReplyName,
        )
        val sendTarget = MessagePostbackFields.findSendMessageTarget(html)
        when (
            val sent = postFromHtml(
                path = path,
                html = html,
                eventTarget = sendTarget,
                extra = sendExtra,
                priority = priority,
            )
        ) {
            is AppResult.Failure -> return sent
            is AppResult.Success -> {
                val body = sent.data
                if (!MessagePostbackFields.looksLikeComposeSendSuccess(body)) {
                    return AppResult.Failure(
                        AppError.Unknown("Kunne ikke sende besked – tjek emne og modtagere"),
                    )
                }
                invalidateMessageListCache()
                settings.appendNotificationHistory("Ny besked: ${draft.subject}")
                return AppResult.Success(Unit)
            }
        }
    }

    /**
     * Upload each local file and attach via AttachmentDocChooser postback.
     * Returns updated HTML ViewState after all attaches (or original [html] if none).
     */
    private suspend fun attachAll(
        html: String,
        path: String,
        attachments: List<ComposeAttachment>,
        priority: FetchPriority,
        repliesNotAllowed: Boolean = false,
        noReplyName: String = "",
    ): AppResult<String> {
        if (attachments.isEmpty()) return AppResult.Success(html)
        var current = html
        for (att in attachments) {
            val bytes = readUriBytes(att.uri)
                ?: return AppResult.Failure(AppError.Unknown("Kunne ikke læse fil: ${att.displayName}"))
            val uploaded = documentUpload.upload(att.displayName, att.mimeType, bytes, priority)
            val serializedId = when (uploaded) {
                is AppResult.Failure -> return uploaded
                is AppResult.Success -> uploaded.data
            }
            val targets = MessagePostbackFields.findAttachTargets(current)
                ?: return AppResult.Failure(
                    AppError.Unknown("Kunne ikke finde vedhæftningsfelt på beskedformularen"),
                )
            val attachExtra = MessagePostbackFields.withNoReply(
                extra = mapOf(
                    targets.docIdFieldName to """{"serializedId":"$serializedId"}""",
                ),
                repliesNotAllowed = repliesNotAllowed,
                checkboxName = noReplyName,
            )
            when (
                val post = postFromHtml(
                    path = path,
                    html = current,
                    eventTarget = targets.postbackTarget,
                    extra = attachExtra,
                    priority = priority,
                    eventArgument = "documentId",
                )
            ) {
                is AppResult.Failure -> return AppResult.Failure(
                    AppError.Unknown("Kunne ikke vedhæfte ${att.displayName}"),
                )
                is AppResult.Success -> current = post.data
            }
        }
        return AppResult.Success(current)
    }

    private fun readUriBytes(uri: Uri): ByteArray? = try {
        appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    } catch (_: Exception) {
        null
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

    /**
     * POST using VIEWSTATE/fields from [html] (no intermediate GET).
     * Required for multi-step compose — each response feeds the next postback.
     */
    private suspend fun postFromHtml(
        path: String,
        html: String,
        eventTarget: String,
        extra: Map<String, String>,
        priority: FetchPriority,
        eventArgument: String = "",
    ): AppResult<String> {
        val resolved = SmartPostback.resolve(
            html = html,
            preferredTargets = listOf(eventTarget),
            extra = extra,
        )
        val fields = resolved.fields.toMutableMap()
        fields["__EVENTTARGET"] = eventTarget
        fields["__EVENTARGUMENT"] = eventArgument
        fields.putAll(extra)
        return when (val post = client.postForm(path, fields, priority)) {
            is AppResult.Failure -> AppResult.Failure(post.error)
            is AppResult.Success -> {
                val body = post.data.body
                if (isLectioErrorPage(body)) {
                    AppResult.Failure(AppError.Unknown("Kunne ikke sende besked (Lectio fejlside)"))
                } else {
                    AppResult.Success(body)
                }
            }
        }
    }

    private fun invalidateMessageListCache() {
        val studentId = session.currentStudent?.studentId ?: return
        for (folder in MessageFolder.defaults) {
            cache.remove(listCacheKey(studentId, folder.id))
        }
    }

    companion object {
        /** Compose posts to the bare messages page (iOS/Flutter). */
        const val COMPOSE_PATH = "beskeder2.aspx"

        /** Lectio rejects `type=liste` (fejlhandled: Ukendt parameter: liste). */
        fun folderListSeedPath(folderId: String): String =
            "beskeder2.aspx?mappeid=$folderId"

        fun folderListPostPath(folderId: String): String =
            "beskeder2.aspx?mappeid=$folderId"

        fun listCacheKey(studentId: String, folderId: String) =
            "messages_${studentId}_${folderId}"

        fun threadCacheKey(studentId: String, normalizedId: String) =
            "message_thread_${studentId}_${normalizedId}"

        fun isLectioErrorPage(html: String): Boolean {
            val lower = html.lowercase()
            return lower.contains("fejlhandled.aspx") ||
                lower.contains("ukendt parameter") ||
                (lower.contains("title=fejl") && lower.contains("message="))
        }

        /**
         * Lectio open-thread `__EVENTARGUMENT`.
         * Prefer the raw list-row id (`$LB2$_MC_$_…`) like Flutter; otherwise rebuild from
         * normalized digits like iOS/extension.
         */
        fun openThreadEventArgument(thread: MessageThread): String {
            val raw = thread.id.trim()
            if (raw.contains("LB2") && raw.contains("MC")) return raw
            // Numeric / already-normalized id
            val norm = thread.normalizedId.ifBlank { MessageParser.normalizeThreadId(raw) }
            return MessagePostbackFields.openThreadArg(norm)
        }
    }
}
