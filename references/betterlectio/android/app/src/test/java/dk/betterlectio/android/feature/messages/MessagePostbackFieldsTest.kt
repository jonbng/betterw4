package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MessagePostbackFieldsTest {
    @Test
    fun reply_variants_non_empty_and_distinct_targets() {
        assertTrue(MessagePostbackFields.replyVariants.size >= 2)
        val targets = MessagePostbackFields.replyVariants.map { it.sendTarget }.toSet()
        assertTrue(targets.size >= 2)
    }

    @Test
    fun compose_variants_include_subject_and_body() {
        MessagePostbackFields.composeVariants.forEach { v ->
            assertTrue(v.subjectField.isNotBlank())
            assertTrue(v.bodyField.isNotBlank())
            assertTrue(v.recipientField.isNotBlank())
        }
    }

    @Test
    fun action_target_lists_non_empty() {
        assertTrue(MessagePostbackFields.markReadTargets.isNotEmpty())
        assertTrue(MessagePostbackFields.markUnreadTargets.isNotEmpty())
        assertTrue(MessagePostbackFields.flagTargets.isNotEmpty())
        assertTrue(MessagePostbackFields.deleteTargets.isNotEmpty())
    }

    @Test
    fun list_event_args_match_ios_flutter() {
        assertEquals("READMESSAGE_42", MessagePostbackFields.readMessageArg("42"))
        assertEquals("UNREADMESSAGE_42", MessagePostbackFields.unreadMessageArg("42"))
        assertEquals("FLAGMESSAGE_42", MessagePostbackFields.flagMessageArg("42"))
        assertEquals("HIDEMESSAGE_42", MessagePostbackFields.hideMessageArg("42"))
        // Must match Lectio onclick: $LB2$_MC_$_42 (underscore before the second $)
        assertEquals("\$LB2\$_MC_\$_42", MessagePostbackFields.openThreadArg("42"))
        assertEquals(
            "\$LB2\$_MC_\$_76896476427",
            MessagePostbackFields.openThreadArg("76896476427"),
        )
        assertTrue(MessagePostbackFields.replyVariants.any { it.sendTarget.contains("SendMessageBtn") })
    }
}

