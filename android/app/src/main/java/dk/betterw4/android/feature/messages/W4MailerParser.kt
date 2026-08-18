package dk.betterw4.android.feature.messages

import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.W4Yii
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.time.LocalDateTime
import java.time.LocalTime

/**
 * W4 Mailer Yii grid (`mailer/inbox`, `mailer/archive`).
 *
 * Inbox columns: Received, From, Subject.
 * Archive columns: Send date, Subject, Attachment.
 */
object W4MailerParser {
    private val TIME = Regex("""(\d{1,2}):(\d{2})""")
    private val ID = Regex("""(?:\?|&|&amp;)id=(\d+)""")

    fun parseInbox(html: String, folderId: String): List<MessageThread> {
        val table = Jsoup.parse(html).selectFirst("div.grid-view table.items") ?: return emptyList()
        val headers = table.select("thead th").map { it.text().trim().lowercase() }
        val receivedIdx = headers.indexOfFirst { it.contains("received") || it.contains("send date") || it.contains("date") }
            .takeIf { it >= 0 } ?: 0
        val fromIdx = headers.indexOfFirst { it == "from" }.takeIf { it >= 0 }
        val subjectIdx = headers.indexOfFirst { it.contains("subject") }.takeIf { it >= 0 }
            ?: (if (fromIdx != null) fromIdx + 1 else 1)

        return table.select("tbody tr").mapNotNull { row ->
            if (W4Yii.isEmptyRow(row)) return@mapNotNull null
            val cells = row.select("td")
            if (cells.size < 2) return@mapNotNull null
            val subjectCell = cells.getOrNull(subjectIdx) ?: cells.lastOrNull() ?: return@mapNotNull null
            val link = subjectCell.selectFirst("a[href]")
            val subject = (link?.text() ?: subjectCell.text()).trim()
            if (subject.isBlank()) return@mapNotNull null
            val href = link?.attr("href").orEmpty()
            val id = ID.find(href)?.groupValues?.get(1)
                ?: rowId(row)
                ?: subject.hashCode().toString()
            val from = fromIdx?.let { cells.getOrNull(it)?.text()?.trim() }.orEmpty()
            val received = cells.getOrNull(receivedIdx)?.text()?.trim().orEmpty()
            MessageThread(
                id = id,
                topic = subject,
                sender = from.ifBlank { "W4" },
                dateChanged = parseDateTime(received),
                folderId = folderId,
                unread = row.hasClass("unread") || row.selectFirst(".unread") != null,
                href = href.ifBlank { null },
            )
        }
    }

    private fun rowId(row: Element): String? {
        val keys = row.id().removePrefix("yw0_").ifBlank { null }
        return keys ?: ID.find(row.html())?.groupValues?.get(1)
    }

    private fun parseDateTime(raw: String): LocalDateTime? {
        val date = W4Dates.parse(raw.substringBefore(" ").ifBlank { raw }) ?: return null
        val time = TIME.find(raw)
        val localTime = if (time != null) {
            LocalTime.of(time.groupValues[1].toInt(), time.groupValues[2].toInt())
        } else {
            LocalTime.MIDNIGHT
        }
        return LocalDateTime.of(date, localTime)
    }
}
