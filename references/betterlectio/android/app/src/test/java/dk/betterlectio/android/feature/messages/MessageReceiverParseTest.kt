package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

class MessageReceiverParseTest {

    @Test
    fun parseThreadDetail_extracts_receiver_entity_ids() {
        val html = """
            <div id="s_m_Content_Content_MessageThreadCtrl_RecipientsReadMode">
              <span data-lectioContextCard="S12345" class="prepend-fonticon-student" title="Anna Elev">Anna Elev</span>
              <span data-lectioContextCard="T99" class="prepend-fonticon-teacher" title="Bo Lærer">Bo Lærer</span>
            </div>
            <table id="s_m_Content_Content_MessageThreadCtrl_MessagesGV">
              <tr>
                <td>
                  <div class="message-thread-message-sender">
                    <span data-lectioContextCard="S1" class="prepend-fonticon-student">Anna Elev</span>, 01-01-2026 10:00
                  </div>
                  <div class="message-thread-message-content">Hej</div>
                </td>
              </tr>
            </table>
        """.trimIndent()
        val ref = MessageThread(
            id = "1",
            topic = "Test",
            sender = "Anna Elev",
            dateChanged = LocalDateTime.of(2026, 1, 1, 10, 0),
            folderId = "-70",
            senderEntityId = "S1",
        )
        val detail = MessageParser.parseThreadDetail(html, ref)
        assertTrue(detail.receivers.any { it.contains("Anna") })
        assertTrue(detail.receivers.any { it.contains("Bo") || it.contains("Lærer") })
        assertEquals(setOf("S12345", "T99"), detail.receiverEntityIds.toSet())
        assertTrue(
            MessageSignature.shouldSkipSignature(
                detail.receiverEntityIds + listOfNotNull(detail.thread.senderEntityId),
            ),
        )
    }

    @Test
    fun signature_skip_students_only_false() {
        assertTrue(
            !MessageSignature.shouldSkipSignature(listOf("S1", "S2")),
        )
    }
}
