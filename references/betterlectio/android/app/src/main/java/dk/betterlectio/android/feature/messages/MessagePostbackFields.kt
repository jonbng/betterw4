package dk.betterlectio.android.feature.messages

/**
 * Known Lectio ASP.NET field-name variants for message actions.
 * Prefer iOS/Flutter contracts; keep legacy names as fallbacks for SmartPostback.
 *
 * List actions (iOS LectioHTTPClient+Messages / Flutter controller):
 * - `__EVENTTARGET=__Page`
 * - `__EVENTARGUMENT=READMESSAGE_|FLAGMESSAGE_|HIDEMESSAGE_<normalizedId>`
 * - `ListGridSelectionTree$folders=<folderId>`
 *
 * Reply (Flutter/iOS):
 * - EditModeHeaderTitleTB / EditModeContentBBTB + MessagesGV$ctlNN$SendMessageBtn
 */
object MessagePostbackFields {
    data class ReplyTargets(
        val contentField: String,
        val sendTarget: String,
        val titleField: String = "s\$m\$Content\$Content\$MessageThreadCtrl\$EditModeHeaderTitleTB\$tb",
    )

    data class ComposeTargets(
        val recipientField: String,
        val subjectField: String,
        val bodyField: String,
        val sendTarget: String,
    )

    /** iOS/Flutter EditMode reply fields first; legacy CreateNewAnswer last. */
    val replyVariants: List<ReplyTargets> = listOf(
        ReplyTargets(
            contentField = "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$EditModeContentBBTB\$TbxNAME\$tb",
            sendTarget = "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$SendMessageBtn",
            titleField = "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$EditModeHeaderTitleTB\$tb",
        ),
        ReplyTargets(
            contentField = "s\$m\$Content\$Content\$MessageThreadCtrl\$EditModeContentBBTB\$TbxNAME\$tb",
            sendTarget = "s\$m\$Content\$Content\$MessageThreadCtrl\$SendMessageBtn",
            titleField = "s\$m\$Content\$Content\$MessageThreadCtrl\$EditModeHeaderTitleTB\$tb",
        ),
        ReplyTargets(
            contentField = "s\$m\$Content\$Content\$MessageThreadCtrl\$CreateNewAnswer\$WriteContent",
            sendTarget = "s\$m\$Content\$Content\$MessageThreadCtrl\$CreateNewAnswer\$SendAnswerBtn",
        ),
        ReplyTargets(
            contentField = "s\$m\$Content\$Content\$CreateNewAnswer\$WriteContent",
            sendTarget = "s\$m\$Content\$Content\$CreateNewAnswer\$SendAnswerBtn",
        ),
    )

    // ── Multi-step compose (iOS sendNewMessage / Flutter MesssageController.create) ──

    /** Flutter: NewMessageLnk; mobile list also has HeaderContent$NewMessageThreadBtn. */
    const val NEW_MESSAGE_LNK = "s\$m\$Content\$Content\$NewMessageLnk"
    const val NEW_MESSAGE_THREAD_BTN = "s\$m\$HeaderContent\$NewMessageThreadBtn"
    const val NEW_THREAD_BTN = "s\$m\$Content\$Content\$NewThreadBtn"
    const val NEW_MESSAGE_BTN = "s\$m\$Content\$Content\$NewMessageBtn"

    val newMessageTargets: List<String> = listOf(
        NEW_MESSAGE_LNK,
        NEW_MESSAGE_THREAD_BTN,
        NEW_THREAD_BTN,
        NEW_MESSAGE_BTN,
        "s\$m\$Content\$Content\$ListGridSelectionToolbar\$NewThreadBtn",
        "s\$m\$Content\$Content\$CreateNewMessageBtn",
    )

    const val ADD_RECIPIENT_BTN =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$AddRecipientBtn"
    const val RECIPIENT_INP =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$addRecipientDD\$inp"
    const val RECIPIENT_INPID =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$addRecipientDD\$inpid"

    const val COMPOSE_TITLE =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$EditModeHeaderTitleTB\$tb"
    const val COMPOSE_BODY =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$EditModeContentBBTB\$TbxNAME\$tb"
    const val COMPOSE_SEND =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$SendMessageBtn"
    const val COMPOSE_ATTACHMENT_DOC_ID =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$MessagesGV\$ctl02\$AttachmentDocChooser\$selectedDocumentId"

    /**
     * Extension / Lectio native: “Skal ikke kunne besvares”.
     * ASP.NET only posts the field when checked (`on`). Do not confuse with
     * [REPLIES_ALLOWED_CHK] (legacy/unused alternate control name).
     */
    const val REPLIES_NOT_ALLOWED_CHK =
        "s\$m\$Content\$Content\$MessageThreadCtrl\$RepliesNotAllowedChkBox"

    /** Legacy constant — prefer [REPLIES_NOT_ALLOWED_CHK] for compose. */
    const val REPLIES_ALLOWED_CHK =
        "s\$m\$Content\$Content\$RepliesToThreadOrExistingMessageAllowedChk"

    val composeVariants: List<ComposeTargets> = listOf(
        // Flutter/iOS multi-step compose field names (MessagesGV ctl02)
        ComposeTargets(
            recipientField = RECIPIENT_INP,
            subjectField = COMPOSE_TITLE,
            bodyField = COMPOSE_BODY,
            sendTarget = COMPOSE_SEND,
        ),
        ComposeTargets(
            recipientField = "s\$m\$Content\$Content\$createNewMessage\$addRecipientDD\$addRecipientDD",
            subjectField = "s\$m\$Content\$Content\$createNewMessage\$MessagesSubjectBox",
            bodyField = "s\$m\$Content\$Content\$createNewMessage\$CreateNewMessage\$WriteContent",
            sendTarget = "s\$m\$Content\$Content\$createNewMessage\$CreateNewMessage\$CreateMessageButton",
        ),
        ComposeTargets(
            recipientField = "s\$m\$Content\$Content\$addRecipientDD\$addRecipientDD",
            subjectField = "s\$m\$Content\$Content\$MessagesSubjectBox",
            bodyField = "s\$m\$Content\$Content\$CreateNewMessage\$WriteContent",
            sendTarget = "s\$m\$Content\$Content\$CreateNewMessage\$CreateMessageButton",
        ),
    )

    /**
     * Resolve which control opens the compose form on a messages list page.
     * Matches iOS `findNewMessageButton` + Flutter `NewMessageLnk` + mobile header button.
     */
    fun findNewMessageTarget(html: String): String {
        // Prefer concrete control ids present on the page (underscore form).
        for (candidate in newMessageTargets) {
            val idForm = candidate.replace('$', '_')
            if (html.contains("id=\"$idForm\"") ||
                html.contains("id='$idForm'") ||
                html.contains("name=\"$candidate\"")
            ) {
                return candidate
            }
        }

        val postbackPatterns = listOf(
            Regex("""__doPostBack\('([^']*NewThread[^']*)'"""),
            Regex("""__doPostBack\('([^']*NewMessageThread[^']*)'"""),
            Regex("""__doPostBack\('([^']*NewMessage(?!Same)[^']*)'"""),
            Regex("""__doPostBack\('([^']*CreateThread[^']*)'"""),
            Regex("""__doPostBack\('([^']*NyBesked[^']*)'"""),
            // Desktop: PostBackOptions("s$m$…$NewMessageLnk", …) — stop at first quote / &quot;
            Regex(
                """PostBackOptions\(\s*(?:&quot;|["'])((?:(?!&quot;|["']).)*NewMessage(?:Lnk|Btn|ThreadBtn))(?:&quot;|["'])""",
            ),
        )
        for (re in postbackPatterns) {
            for (m in re.findAll(html)) {
                val target = m.groupValues[1].trim()
                if (target.isNotBlank() && !target.contains("SameReceivers")) {
                    return target
                }
            }
        }
        for (candidate in newMessageTargets) {
            val idForm = candidate.replace('$', '_')
            if (html.contains(idForm) || html.contains(candidate)) {
                return candidate
            }
        }
        return NEW_MESSAGE_LNK
    }

    /** Compose form is open when recipient autocomplete + send controls exist. */
    fun looksLikeComposeForm(html: String): Boolean {
        val hasRecipient = html.contains("addRecipientDD") || html.contains("AddRecipientBtn")
        val hasSend = html.contains("SendMessageBtn") || html.contains("CreateMessageButton")
        val hasTitle = html.contains("EditModeHeaderTitleTB") || html.contains("MessagesSubject")
        return hasRecipient && (hasSend || hasTitle)
    }

    /**
     * Resolve “Skal ikke kunne besvares” checkbox form name from compose HTML.
     * Falls back to [REPLIES_NOT_ALLOWED_CHK].
     */
    fun findNoReplyCheckboxName(html: String): String {
        // name="s$m$…$RepliesNotAllowedChkBox" or id with underscores
        val nameRe = Regex(
            """name\s*=\s*["']([^"']*RepliesNotAllowedChkBox)["']""",
            RegexOption.IGNORE_CASE,
        )
        nameRe.find(html)?.groupValues?.getOrNull(1)?.let { return it }
        val idRe = Regex(
            """id\s*=\s*["']([^"']*RepliesNotAllowedChkBox)["']""",
            RegexOption.IGNORE_CASE,
        )
        idRe.find(html)?.groupValues?.getOrNull(1)?.let { id ->
            return id.replace('_', '$')
        }
        return REPLIES_NOT_ALLOWED_CHK
    }

    /**
     * AttachmentDocChooser field + postback target from compose/reply form HTML.
     * Extension: postback target = field name with `$selectedDocumentId` stripped.
     */
    fun findAttachTargets(html: String): MessageAttachTargets? {
        val docIdSuffix = "\$selectedDocumentId"
        val nameRe = Regex(
            """name\s*=\s*["']([^"']*AttachmentDocChooser\${'$'}selectedDocumentId)["']""",
            RegexOption.IGNORE_CASE,
        )
        nameRe.find(html)?.groupValues?.getOrNull(1)?.let { name ->
            val target = name.removeSuffix(docIdSuffix)
            if (target.isNotBlank()) {
                return MessageAttachTargets(docIdFieldName = name, postbackTarget = target)
            }
        }
        // Underscore form in id attributes
        val idRe = Regex(
            """id\s*=\s*["']([^"']*AttachmentDocChooser_selectedDocumentId)["']""",
            RegexOption.IGNORE_CASE,
        )
        idRe.find(html)?.groupValues?.getOrNull(1)?.let { id ->
            val name = id.replace('_', '$')
            val target = name.removeSuffix(docIdSuffix)
            if (target.isNotBlank()) {
                return MessageAttachTargets(docIdFieldName = name, postbackTarget = target)
            }
        }
        // Fallback known MessagesGV ctl02 path if page mentions AttachmentDocChooser
        if (html.contains("AttachmentDocChooser", ignoreCase = true)) {
            return MessageAttachTargets(
                docIdFieldName = COMPOSE_ATTACHMENT_DOC_ID,
                postbackTarget = COMPOSE_ATTACHMENT_DOC_ID.removeSuffix("\$selectedDocumentId"),
            )
        }
        return null
    }

    /** Merge no-reply checkbox into extra fields when enabled (ASP.NET checkbox semantics). */
    fun withNoReply(
        extra: Map<String, String>,
        repliesNotAllowed: Boolean,
        checkboxName: String,
    ): Map<String, String> {
        if (!repliesNotAllowed || checkboxName.isBlank()) return extra
        return extra + (checkboxName to "on")
    }

    /**
     * Prefer live SendMessageBtn postback target from HTML (ctl index may shift after attach).
     */
    fun findSendMessageTarget(html: String): String {
        val re = Regex(
            """__doPostBack\(\s*['"]([^'"]*SendMessageBtn)['"]""",
            RegexOption.IGNORE_CASE,
        )
        re.find(html)?.groupValues?.getOrNull(1)?.let { return it }
        val idRe = Regex(
            """id\s*=\s*["']([^"']*SendMessageBtn)["']""",
            RegexOption.IGNORE_CASE,
        )
        idRe.find(html)?.groupValues?.getOrNull(1)?.let { return it.replace('_', '$') }
        return COMPOSE_SEND
    }

    /**
     * After Send: success if we left the empty compose shell or landed on a thread/list.
     * Fail when Lectio redisplays compose (validation) or returns fejlhandled.
     */
    fun looksLikeComposeSendSuccess(html: String): Boolean {
        val lower = html.lowercase()
        if (lower.contains("fejlhandled.aspx") || lower.contains("ukendt parameter")) {
            return false
        }
        if (html.contains("message-thread-message-content") ||
            html.contains("threadGV") ||
            html.contains("MessagesGV") && html.contains("message-thread-message-sender")
        ) {
            return true
        }
        // Still stuck on compose editor with both add-recipient and send
        if (looksLikeComposeForm(html) && html.contains("SendMessageBtn")) {
            // Lectio keeps compose chrome after successful send only briefly; if title
            // field is still empty-ready and no messages, treat as failure only when
            // no thread content appeared — already checked above.
            // Presence of RecipientsReadMode implies we switched to a real thread view.
            if (html.contains("RecipientsReadMode")) return true
            // If send button still present and no thread content, likely validation fail
            return false
        }
        return !looksLikeComposeForm(html)
    }

    /** Prefer page event args (iOS/Flutter/extension); button names are SmartPostback fallbacks only. */
    fun readMessageArg(normalizedId: String) = "READMESSAGE_$normalizedId"
    /** Lectio list icon for read rows: `__doPostBack('__Page','UNREADMESSAGE_<id>')`. */
    fun unreadMessageArg(normalizedId: String) = "UNREADMESSAGE_$normalizedId"
    fun flagMessageArg(normalizedId: String) = "FLAGMESSAGE_$normalizedId"
    fun hideMessageArg(normalizedId: String) = "HIDEMESSAGE_$normalizedId"

    /**
     * iOS `fetchMessageThread` / extension `openThread` / Flutter `MessageRef.id`:
     * open a thread via list-page postback
     * `__EVENTARGUMENT=$LB2$_MC_$_<id>` (not `type=showthread`).
     *
     * Kotlin string note: must be `"\$LB2\$_MC_\$_$id"` so the segment after `MC` is
     * `_$_` (underscore + dollar + underscore). The previous `"\$LB2\$_MC\$_$id"`
     * produced `$LB2$_MC$_id` and Lectio ignored the open.
     */
    fun openThreadArg(normalizedId: String) = "\$LB2\$_MC_\$_$normalizedId"

    const val PAGE_EVENT_TARGET = "__Page"
    const val FOLDERS_FIELD = "s\$m\$Content\$Content\$ListGridSelectionTree\$folders"

    val markReadTargets = listOf(
        "s\$m\$Content\$Content\$MarkAsReadBtn",
        "s\$m\$Content\$Content\$MarkReadBtn",
        "m\$Content\$Content\$MarkAsReadBtn",
    )

    val markUnreadTargets = listOf(
        "s\$m\$Content\$Content\$MarkAsUnreadBtn",
        "s\$m\$Content\$Content\$MarkUnreadBtn",
        "m\$Content\$Content\$MarkAsUnreadBtn",
    )

    val flagTargets = listOf(
        "s\$m\$Content\$Content\$FlagBtn",
        "s\$m\$Content\$Content\$StarBtn",
        "m\$Content\$Content\$FlagBtn",
    )

    val deleteTargets = listOf(
        "s\$m\$Content\$Content\$DeleteBtn",
        "s\$m\$Content\$Content\$DeleteThreadBtn",
        "m\$Content\$Content\$DeleteBtn",
    )
}
