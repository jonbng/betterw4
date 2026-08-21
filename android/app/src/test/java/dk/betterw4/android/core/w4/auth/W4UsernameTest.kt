package dk.betterw4.android.core.w4.auth

import org.junit.Assert.assertEquals
import org.junit.Test

class W4UsernameTest {

    @Test
    fun leaves_bare_username_alone() {
        assertEquals("nc26jban", W4Username.normalize("nc26jban"))
        assertEquals("nc26jban", W4Username.normalize("  nc26jban \n"))
    }

    @Test
    fun strips_school_email_domain() {
        assertEquals("nc26jban", W4Username.normalize("nc26jban@uwcrcn.no"))
        assertEquals("NC26JBAN", W4Username.normalize("  NC26JBAN@UWCRCN.NO  "))
        assertEquals("nc26jban", W4Username.normalize("nc26jban@uwcrcn.no "))
    }

    @Test
    fun strips_any_email_domain() {
        assertEquals("nc26jban", W4Username.normalize("nc26jban@gmail.com"))
    }

    @Test
    fun empty_local_part_is_empty() {
        assertEquals("", W4Username.normalize("@uwcrcn.no"))
        assertEquals("", W4Username.normalize("   "))
    }
}
