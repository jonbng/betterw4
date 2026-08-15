package dk.betterlectio.android.feature.messages

import android.net.Uri
import java.time.LocalDateTime
import java.time.Instant

data class MessageFolder(
    val id: String,
    val displayName: String,
) {
    companion object {
        val NEWEST = MessageFolder("-70", "Nyeste")
        val UNREAD = MessageFolder("-40", "Ulæst")
        val INBOX = MessageFolder("-10", "Egne beskeder")
        val SENT = MessageFolder("-80", "Sendte beskeder")
        val DELETED = MessageFolder("-60", "Alle slettede")
        val defaults = listOf(NEWEST, UNREAD, INBOX, SENT, DELETED)
    }
}

data class MessageThread(
    val id: String,
    val topic: String,
    /** Latest sender display name (title attribute when present). */
    val sender: String,
    val dateChanged: LocalDateTime?,
    val folderId: String,
    val normalizedId: String = id,
    val unread: Boolean = false,
    val flagged: Boolean = false,
    /** Lectio context-card id when present on the list row (`S…` / `T…`). */
    val senderEntityId: String? = null,
    /** `STUDENT` / `TEACHER` when inferred from list row fonticon classes. */
    val senderKind: String? = null,
)

data class MessageAttachment(
    val name: String,
    val url: String,
)

enum class MessageReactionEmoji(val glyph: String) {
    THUMBS_UP("👍"),
    HEART("❤️"),
    LAUGH("😂"),
    SURPRISED("😮"),
    SAD("😢"),
    THUMBS_DOWN("👎");

    companion object {
        fun fromGlyph(value: String?): MessageReactionEmoji? = entries.firstOrNull { it.glyph == value }
    }
}

data class MessageLocator(
    val senderKey: String,
    val sentAt: String,
    val occurrence: Int,
)

data class MessageReactionParticipant(
    val key: String,
    val name: String,
    val isOwn: Boolean,
)

data class MessageReactionGroup(
    val emoji: MessageReactionEmoji,
    val reactors: List<MessageReactionParticipant>,
)

data class ThreadEntry(
    val id: String,
    val topic: String?,
    val contentHtml: String?,
    val senderName: String?,
    val sentAt: LocalDateTime?,
    val editedAt: Instant? = null,
    val attachments: List<MessageAttachment> = emptyList(),
    val senderEntityId: String? = null,
    val senderKind: String? = null,
    val locator: MessageLocator? = null,
    val reactions: List<MessageReactionGroup> = emptyList(),
    val ownReaction: MessageReactionEmoji? = null,
    /** Present only when Lectio grants edit permission for this row. */
    val editPostbackTarget: String = "",
) {
    val attachmentNames: List<String> get() = attachments.map { it.name }
}

data class MessageEditDraft(
    val thread: MessageThread,
    val locator: MessageLocator,
    val title: String,
    val body: String,
    val signatureSuffix: String,
    internal val editHtml: String,
    internal val formAction: String,
    internal val titleField: String,
    internal val bodyField: String,
    internal val saveTarget: String,
)

data class MessageThreadDetail(
    val thread: MessageThread,
    val entries: List<ThreadEntry>,
    val receivers: List<String> = emptyList(),
    /** Lectio context-card ids for thread recipients (`S…` / `T…`) — signature skip. */
    val receiverEntityIds: List<String> = emptyList(),
    /** Fresh row-scoped edit targets for the signed-in user's reaction carriers. */
    val ownReactionCarrierTargets: Map<MessageLocator, String> = emptyMap(),
)

/**
 * Local attachment selected in compose/reply UI (uploaded at send time).
 */
data class ComposeAttachment(
    val uri: Uri,
    val displayName: String,
    val mimeType: String,
    val sizeBytes: Long? = null,
)

data class ComposeMessageDraft(
    val subject: String,
    /** BBCode body (Lectio `EditModeContentBBTB`). */
    val body: String,
    val recipientIds: List<String>,
    val recipientNames: List<String>,
    /** When true, inject Lectio `RepliesNotAllowedChkBox=on` on compose postbacks. */
    val repliesNotAllowed: Boolean = false,
    val attachments: List<ComposeAttachment> = emptyList(),
)

data class MessageRecipient(
    val id: String,
    val name: String,
    val kind: String = "person",
)

/**
 * Resolved attachment field names from a compose/reply form HTML page.
 */
data class MessageAttachTargets(
    val docIdFieldName: String,
    val postbackTarget: String,
)
