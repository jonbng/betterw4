package dk.betterlectio.android.feature.messages

import java.time.LocalDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageReactionProtocolTest {
    private val target = MessageLocator(
        senderKey = "id:U72721772844",
        sentAt = "2026-03-05T14:33:09",
        occurrence = 0,
    )

    @Test
    fun roundTripsEveryEmojiAndUsesFragmentOnly() {
        MessageReactionEmoji.entries.forEach { emoji ->
            val envelope = MessageReactionProtocol.Envelope.Set(emoji, target)
            val encoded = MessageReactionProtocol.encode(envelope)
            assertEquals(envelope, MessageReactionProtocol.decode(encoded))
            val url = MessageReactionProtocol.carrierUrl(envelope)
            assertTrue(url.startsWith("https://betterlectio.dk/download#blr1."))
            assertFalse(url.contains("?"))
            assertEquals(envelope, MessageReactionProtocol.parseCarrierUrl(url))
        }
    }

    @Test
    fun clearContainsNoPreviousEmoji() {
        val clear = MessageReactionProtocol.Envelope.Clear(target)
        val body = MessageReactionProtocol.carrierBody(clear, showSignature = false)
        assertTrue(body.contains("Fjernede sin reaktion"))
        assertFalse(body.contains("❤️"))
        assertEquals(clear, MessageReactionProtocol.decode(MessageReactionProtocol.encode(clear)))

        val invalidClear = MessageReactionProtocol.carrierUrl(
            MessageReactionProtocol.Envelope.Set(MessageReactionEmoji.HEART, target),
        ).replace("#blr1.", "?blr1=")
        assertNull(MessageReactionProtocol.parseCarrierUrl(invalidClear))
    }

    @Test
    fun resolvesLatestCarrierAndKeepsMalformedMessagesVisible() {
        val original = rawMessage(
            id = "original",
            senderId = "U72721772844",
            sender = "Target Person",
            sentAt = LocalDateTime.of(2026, 3, 5, 14, 33, 9),
            html = "<p>Original</p>",
        )
        val set = MessageReactionProtocol.Envelope.Set(MessageReactionEmoji.HEART, target)
        val clear = MessageReactionProtocol.Envelope.Clear(target)
        val setCarrier = rawMessage(
            id = "set",
            senderId = "U-own",
            sender = "Own Person",
            sentAt = LocalDateTime.of(2026, 3, 5, 14, 34),
            html = carrierHtml(set),
            editTarget = "row-set",
        )
        val clearCarrier = rawMessage(
            id = "clear",
            senderId = "U-own",
            sender = "Own Person",
            sentAt = LocalDateTime.of(2026, 3, 5, 14, 35),
            html = carrierHtml(clear),
            editTarget = "row-clear",
        )
        val malformed = rawMessage(
            id = "malformed",
            senderId = "U-other",
            sender = "Other Person",
            sentAt = LocalDateTime.of(2026, 3, 5, 14, 36),
            html = carrierHtml(set).replace("Reagerede med", "Påstod at reagere med"),
        )

        val result = MessageReactionProtocol.resolve(listOf(original, setCarrier, clearCarrier, malformed))
        assertEquals(2, result.hiddenCarrierCount)
        assertEquals(listOf("original", "malformed"), result.entries.map { it.id })
        assertTrue(result.entries.first().reactions.isEmpty())
        assertNull(result.entries.first().ownReaction)
        assertEquals("row-clear", result.ownCarriersByTarget[target]?.editPostbackTarget)
    }

    @Test
    fun unresolvedCarrierRemainsVisible() {
        val unresolved = MessageReactionProtocol.Envelope.Set(
            MessageReactionEmoji.THUMBS_UP,
            target.copy(senderKey = "id:missing"),
        )
        val result = MessageReactionProtocol.resolve(
            listOf(
                rawMessage(
                    id = "original",
                    senderId = "U72721772844",
                    sender = "Target Person",
                    sentAt = LocalDateTime.of(2026, 3, 5, 14, 33, 9),
                    html = "Original",
                ),
                rawMessage(
                    id = "carrier",
                    senderId = "U-reactor",
                    sender = "Reactor",
                    sentAt = LocalDateTime.of(2026, 3, 5, 14, 34),
                    html = carrierHtml(unresolved),
                ),
            ),
        )
        assertEquals(0, result.hiddenCarrierCount)
        assertEquals(2, result.entries.size)
    }

    @Test
    fun editedCarrierIgnoresLectioAuditLine() {
        val envelope = MessageReactionProtocol.Envelope.Set(MessageReactionEmoji.THUMBS_UP, target)
        val html = carrierHtml(envelope) +
            "<div>Redigeret af Jonathan Arthur Hojer Bangert(k) (2x 17), d. 3/8-2026 09:54</div>"
        assertEquals(envelope, MessageReactionProtocol.parseCarrierHtml(html))
        assertNull(MessageReactionProtocol.parseCarrierHtml("$html<div>extra text</div>"))
    }

    private fun carrierHtml(envelope: MessageReactionProtocol.Envelope): String {
        val sentence = when (envelope) {
            is MessageReactionProtocol.Envelope.Set -> "Reagerede med “${envelope.emoji.glyph}”"
            is MessageReactionProtocol.Envelope.Clear -> "Fjernede sin reaktion"
        }
        return "<p>$sentence</p><p><a href=\"${MessageReactionProtocol.carrierUrl(envelope)}\">Sendt med BetterLectio</a></p>"
    }

    private fun rawMessage(
        id: String,
        senderId: String,
        sender: String,
        sentAt: LocalDateTime,
        html: String,
        editTarget: String = "",
    ) = MessageReactionProtocol.RawMessage(
        entry = ThreadEntry(
            id = id,
            topic = null,
            contentHtml = MessageParser.stripAppSignatures(html),
            senderName = sender,
            sentAt = sentAt,
            senderEntityId = senderId,
        ),
        rawContentHtml = html,
        editPostbackTarget = editTarget,
    )
}
