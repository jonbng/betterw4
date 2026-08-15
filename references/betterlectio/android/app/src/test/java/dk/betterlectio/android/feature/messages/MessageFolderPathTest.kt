package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageFolderPathTest {

    @Test
    fun folderListSeedPath_doesNotUseTypeListe() {
        val path = MessageRepository.folderListSeedPath("-40")
        assertEquals("beskeder2.aspx?mappeid=-40", path)
        assertFalse(path.contains("type=liste"))
        assertFalse(path.contains("type="))
    }

    @Test
    fun folderListPostPath_matchesSeed() {
        assertEquals(
            MessageRepository.folderListSeedPath("-70"),
            MessageRepository.folderListPostPath("-70"),
        )
    }

    @Test
    fun isLectioErrorPage_detectsFejlhandled() {
        assertTrue(
            MessageRepository.isLectioErrorPage(
                """<html><a href="fejlhandled.aspx?title=Fejl&message=Ukendt%20parameter:%20liste">x</a></html>""",
            ),
        )
        assertTrue(
            MessageRepository.isLectioErrorPage("Ukendt parameter: liste"),
        )
        assertFalse(
            MessageRepository.isLectioErrorPage(
                """<html><table class="ls-table"><tr><td>Emne</td></tr></table></html>""",
            ),
        )
    }

    @Test
    fun openThreadArg_matchesIosFetchMessageThread() {
        // iOS: "$LB2$_MC_$_\(threadId)" / extension: `$LB2$_MC_$_${threadId}`
        val arg = MessagePostbackFields.openThreadArg("42")
        assertEquals("\$LB2\$_MC_\$_42", arg)
        assertTrue("missing _\$_ after MC: $arg", arg.contains("MC_\$_"))
        assertFalse(arg.contains("showthread"))
    }

    @Test
    fun openThreadEventArgument_prefersRawLb2Id() {
        val full = "\$LB2\$_MC_\$_76896476427"
        val thread = MessageThread(
            id = full,
            topic = "T",
            sender = "S",
            dateChanged = null,
            folderId = "-70",
            normalizedId = "76896476427",
        )
        assertEquals(full, MessageRepository.openThreadEventArgument(thread))
        val numericOnly = thread.copy(id = "76896476427")
        assertEquals(
            "\$LB2\$_MC_\$_76896476427",
            MessageRepository.openThreadEventArgument(numericOnly),
        )
    }
}
