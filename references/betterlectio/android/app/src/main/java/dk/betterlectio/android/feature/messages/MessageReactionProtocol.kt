package dk.betterlectio.android.feature.messages

import java.net.URI
import java.text.Normalizer
import java.time.format.DateTimeFormatter
import java.util.Base64
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

object MessageReactionProtocol {
    const val DOWNLOAD_URL = "https://betterlectio.dk/download"
    const val FRAGMENT_PREFIX = "blr1."
    private const val MAX_URL_LENGTH = 2_048
    private val json = Json { ignoreUnknownKeys = false }
    private val danishLocale = Locale.forLanguageTag("da-DK")
    private val isoSeconds = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")

    sealed interface Envelope {
        val target: MessageLocator

        data class Set(
            val emoji: MessageReactionEmoji,
            override val target: MessageLocator,
        ) : Envelope

        data class Clear(
            override val target: MessageLocator,
        ) : Envelope
    }

    data class RawMessage(
        val entry: ThreadEntry,
        val rawContentHtml: String,
        val editPostbackTarget: String = "",
    )

    data class Carrier(
        val envelope: Envelope,
        val actor: MessageReactionParticipant,
        val editPostbackTarget: String,
        val index: Int,
    )

    data class ResolvedThread(
        val entries: List<ThreadEntry>,
        val ownCarriersByTarget: Map<MessageLocator, Carrier>,
        val hiddenCarrierCount: Int,
    )

    fun encode(envelope: Envelope): String {
        val payload = buildJsonObject {
            put("v", 1)
            when (envelope) {
                is Envelope.Set -> {
                    put("op", "set")
                    put("emoji", envelope.emoji.glyph)
                }
                is Envelope.Clear -> {
                    put("op", "clear")
                    put("emoji", JsonNull)
                }
            }
            put("target", buildJsonObject {
                put("senderKey", envelope.target.senderKey)
                put("sentAt", envelope.target.sentAt)
                put("occurrence", envelope.target.occurrence)
            })
        }.toString()
        return Base64.getUrlEncoder().withoutPadding().encodeToString(payload.toByteArray(Charsets.UTF_8))
    }

    fun decode(encoded: String): Envelope? = runCatching {
        if (!encoded.matches(Regex("^[A-Za-z0-9_-]+$"))) return null
        val root = json.parseToJsonElement(
            Base64.getUrlDecoder().decode(encoded).toString(Charsets.UTF_8),
        ).jsonObject
        if (root["v"]?.jsonPrimitive?.intOrNull != 1) return null
        val targetObject = root["target"]?.jsonObject ?: return null
        val target = MessageLocator(
            senderKey = targetObject["senderKey"]?.jsonPrimitive?.content ?: return null,
            sentAt = targetObject["sentAt"]?.jsonPrimitive?.content ?: return null,
            occurrence = targetObject["occurrence"]?.jsonPrimitive?.intOrNull ?: return null,
        )
        if (!isValidLocator(target)) return null
        when (root["op"]?.jsonPrimitive?.content) {
            "set" -> Envelope.Set(
                emoji = MessageReactionEmoji.fromGlyph(root["emoji"]?.jsonPrimitive?.content) ?: return null,
                target = target,
            )
            "clear" -> {
                if (root["emoji"] !is JsonNull) return null
                Envelope.Clear(target)
            }
            else -> null
        }
    }.getOrNull()

    fun carrierUrl(envelope: Envelope): String = "$DOWNLOAD_URL#$FRAGMENT_PREFIX${encode(envelope)}"

    fun carrierBody(envelope: Envelope, showSignature: Boolean): String {
        val sentence = when (envelope) {
            is Envelope.Set -> "Reagerede med “${envelope.emoji.glyph}”"
            is Envelope.Clear -> "Fjernede sin reaktion"
        }
        val label = if (showSignature) "Sendt med BetterLectio" else "#"
        return "$sentence\n\n[url=${carrierUrl(envelope)}]$label[/url]"
    }

    fun parseCarrierUrl(rawUrl: String): Envelope? {
        if (rawUrl.isBlank() || rawUrl.length > MAX_URL_LENGTH) return null
        val uri = runCatching { URI(rawUrl) }.getOrNull() ?: return null
        if (!uri.scheme.equals("https", true) || !uri.host.equals("betterlectio.dk", true)) return null
        if (uri.path.trimEnd('/') != "/download" || uri.rawQuery != null) return null
        val fragment = uri.rawFragment ?: return null
        if (!fragment.startsWith(FRAGMENT_PREFIX)) return null
        return decode(fragment.removePrefix(FRAGMENT_PREFIX))
    }

    fun parseCarrierHtml(html: String): Envelope? {
        if (html.isBlank()) return null
        val root = Jsoup.parseBodyFragment(html).body()
        val matches = root.select("a[href]").mapNotNull { anchor ->
            parseCarrierUrl(anchor.attr("href"))?.let { anchor to it }
        }
        if (matches.size != 1) return null
        val (anchor, envelope) = matches.single()
        if (anchor.text().trim() !in setOf("Sendt med BetterLectio", "#")) return null
        val clone = root.clone()
        val anchorIndex = root.select("a").indexOf(anchor)
        clone.select("a").getOrNull(anchorIndex)?.remove()
        val visibleText = MessageEditAudit.stripTerminalAudit(normalizeText(clone))
        val expected = when (envelope) {
            is Envelope.Set -> "Reagerede med “${envelope.emoji.glyph}”"
            is Envelope.Clear -> "Fjernede sin reaktion"
        }
        return envelope.takeIf { visibleText == expected }
    }

    fun resolve(messages: List<RawMessage>): ResolvedThread {
        val candidates = messages.mapIndexed { index, raw ->
            if (raw.entry.attachments.isNotEmpty()) return@mapIndexed null
            val envelope = parseCarrierHtml(raw.rawContentHtml) ?: return@mapIndexed null
            val actorKey = senderKey(raw.entry.senderEntityId, raw.entry.senderName.orEmpty())
            if (actorKey.isBlank()) return@mapIndexed null
            Carrier(
                envelope = envelope,
                actor = MessageReactionParticipant(
                    key = actorKey,
                    name = raw.entry.senderName.orEmpty(),
                    isOwn = raw.editPostbackTarget.isNotBlank(),
                ),
                editPostbackTarget = raw.editPostbackTarget,
                index = index,
            )
        }

        val occurrences = mutableMapOf<String, Int>()
        val locators = mutableMapOf<Int, MessageLocator>()
        val targetIndexes = mutableMapOf<String, Int>()
        messages.forEachIndexed { index, raw ->
            if (candidates[index] != null) return@forEachIndexed
            val locator = deriveLocator(raw.entry, occurrences) ?: return@forEachIndexed
            locators[index] = locator
            targetIndexes[locatorKey(locator)] = index
        }

        val carriersByTarget = mutableMapOf<Int, MutableMap<String, Carrier>>()
        val hidden = mutableSetOf<Int>()
        candidates.filterNotNull().forEach { carrier ->
            val targetIndex = targetIndexes[locatorKey(carrier.envelope.target)] ?: return@forEach
            if (targetIndex >= carrier.index) return@forEach
            hidden += carrier.index
            carriersByTarget.getOrPut(targetIndex) { linkedMapOf() }[carrier.actor.key] = carrier
        }

        val ownCarriers = mutableMapOf<MessageLocator, Carrier>()
        val result = messages.mapIndexedNotNull { index, raw ->
            if (index in hidden) return@mapIndexedNotNull null
            val locator = locators[index]
            val groups = linkedMapOf<MessageReactionEmoji, MutableList<MessageReactionParticipant>>()
            var ownReaction: MessageReactionEmoji? = null
            carriersByTarget[index]?.values?.forEach { carrier ->
                if (carrier.actor.isOwn && locator != null) ownCarriers[locator] = carrier
                when (val envelope = carrier.envelope) {
                    is Envelope.Clear -> Unit
                    is Envelope.Set -> {
                        groups.getOrPut(envelope.emoji) { mutableListOf() } += carrier.actor
                        if (carrier.actor.isOwn) ownReaction = envelope.emoji
                    }
                }
            }
            raw.entry.copy(
                locator = locator,
                reactions = MessageReactionEmoji.entries.mapNotNull { emoji ->
                    groups[emoji]?.let { MessageReactionGroup(emoji, it) }
                },
                ownReaction = ownReaction,
            )
        }
        return ResolvedThread(result, ownCarriers, hidden.size)
    }

    fun senderKey(entityId: String?, senderName: String): String {
        val id = entityId.orEmpty().trim()
        if (id.isNotEmpty()) return "id:$id"
        val name = Normalizer.normalize(senderName, Normalizer.Form.NFC)
            .replace(Regex("\\s+"), " ")
            .trim()
            .lowercase(danishLocale)
        return if (name.isBlank()) "" else "name:$name"
    }

    fun locatorKey(locator: MessageLocator): String =
        "${locator.senderKey}\u001f${locator.sentAt}\u001f${locator.occurrence}"

    private fun deriveLocator(
        entry: ThreadEntry,
        occurrences: MutableMap<String, Int>,
    ): MessageLocator? {
        val senderKey = senderKey(entry.senderEntityId, entry.senderName.orEmpty())
        val sentAt = entry.sentAt?.format(isoSeconds) ?: return null
        if (senderKey.isBlank()) return null
        val base = "$senderKey\u001f$sentAt"
        val occurrence = occurrences[base] ?: 0
        occurrences[base] = occurrence + 1
        return MessageLocator(senderKey, sentAt, occurrence)
    }

    private fun isValidLocator(locator: MessageLocator): Boolean =
        locator.senderKey.isNotBlank() &&
            locator.senderKey.length <= 256 &&
            locator.sentAt.matches(Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$")) &&
            locator.occurrence in 0..9

    private fun normalizeText(root: Element): String = root.text().replace(Regex("\\s+"), " ").trim()

}
