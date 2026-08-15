package dk.betterlectio.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * Drives shipped [HomeworkRepository] helpers for per-student keys and optimistic LWW.
 */
class HomeworkDoneLwwTest {

    @Test
    fun donePrefsKey_is_scoped_per_student() {
        assertEquals("s1|999", HomeworkRepository.donePrefsKey("s1", "999"))
        assertEquals("s2|999", HomeworkRepository.donePrefsKey("s2", "999"))
        assertFalse(
            HomeworkRepository.donePrefsKey("s1", "999") ==
                HomeworkRepository.donePrefsKey("s2", "999"),
        )
        assertEquals("at_s1|999", HomeworkRepository.atPrefsKey("s1", "999"))
    }

    @Test
    fun shouldDropPending_when_remote_acknowledges() {
        val t = Instant.parse("2026-03-10T12:00:00Z")
        assertTrue(
            HomeworkRepository.shouldDropPendingAfterRemote(
                pendingClientUpdatedAt = t,
                thisWriteAt = t,
                remoteClientUpdatedAt = t,
                didWrite = true,
            ),
        )
        assertTrue(
            HomeworkRepository.shouldDropPendingAfterRemote(
                pendingClientUpdatedAt = t,
                thisWriteAt = t,
                remoteClientUpdatedAt = t.plusSeconds(1),
                didWrite = true,
            ),
        )
    }

    @Test
    fun shouldKeepPending_when_write_ok_but_remote_stale() {
        val t = Instant.parse("2026-03-10T12:00:00Z")
        assertFalse(
            HomeworkRepository.shouldDropPendingAfterRemote(
                pendingClientUpdatedAt = t,
                thisWriteAt = t,
                remoteClientUpdatedAt = t.minusSeconds(5),
                didWrite = true,
            ),
        )
        assertFalse(
            HomeworkRepository.shouldDropPendingAfterRemote(
                pendingClientUpdatedAt = t,
                thisWriteAt = t,
                remoteClientUpdatedAt = null,
                didWrite = true,
            ),
        )
    }

    @Test
    fun shouldDropPending_when_write_failed() {
        val t = Instant.parse("2026-03-10T12:00:00Z")
        assertTrue(
            HomeworkRepository.shouldDropPendingAfterRemote(
                pendingClientUpdatedAt = t,
                thisWriteAt = t,
                remoteClientUpdatedAt = null,
                didWrite = false,
            ),
        )
    }

    @Test
    fun shouldNotDrop_when_pending_is_a_newer_write() {
        val older = Instant.parse("2026-03-10T12:00:00Z")
        val newer = older.plusSeconds(10)
        assertFalse(
            HomeworkRepository.shouldDropPendingAfterRemote(
                pendingClientUpdatedAt = newer,
                thisWriteAt = older,
                remoteClientUpdatedAt = null,
                didWrite = false,
            ),
        )
    }
}
