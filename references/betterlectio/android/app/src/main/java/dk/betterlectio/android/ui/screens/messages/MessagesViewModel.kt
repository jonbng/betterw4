package dk.betterlectio.android.ui.screens.messages

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.posthog.PostHog
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterlectio.android.R
import dk.betterlectio.android.core.i18n.UiText
import dk.betterlectio.android.core.i18n.toUiText
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.messages.ComposeAttachment
import dk.betterlectio.android.feature.messages.ComposeMessageDraft
import dk.betterlectio.android.feature.messages.MessageFolder
import dk.betterlectio.android.feature.messages.MessageEditDraft
import dk.betterlectio.android.feature.messages.MessageRecipient
import dk.betterlectio.android.feature.messages.MessageLocator
import dk.betterlectio.android.feature.messages.MessageReactionEmoji
import dk.betterlectio.android.feature.messages.MessageReactionGroup
import dk.betterlectio.android.feature.messages.MessageReactionParticipant
import dk.betterlectio.android.feature.messages.MessageRepository
import dk.betterlectio.android.feature.messages.MessageThread
import dk.betterlectio.android.feature.messages.MessageThreadDetail
import dk.betterlectio.android.feature.messages.PendingComposeRecipient
import dk.betterlectio.android.feature.review.ReviewPromptCoordinator
import dk.betterlectio.android.feature.review.ReviewTrigger
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import javax.inject.Inject

data class MessagesUiState(
    val loading: Boolean = true,
    val folders: List<MessageFolder> = MessageFolder.defaults,
    val selectedFolder: MessageFolder = MessageFolder.NEWEST,
    val threads: List<MessageThread> = emptyList(),
    val detail: MessageThreadDetail? = null,
    val error: AppError? = null,
    val replyText: String = "",
    val replyAttachments: List<ComposeAttachment> = emptyList(),
    val replyError: UiText? = null,
    val reactionPendingTarget: MessageLocator? = null,
    val reactionError: UiText? = null,
    val editDraft: MessageEditDraft? = null,
    val editTitle: String = "",
    val editBody: String = "",
    val editLoading: Boolean = false,
    val editSaving: Boolean = false,
    val editError: UiText? = null,
    val showCompose: Boolean = false,
    val composeSubject: String = "",
    val composeBody: String = "",
    val recipientQuery: String = "",
    val recipientResults: List<MessageRecipient> = emptyList(),
    val selectedRecipients: List<MessageRecipient> = emptyList(),
    val repliesNotAllowed: Boolean = false,
    val composeAttachments: List<ComposeAttachment> = emptyList(),
    val isSending: Boolean = false,
    val composeMessage: UiText? = null,
    /** Bumped when compose should be shown (e.g. directory preselect handoff). */
    val composeNavToken: Int = 0,
)

@HiltViewModel
class MessagesViewModel @Inject constructor(
    private val repository: MessageRepository,
    private val pendingCompose: PendingComposeRecipient,
    private val reviewPromptCoordinator: ReviewPromptCoordinator,
) : ViewModel() {
    private val _state = MutableStateFlow(MessagesUiState())
    val state: StateFlow<MessagesUiState> = _state.asStateFlow()
    val unreadCount = repository.unreadCount

    init {
        refresh()
        viewModelScope.launch {
            pendingCompose.pending.collect { offered ->
                if (offered == null) return@collect
                val recipient = pendingCompose.consume() ?: return@collect
                openCompose(preselected = listOf(recipient))
            }
        }
    }

    fun refresh(force: Boolean = false) {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            when (val res = repository.loadFolder(_state.value.selectedFolder, force)) {
                is AppResult.Success -> _state.update {
                    it.copy(loading = false, threads = res.data)
                }
                is AppResult.Failure -> _state.update {
                    it.copy(loading = false, error = res.error)
                }
            }
            repository.refreshUnreadBadge()
        }
    }

    fun selectFolder(folder: MessageFolder) {
        _state.update { it.copy(selectedFolder = folder) }
        refresh(true)
    }

    fun openThread(thread: MessageThread) {
        PostHog.capture(
            event = "message_thread_opened",
            properties = mapOf("is_unread" to thread.unread),
        )
        viewModelScope.launch {
            // iOS selectThread + markAsRead: optimistic local read, then server READMESSAGE_
            // and unread badge refresh. Opening alone used to leave list/badge stuck on unread.
            val wasUnread = thread.unread
            if (wasUnread) {
                _state.update { s ->
                    s.copy(
                        loading = true,
                        threads = s.threads.map { t ->
                            if (t.id == thread.id) t.copy(unread = false) else t
                        },
                    )
                }
                repository.markRead(thread)
            } else {
                _state.update { it.copy(loading = true) }
            }

            val opened = thread.copy(unread = false)
            when (val res = repository.loadThread(opened, forceNetwork = wasUnread)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        loading = false,
                        detail = res.data.copy(thread = res.data.thread.copy(unread = false)),
                        replyText = "",
                        replyAttachments = emptyList(),
                        replyError = null,
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(loading = false, error = res.error)
                }
            }
            repository.refreshUnreadBadge()
        }
    }

    fun closeDetail() {
        _state.update {
            it.copy(
                detail = null,
                replyText = "",
                replyAttachments = emptyList(),
                replyError = null,
            )
        }
    }

    fun onReplyChange(t: String) {
        _state.update { it.copy(replyText = t, replyError = null) }
    }

    fun addReplyAttachments(uris: List<Uri>) {
        if (uris.isEmpty()) return
        _state.update { s ->
            val existing = s.replyAttachments.toMutableList()
            for (uri in uris) {
                if (existing.size >= MAX_ATTACHMENTS) break
                if (existing.any { it.uri == uri }) continue
                existing += repository.resolveAttachmentMeta(uri)
            }
            s.copy(replyAttachments = existing)
        }
    }

    fun removeReplyAttachment(uri: Uri) {
        _state.update { s ->
            s.copy(replyAttachments = s.replyAttachments.filterNot { it.uri == uri })
        }
    }

    fun sendReply() {
        val detail = _state.value.detail ?: return
        val text = _state.value.replyText.trim()
        if (text.isEmpty() || _state.value.isSending) return
        val attachments = _state.value.replyAttachments
        val sigIds = buildList {
            detail.thread.senderEntityId?.let { add(it) }
            detail.receiverEntityIds.forEach { add(it) }
            detail.entries.mapNotNullTo(this) { it.senderEntityId }
        }.distinct()
        viewModelScope.launch {
            _state.update { it.copy(isSending = true, replyError = null) }
            val res = try {
                withTimeout(SEND_TIMEOUT_MS) {
                    repository.reply(
                        thread = detail.thread,
                        body = text,
                        attachments = attachments,
                        recipientIdsForSignature = sigIds,
                    )
                }
            } catch (_: TimeoutCancellationException) {
                AppResult.Failure(
                    AppError.Unknown("Afsendelse tog for lang tid – tjek netværket og prøv igen"),
                )
            }
            when (res) {
                is AppResult.Success -> {
                    PostHog.capture(
                        event = "message_reply_sent",
                        properties = mapOf(
                            "attachment_count" to attachments.size,
                            "has_formatting" to text.contains('['),
                        ),
                    )
                    _state.update {
                        it.copy(
                            replyText = "",
                            replyAttachments = emptyList(),
                            isSending = false,
                            replyError = null,
                        )
                    }
                    reviewPromptCoordinator.maybePrompt(ReviewTrigger.MessageSent)
                    openThread(detail.thread)
                }
                is AppResult.Failure -> {
                    reviewPromptCoordinator.reportRecentError()
                    _state.update {
                        it.copy(
                            isSending = false,
                            replyError = res.error.toUiText(),
                        )
                    }
                }
            }
        }
    }

    fun react(entryId: String, selectedEmoji: MessageReactionEmoji) {
        val state = _state.value
        val detail = state.detail ?: return
        val entry = detail.entries.firstOrNull { it.id == entryId } ?: return
        val locator = entry.locator ?: return
        if (state.reactionPendingTarget != null || state.isSending) return
        val nextEmoji = selectedEmoji.takeUnless { entry.ownReaction == it }
        val snapshot = detail
        val optimistic = detail.copy(
            entries = detail.entries.map { item ->
                if (item.id != entryId) item else optimisticReaction(item, nextEmoji)
            },
        )
        _state.update {
            it.copy(
                detail = optimistic,
                reactionPendingTarget = locator,
                reactionError = null,
            )
        }
        viewModelScope.launch {
            if (repository.isDemoSession()) {
                _state.update { it.copy(reactionPendingTarget = null) }
                return@launch
            }
            when (val result = repository.setReaction(detail.thread, locator, nextEmoji)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        detail = result.data,
                        reactionPendingTarget = null,
                        reactionError = null,
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(
                        detail = snapshot,
                        reactionPendingTarget = null,
                        reactionError = UiText.Res(R.string.message_reaction_failed),
                    )
                }
            }
        }
    }

    fun clearReactionError() {
        _state.update { it.copy(reactionError = null) }
    }

    fun beginEdit(entryId: String) {
        val detail = _state.value.detail ?: return
        val entry = detail.entries.firstOrNull { it.id == entryId } ?: return
        val locator = entry.locator ?: return
        if (entry.editPostbackTarget.isBlank() || _state.value.editLoading || _state.value.isSending) return
        _state.update { it.copy(editLoading = true, editError = null) }
        viewModelScope.launch {
            when (val result = repository.beginMessageEdit(detail.thread, locator)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        editDraft = result.data,
                        editTitle = result.data.title,
                        editBody = result.data.body,
                        editLoading = false,
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(editLoading = false, editError = result.error.toUiText())
                }
            }
        }
    }

    fun updateEdit(title: String? = null, body: String? = null) {
        _state.update { it.copy(editTitle = title ?: it.editTitle, editBody = body ?: it.editBody, editError = null) }
    }

    fun cancelEdit() {
        if (_state.value.editSaving) return
        _state.update {
            it.copy(editDraft = null, editTitle = "", editBody = "", editError = null, editLoading = false)
        }
    }

    fun saveEdit() {
        val state = _state.value
        val draft = state.editDraft ?: return
        if (state.editSaving || state.editTitle.length > 100 || state.editBody.length + draft.signatureSuffix.length > 100_000) return
        _state.update { it.copy(editSaving = true, editError = null) }
        viewModelScope.launch {
            when (val result = repository.saveMessageEdit(draft, state.editTitle, state.editBody)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        detail = result.data,
                        editDraft = null,
                        editTitle = "",
                        editBody = "",
                        editSaving = false,
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(editSaving = false, editError = result.error.toUiText())
                }
            }
        }
    }

    private fun optimisticReaction(
        entry: dk.betterlectio.android.feature.messages.ThreadEntry,
        nextEmoji: MessageReactionEmoji?,
    ): dk.betterlectio.android.feature.messages.ThreadEntry {
        val groups = entry.reactions.mapNotNull { group ->
            group.copy(reactors = group.reactors.filterNot { it.isOwn })
                .takeIf { it.reactors.isNotEmpty() }
        }.associateBy { it.emoji }.toMutableMap()
        if (nextEmoji != null) {
            val current = groups[nextEmoji]?.reactors.orEmpty()
            groups[nextEmoji] = MessageReactionGroup(
                emoji = nextEmoji,
                reactors = current + MessageReactionParticipant(
                    key = "pending-own",
                    name = "",
                    isOwn = true,
                ),
            )
        }
        return entry.copy(
            reactions = MessageReactionEmoji.entries.mapNotNull(groups::get),
            ownReaction = nextEmoji,
        )
    }

    fun openCompose(preselected: List<MessageRecipient> = emptyList()) {
        _state.update {
            it.copy(
                showCompose = true,
                composeSubject = "",
                composeBody = "",
                recipientQuery = "",
                selectedRecipients = preselected,
                recipientResults = emptyList(),
                repliesNotAllowed = false,
                composeAttachments = emptyList(),
                isSending = false,
                composeMessage = null,
                composeNavToken = it.composeNavToken + 1,
            )
        }
    }

    fun closeCompose() {
        if (_state.value.isSending) return
        _state.update {
            it.copy(
                showCompose = false,
                composeAttachments = emptyList(),
                repliesNotAllowed = false,
            )
        }
    }

    fun updateCompose(subject: String? = null, body: String? = null) {
        _state.update {
            it.copy(
                composeSubject = subject ?: it.composeSubject,
                composeBody = body ?: it.composeBody,
            )
        }
    }

    fun setRepliesNotAllowed(v: Boolean) {
        _state.update { it.copy(repliesNotAllowed = v) }
    }

    fun addComposeAttachments(uris: List<Uri>) {
        if (uris.isEmpty()) return
        _state.update { s ->
            val existing = s.composeAttachments.toMutableList()
            for (uri in uris) {
                if (existing.size >= MAX_ATTACHMENTS) break
                if (existing.any { it.uri == uri }) continue
                existing += repository.resolveAttachmentMeta(uri)
            }
            s.copy(composeAttachments = existing)
        }
    }

    fun removeComposeAttachment(uri: Uri) {
        _state.update { s ->
            s.copy(composeAttachments = s.composeAttachments.filterNot { it.uri == uri })
        }
    }

    fun onRecipientQuery(q: String) {
        _state.update { it.copy(recipientQuery = q) }
        viewModelScope.launch {
            when (val res = repository.searchRecipients(q)) {
                is AppResult.Success -> _state.update { it.copy(recipientResults = res.data) }
                is AppResult.Failure -> Unit
            }
        }
    }

    fun toggleRecipient(r: MessageRecipient) {
        _state.update { s ->
            val selected = s.selectedRecipients.toMutableList()
            if (selected.any { it.id == r.id }) selected.removeAll { it.id == r.id }
            else selected.add(r)
            s.copy(selectedRecipients = selected)
        }
    }

    fun sendCompose() {
        val s = _state.value
        if (s.isSending) return
        viewModelScope.launch {
            _state.update { it.copy(isSending = true, composeMessage = null) }
            val draft = ComposeMessageDraft(
                subject = s.composeSubject,
                body = s.composeBody,
                recipientIds = s.selectedRecipients.map { it.id },
                recipientNames = s.selectedRecipients.map { it.name },
                repliesNotAllowed = s.repliesNotAllowed,
                attachments = s.composeAttachments,
            )
            val res = try {
                withTimeout(SEND_TIMEOUT_MS) {
                    repository.compose(draft)
                }
            } catch (_: TimeoutCancellationException) {
                AppResult.Failure(
                    AppError.Unknown("Afsendelse tog for lang tid – tjek netværket og prøv igen"),
                )
            }
            when (res) {
                is AppResult.Success -> {
                    PostHog.capture(
                        event = "message_composed_sent",
                        properties = mapOf(
                            "recipient_count" to s.selectedRecipients.size,
                            "attachment_count" to s.composeAttachments.size,
                            "replies_not_allowed" to s.repliesNotAllowed,
                            "has_formatting" to s.composeBody.contains('['),
                        ),
                    )
                    _state.update {
                        it.copy(
                            showCompose = false,
                            isSending = false,
                            composeMessage = UiText.Res(R.string.message_sent),
                            recipientQuery = "",
                            composeAttachments = emptyList(),
                            repliesNotAllowed = false,
                        )
                    }
                    reviewPromptCoordinator.maybePrompt(ReviewTrigger.MessageSent)
                }
                is AppResult.Failure -> {
                    reviewPromptCoordinator.reportRecentError()
                    _state.update {
                        it.copy(isSending = false, composeMessage = res.error.toUiText())
                    }
                }
            }
        }
    }

    fun markRead() {
        val detail = _state.value.detail ?: return
        markThreadRead(detail.thread, fromDetail = true)
    }

    fun markUnread() {
        val detail = _state.value.detail ?: return
        markThreadUnread(detail.thread)
    }

    fun markThreadRead(thread: MessageThread, fromDetail: Boolean = false) {
        viewModelScope.launch {
            repository.markRead(thread)
            applyUnreadLocally(threadId = thread.id, unread = false)
            repository.refreshUnreadBadge()
            if (fromDetail) {
                openThread(thread.copy(unread = false))
            }
        }
    }

    fun markThreadUnread(thread: MessageThread) {
        viewModelScope.launch {
            repository.markUnread(thread)
            applyUnreadLocally(threadId = thread.id, unread = true)
            repository.refreshUnreadBadge()
        }
    }

    private fun applyUnreadLocally(threadId: String, unread: Boolean) {
        _state.update { s ->
            s.copy(
                threads = s.threads.map { t ->
                    if (t.id == threadId) t.copy(unread = unread) else t
                },
                detail = s.detail?.let { d ->
                    if (d.thread.id == threadId) d.copy(thread = d.thread.copy(unread = unread)) else d
                },
            )
        }
    }

    fun deleteCurrent() {
        val detail = _state.value.detail ?: return
        deleteThread(detail.thread)
    }

    fun deleteThread(thread: MessageThread) {
        viewModelScope.launch {
            repository.deleteThread(thread)
            _state.update { s ->
                s.copy(
                    detail = if (s.detail?.thread?.id == thread.id) null else s.detail,
                    threads = s.threads.filterNot { it.id == thread.id },
                )
            }
            repository.refreshUnreadBadge()
        }
    }

    fun toggleFlag() {
        val detail = _state.value.detail ?: return
        toggleThreadFlag(detail.thread)
    }

    fun toggleThreadFlag(thread: MessageThread) {
        viewModelScope.launch {
            when (val res = repository.toggleFlag(thread)) {
                is AppResult.Success -> {
                    _state.update {
                        it.copy(
                            detail = it.detail?.let { d ->
                                if (d.thread.id == res.data.id) d.copy(thread = res.data) else d
                            },
                            threads = it.threads.map { t ->
                                if (t.id == res.data.id) res.data else t
                            },
                        )
                    }
                }
                is AppResult.Failure -> Unit
            }
        }
    }

    companion object {
        const val MAX_ATTACHMENTS = 10

        /** Wall-clock budget for multi-step Lectio compose/reply (includes queue wait). */
        private const val SEND_TIMEOUT_MS = 120_000L
    }
}
