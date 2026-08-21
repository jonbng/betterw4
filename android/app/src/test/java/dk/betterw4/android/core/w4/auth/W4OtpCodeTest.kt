package dk.betterw4.android.core.w4.auth

import org.junit.Assert.assertEquals
import org.junit.Test

class W4OtpCodeTest {

    @Test
    fun sanitize_strips_whitespace_and_caps_length() {
        assertEquals("5Z4IccMB", W4OtpCode.sanitizeInput(" 5Z4IccMB\n"))
        assertEquals("5Z4IccMB", W4OtpCode.sanitizeInput("5Z4IccMBXXXX"))
    }
}
