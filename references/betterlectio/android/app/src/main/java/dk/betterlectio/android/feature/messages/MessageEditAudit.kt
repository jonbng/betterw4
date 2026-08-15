package dk.betterlectio.android.feature.messages

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.TextNode

object MessageEditAudit {
    private val auditRegex = Regex(
        """^Redigeret af (.+?),\s*d\.\s*(\d{1,2})/(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$""",
        RegexOption.IGNORE_CASE,
    )
    private val auditSuffixRegex = Regex(
        """\s*Redigeret af .+?,\s*d\.\s*\d{1,2}/\d{1,2}-\d{4}\s+\d{1,2}:\d{2}(?::\d{2})?\s*$""",
        RegexOption.IGNORE_CASE,
    )
    val copenhagenZone: ZoneId = ZoneId.of("Europe/Copenhagen")

    data class Result(val html: String?, val editedAt: Instant?)

    fun extract(html: String?): Result {
        if (html.isNullOrEmpty()) return Result(html, null)
        val body = Jsoup.parseBodyFragment(html).body()
        var candidate = body.childNodes().lastOrNull()
        while (candidate is TextNode && candidate.wholeText.trim().isEmpty()) {
            val previous = candidate.previousSibling()
            candidate.remove()
            candidate = previous
        }
        val text = when (candidate) {
            is Element -> candidate.text()
            is TextNode -> candidate.wholeText
            else -> return Result(html, null)
        }.replace(Regex("\\s+"), " ").trim()
        val match = auditRegex.matchEntire(text) ?: return Result(html, null)
        val editedAt = runCatching {
            LocalDateTime.of(
                match.groupValues[4].toInt(),
                match.groupValues[3].toInt(),
                match.groupValues[2].toInt(),
                match.groupValues[5].toInt(),
                match.groupValues[6].toInt(),
                match.groupValues[7].ifEmpty { "0" }.toInt(),
            ).atZone(copenhagenZone).toInstant()
        }.getOrNull() ?: return Result(html, null)

        candidate.remove()
        return Result(body.html().trim(), editedAt)
    }

    fun stripTerminalAudit(text: String): String = text.replace(auditSuffixRegex, "").trim()
}

sealed interface MessageEditedTimeValue {
    data object JustNow : MessageEditedTimeValue
    data class Minutes(val count: Int) : MessageEditedTimeValue
    data class Hours(val count: Int) : MessageEditedTimeValue
    data class Days(val count: Int) : MessageEditedTimeValue
    data class Absolute(val value: String) : MessageEditedTimeValue
}

object MessageEditedTimeFormatter {
    fun value(
        editedAt: Instant,
        now: Instant,
        locale: Locale = Locale.getDefault(),
    ): MessageEditedTimeValue {
        val seconds = maxOf(0, ChronoUnit.SECONDS.between(editedAt, now))
        return when {
            seconds < 60 -> MessageEditedTimeValue.JustNow
            seconds < 3_600 -> MessageEditedTimeValue.Minutes((seconds / 60).toInt())
            seconds < 86_400 -> MessageEditedTimeValue.Hours((seconds / 3_600).toInt())
            seconds < 7 * 86_400 -> MessageEditedTimeValue.Days((seconds / 86_400).toInt())
            else -> MessageEditedTimeValue.Absolute(
                DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                    .withLocale(locale)
                    .withZone(MessageEditAudit.copenhagenZone)
                    .format(editedAt),
            )
        }
    }
}
