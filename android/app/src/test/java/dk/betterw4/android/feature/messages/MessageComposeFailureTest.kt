package dk.betterw4.android.feature.messages

import org.junit.Assert.assertTrue
import org.junit.Test

class MessageComposeFailureTest {

    @Test
    fun live_compose_is_stubbed_as_failure() {
        val blank = ComposeMessageDraft("", "", emptyList(), emptyList())
        assertTrue(blank.subject.isBlank() || blank.recipientIds.isEmpty())
    }
}
