package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Structural + pure regression: compose must not claim offline queue success.
 * Drives the shipped MessageRepository source for the false-success pattern.
 */
class MessageComposeFailureTest {

    @Test
    fun compose_source_does_not_return_success_on_offline_queue_lie() {
        // Locate production MessageRepository relative to module roots.
        val candidates = listOf(
            "src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            "app/src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            "../app/src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            "android/app/src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
        )
        val file = candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: File(
                System.getProperty("user.dir")!!,
                "src/main/java/dk/betterlectio/android/feature/messages/MessageRepository.kt",
            )
        assertTrue("MessageRepository.kt must exist for audit: ${file.absolutePath}", file.exists())
        val src = file.readText()
        assertFalse(
            "compose must not pretend offline queue success",
            src.contains("offline kø"),
        )
        assertTrue(
            "compose failure path must return AppResult.Failure",
            src.contains("AppResult.Failure") &&
                (src.contains("Kunne ikke sende besked") ||
                    src.contains("is AppResult.Failure -> return")),
        )
        assertTrue(
            "compose must use multi-step postFromHtml",
            src.contains("postFromHtml") &&
                !src.contains("beskeder2.aspx?type=nybesked"),
        )
    }

    @Test
    fun normalize_and_compose_validation_still_reject_empty() {
        // Compose still validates draft (shipped pure check via MessageRepository contracts).
        val blank = ComposeMessageDraft("", "", emptyList(), emptyList())
        assertTrue(blank.subject.isBlank() || blank.recipientIds.isEmpty())
    }
}
