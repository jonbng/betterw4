package dk.betterlectio.android.feature.messages

import dk.betterlectio.android.core.util.LectioDateUtils
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Message list + thread detail.
 * Thread id normalization: Flutter (`_$_` segment).
 * List flags / mobile layout: iOS MessageParser.
 * Detail timestamps: strip sender name before parse (Flutter/iOS).
 */
object MessageParser {

    fun parseThreadList(html: String, fallbackFolderId: String = MessageFolder.NEWEST.id): List<MessageThread> {
        val doc = Jsoup.parse(html)
        val folderId = doc.getElementById("s_m_Content_Content_ListGridSelectionTree_folders")
            ?.attr("value")
            ?.ifBlank { null }
            ?: fallbackFolderId

        // Desktop tables first (Flutter exact + iOS fuzzy), then iOS mobile layouts
        val table = doc.selectFirst("table#s_m_Content_Content_threadGV_ctl00")
            ?: doc.selectFirst("table[id*=threadGV]")
            ?: doc.selectFirst("table.ls-table-layout5")

        if (table != null) {
            val rows = table.select("tr").drop(1)
            val fromTable = rows.mapNotNull { row -> parseThreadRow(row, folderId) }
            if (fromTable.isNotEmpty()) return fromTable
        }

        // iOS mobile: div.message-list-thread-container
        val mobile = doc.select("div.message-list-thread-container")
        if (mobile.isNotEmpty()) {
            return mobile.mapNotNull { parseMobileThread(it, folderId) }
        }

        return emptyList()
    }

    private fun parseThreadRow(row: Element, folderId: String): MessageThread? {
        val cells = row.select("td")
        if (cells.size < 4) return null

        val link = cells.mapNotNull { it.selectFirst("a") }.firstOrNull() ?: return null
        val onclick = link.attr("onclick")
        val href = link.attr("href")
        val id = extractThreadId(onclick, href) ?: return null
        val topic = link.text().trim().ifBlank { cells.getOrNull(3)?.text()?.trim().orEmpty() }
        if (topic.isBlank()) return null

        // Cell 4 = latest sender (extension/iOS list avatar); cell 5 = first sender.
        val latestPerson = parsePersonCell(cells.getOrNull(4))
            ?: parsePersonCell(cells.getOrNull(5))
        // Mobile block also carries the latest sender with a full title attribute.
        val mobilePerson = row.selectFirst("div.message-list-thread-from span[title], div.message-list-thread-from span")
            ?.let { parsePersonElement(it) }
        val person = when {
            latestPerson != null && latestPerson.name.isNotBlank() -> latestPerson
            mobilePerson != null && mobilePerson.name.isNotBlank() -> mobilePerson
            else -> PersonRef("", null, null)
        }

        val dateRaw = cells.getOrNull(7)?.text()?.trim()
            ?: cells.lastOrNull()?.text()?.trim()
            ?: ""
        val date = LectioDateUtils.parseLectioDate(dateRaw)

        // iOS: row class "unread"; also Danish class / text heuristics
        val unread = row.hasClass("ulæst") ||
            row.className().contains("unread", true) ||
            cells.any { it.text().contains("Ulæst", true) }

        // iOS: img[title*=flag] with flagon src
        val flagged = row.select("img[title*=flag], img[title*=Flag]").any {
            it.attr("src").contains("flagon", ignoreCase = true)
        }

        return MessageThread(
            id = id,
            topic = topic,
            sender = person.name,
            dateChanged = date,
            folderId = folderId,
            normalizedId = normalizeThreadId(id),
            unread = unread,
            flagged = flagged,
            senderEntityId = person.entityId,
            senderKind = person.kind,
        )
    }

    private fun parseMobileThread(container: Element, folderId: String): MessageThread? {
        val link = container.selectFirst("a[id*=EmneMobil], a") ?: return null
        val onclick = link.attr("onclick")
        val href = link.attr("href")
        val id = extractThreadId(onclick, href) ?: return null
        val topic = link.text().trim()
        if (topic.isBlank()) return null
        val person = container.selectFirst("span[title], .message-list-sender, span")
            ?.let { parsePersonElement(it) }
            ?: PersonRef("", null, null)
        val dateRaw = container.selectFirst(".message-list-date, .lpm-datetime, .message-list-thread-datetime, div")
            ?.text()?.trim().orEmpty()
        val date = LectioDateUtils.parseLectioDate(dateRaw)
        val unread = container.className().contains("unread", true) ||
            container.hasClass("ulæst") ||
            container.parent()?.className()?.contains("unread", true) == true
        val flagged = container.select("img[title*=flag]").any {
            it.attr("src").contains("flagon", ignoreCase = true)
        }
        return MessageThread(
            id = id,
            topic = topic,
            sender = person.name,
            dateChanged = date,
            folderId = folderId,
            normalizedId = normalizeThreadId(id),
            unread = unread,
            flagged = flagged,
            senderEntityId = person.entityId,
            senderKind = person.kind,
        )
    }

    private data class PersonRef(
        val name: String,
        val entityId: String?,
        val kind: String?,
    )

    private fun parsePersonCell(cell: Element?): PersonRef? {
        if (cell == null) return null
        val el = cell.selectFirst("[data-lectiocontextcard], [data-lectioContextCard], span[title], span")
            ?: return null
        return parsePersonElement(el)
    }

    private fun parsePersonElement(el: Element): PersonRef {
        val entityId = el.attr("data-lectiocontextcard").ifBlank {
            el.attr("data-lectioContextCard")
        }.ifBlank {
            el.selectFirst("[data-lectiocontextcard], [data-lectioContextCard]")
                ?.let { it.attr("data-lectiocontextcard").ifBlank { it.attr("data-lectioContextCard") } }
                .orEmpty()
        }.ifBlank { null }

        val title = el.attr("title").trim()
        val text = el.text().trim()
        // Prefer full title ("Name (code)") over abbreviated cell text ("MPS")
        val name = title.ifBlank { text }

        val classes = el.className()
        val kind = when {
            classes.contains("prepend-fonticon-teacher") -> "TEACHER"
            classes.contains("prepend-fonticon-student") -> "STUDENT"
            entityId?.startsWith("T", ignoreCase = true) == true -> "TEACHER"
            entityId?.startsWith("S", ignoreCase = true) == true -> "STUDENT"
            else -> null
        }
        return PersonRef(name = name, entityId = entityId, kind = kind)
    }

    /**
     * Lectio control ids look like `$ABC_$_42`. Flutter uses the segment after `_$_`.
     * (Not [substringAfterLast] of `_$`, which incorrectly yields `_42`.)
     */
    fun normalizeThreadId(id: String): String {
        val marker = "_\$_"
        val idx = id.indexOf(marker)
        if (idx < 0) return id
        return id.substring(idx + marker.length).ifBlank { id }
    }

    fun parseThreadDetail(html: String, ref: MessageThread): MessageThreadDetail {
        val doc = Jsoup.parse(html)
        val receiverPeople = doc.select(
            "#s_m_Content_Content_MessageThreadCtrl_RecipientsReadMode span, " +
                "#s_m_Content_Content_MessageThreadCtrl_RecipientsReadMode [data-lectiocontextcard], " +
                "#s_m_Content_Content_MessageThreadCtrl_RecipientsReadMode [data-lectioContextCard]",
        ).map { parsePersonElement(it) }
            .filter { it.name.isNotBlank() || !it.entityId.isNullOrBlank() }
            .distinctBy { it.entityId ?: it.name }
        val receivers = receiverPeople.mapNotNull { p ->
            p.name.takeIf { it.isNotBlank() }
        }
        val receiverEntityIds = receiverPeople.mapNotNull { it.entityId?.takeIf(String::isNotBlank) }

        // Prefer MessagesGV rows (iOS), skip textareas; also accept GridRowMessage (Flutter)
        val entryEls = buildList {
            val gv = doc.selectFirst("table[id*=MessagesGV]")
            if (gv != null) {
                for (tr in gv.select("tr")) {
                    if (tr.select("textarea").isNotEmpty()) continue
                    val content = tr.selectFirst(".message-thread-message-content, #GridRowMessage, .message-thread-message")
                        ?: tr.selectFirst("td")
                    if (content != null && tr.selectFirst(".message-thread-message-content, .message-thread-message-sender") != null) {
                        add(tr)
                    }
                }
            }
            if (isEmpty()) {
                addAll(doc.select("#GridRowMessage, .message-thread-message"))
            }
        }

        val rawEntries = entryEls.mapIndexed { index, el ->
            val topic = el.selectFirst(".message-thread-message-header")?.text()?.trim()
            val contentEl = el.selectFirst(".message-thread-message-content")
            val attachments = parseAttachments(contentEl)
            contentEl?.select(".message-attachements, .message-attachments")?.remove()
            val rawContentHtml = contentEl?.html()?.trim().orEmpty()
            val editAudit = MessageEditAudit.extract(rawContentHtml)
            val contentHtml = stripAppSignatures(editAudit.html)

            val senderSpan = el.selectFirst(".message-thread-message-sender span")
            val senderBlock = el.selectFirst(".message-thread-message-sender")
            val person = senderSpan?.let { parsePersonElement(it) }
            val sender = person?.name?.takeIf { it.isNotBlank() }
                ?: senderSpan?.text()?.trim()
                ?: senderBlock?.text()?.trim()?.substringBefore(',')?.trim()
            val infoText = senderBlock?.text().orEmpty()
            val sentAt = parseMessageTimestamp(infoText, sender)
            val editElement = el.selectFirst("a[id*=EditModeToggleBtn], a[onclick*=EditModeToggleBtn]")
            val editScript = editElement?.attr("onclick").orEmpty().ifBlank {
                editElement?.attr("href").orEmpty()
            }
            val editTarget = Regex("""__doPostBack\('([^']+)'""")
                .find(editScript)?.groupValues?.get(1).orEmpty()

            MessageReactionProtocol.RawMessage(
                entry = ThreadEntry(
                    id = "${ref.id}_$index",
                    topic = topic,
                    contentHtml = contentHtml,
                    editedAt = editAudit.editedAt,
                    senderName = sender,
                    sentAt = sentAt,
                    attachments = attachments,
                    senderEntityId = person?.entityId,
                    senderKind = person?.kind,
                    editPostbackTarget = editTarget,
                ),
                rawContentHtml = rawContentHtml,
                editPostbackTarget = editTarget,
            )
        }

        val resolvedReactions = MessageReactionProtocol.resolve(rawEntries)
        val entries = resolvedReactions.entries

        return MessageThreadDetail(
            thread = ref,
            entries = entries.ifEmpty {
                val contentEl = doc.selectFirst(
                    "#s_m_Content_Content_MessageThreadCtrl_MessageContent, .message-thread-message-content",
                )
                val editAudit = MessageEditAudit.extract(contentEl?.html())
                listOf(
                    ThreadEntry(
                        id = ref.id,
                        topic = ref.topic,
                        contentHtml = stripAppSignatures(editAudit.html),
                        editedAt = editAudit.editedAt,
                        senderName = ref.sender,
                        sentAt = ref.dateChanged,
                        attachments = parseAttachments(contentEl),
                        senderEntityId = ref.senderEntityId,
                        senderKind = ref.senderKind,
                    ),
                )
            },
            receivers = receivers,
            receiverEntityIds = receiverEntityIds,
            ownReactionCarrierTargets = resolvedReactions.ownCarriersByTarget
                .mapValues { it.value.editPostbackTarget },
        )
    }

    /**
     * Flutter/iOS: `"Name (class), 04-03-2026 11:05:41"` → parse timestamp only.
     */
    internal fun parseMessageTimestamp(infoText: String, senderName: String?): java.time.LocalDateTime? {
        val t = infoText.trim()
        if (t.isEmpty()) return null
        // Prefer text after last comma (iOS split on ", ")
        val afterComma = t.substringAfterLast(',').trim()
        LectioDateUtils.parseLectioDate(afterComma)?.let { return it }
        if (!senderName.isNullOrBlank()) {
            val stripped = t.removePrefix(senderName).removePrefix(",").trim()
            LectioDateUtils.parseLectioDate(stripped)?.let { return it }
        }
        return LectioDateUtils.parseLectioDate(t)
    }

    /** iOS signature cleanup for BetterLectio / Flutter footers. */
    internal fun stripAppSignatures(html: String?): String? {
        if (html.isNullOrBlank()) return html
        var out: String = html
        listOf(
            "sendt med betterlectio",
            "sendt med BetterLectio",
            "Sendt med BetterLectio",
            "Sendt fra BetterLectio",
        ).forEach { sig ->
            out = out.replace(sig, "", ignoreCase = true)
        }
        return out.trim().ifBlank { null }
    }

    /** Extract attachment name+href pairs from message HTML. */
    fun parseAttachments(root: Element?): List<MessageAttachment> {
        if (root == null) return emptyList()
        // Prefer attachment blocks (Flutter typo + correct spelling); fallback GetFile/document
        val fromBlock = root.select(".message-attachements a, .message-attachments a")
        val links = if (fromBlock.isNotEmpty()) {
            fromBlock
        } else {
            root.select("a[href*=GetFile], a[href*=documentid], a[href*=document]")
        }
        return links
            .mapNotNull { a ->
                val href = a.attr("href").trim()
                if (href.isEmpty()) return@mapNotNull null
                val name = a.text().trim().ifBlank { href.substringAfterLast('/') }
                val url = when {
                    href.startsWith("http") -> href
                    href.startsWith("/") -> "https://www.lectio.dk$href"
                    else -> "https://www.lectio.dk/$href"
                }
                MessageAttachment(name = name, url = url)
            }
            .distinctBy { it.url }
    }

    fun parseAttachmentsFromHtml(html: String): List<MessageAttachment> =
        parseAttachments(Jsoup.parse(html).body())

    /**
     * iOS parseMessageFolders — custom folders from ListGridSelectionTree postbacks / mobile select.
     */
    fun parseMessageFolders(html: String): List<MessageFolder> {
        val doc = Jsoup.parse(html)
        val folders = MessageFolder.defaults.toMutableList()
        val seen = folders.map { it.id }.toMutableSet()

        // Anchors with __doPostBack(..., 'folderId')
        doc.select("a[href*=ListGridSelectionTree], a[onclick*=ListGridSelectionTree]").forEach { a ->
            val onclick = a.attr("onclick") + a.attr("href")
            val m = Regex("""['"](-?\d+)['"]\s*\)""").findAll(onclick).lastOrNull()
                ?: Regex("""folders['"]?\s*,\s*['"](-?\d+)""").find(onclick)
            val id = m?.groupValues?.get(1) ?: return@forEach
            if (id in seen) return@forEach
            val name = a.text().trim().ifBlank { return@forEach }
            seen += id
            folders += MessageFolder(id = id, displayName = name)
        }

        doc.select("select[id*=ListGridSelectionTree] option, select[name*=ListGridSelectionTree] option")
            .forEach { opt ->
                val id = opt.attr("value").trim()
                if (id.isEmpty() || id in seen) return@forEach
                val name = opt.text().trim().ifBlank { return@forEach }
                seen += id
                folders += MessageFolder(id = id, displayName = name)
            }

        return folders
    }

    /**
     * Prefer **numeric** Lectio thread ids (iOS / extension), not the full
     * `$LB2$_MC_$_…` control token. Digits-only ids are safe for Navigation routes
     * and match READMESSAGE_/FLAGMESSAGE_/openThreadArg reconstruction.
     */
    private fun extractThreadId(onclick: String, href: String): String? {
        val blob = "$onclick $href"
        THREAD_ID_NUMERIC.find(blob)?.let { return it.groupValues[1] }
        // Fallback: full `$…` token (older fixtures / odd layouts)
        val dollar = onclick.indexOf('$')
        if (dollar >= 0) {
            val end = onclick.indexOf('\'', dollar).takeIf { it > dollar }
                ?: onclick.indexOf('"', dollar).takeIf { it > dollar }
            if (end != null) {
                return onclick.substring(dollar, end)
            }
        }
        Regex("""threadid=([^&'"]+)""", RegexOption.IGNORE_CASE).find(href)?.let {
            return it.groupValues[1]
        }
        return null
    }

    /** True when HTML is a message thread detail page (not the folder list). */
    fun looksLikeThreadDetail(html: String): Boolean {
        if (html.isBlank() || isLikelyErrorHtml(html)) return false
        // Compose form is not a thread view
        if (html.contains("addRecipientDD") && html.contains("SendMessageBtn") &&
            !html.contains("message-thread-message-sender")
        ) {
            return false
        }
        return html.contains("message-thread-message-content") ||
            html.contains("message-thread-message-sender") ||
            html.contains("MessageThreadCtrl_RecipientsReadMode") ||
            html.contains("RecipientsReadMode") ||
            (html.contains("MessagesGV") && html.contains("message-thread"))
    }

    /** Folder list page with a thread table (or empty table). */
    fun looksLikeThreadList(html: String): Boolean {
        if (html.isBlank() || isLikelyErrorHtml(html)) return false
        return html.contains("threadGV") ||
            html.contains("message-list-thread-container") ||
            html.contains("ListGridSelectionTree")
    }

    private fun isLikelyErrorHtml(html: String): Boolean {
        val lower = html.lowercase()
        return lower.contains("fejlhandled.aspx") ||
            lower.contains("ukendt parameter") ||
            lower.contains("robotdetection")
    }

    private val THREAD_ID_NUMERIC = Regex(
        // Raw string: double $$ so Kotlin does not interpolate $LB2 / $_MC_
        """(?:FLAGMESSAGE|VIEWTHREAD|(?:UN)?HIDEMESSAGE|UNREADMESSAGE|READMESSAGE|\${'$'}LB2\${'$'}_MC_\${'$'}_)(\d+)""",
    )
}
