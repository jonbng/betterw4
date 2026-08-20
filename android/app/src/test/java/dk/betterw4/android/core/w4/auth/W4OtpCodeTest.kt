package dk.betterw4.android.core.w4.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class W4OtpCodeTest {

    @Test
    fun extracts_live_w4_codes() {
        val codes = listOf(
            "5Z4IccMB",
            "abSHlAcY",
            "jYSaRbGT",
            "VYTkVHeR",
            "9LPKSSSX",
            "zGhIItWl",
            "w3RSqC6f",
            "KRxMTc9v",
        )
        for (code in codes) {
            assertEquals(code, W4OtpCode.extract(code))
            assertEquals(code, W4OtpCode.extract("  $code \n"))
            assertEquals(code, W4OtpCode.extract("\"$code\""))
            assertEquals(code, W4OtpCode.extract("$code."))
        }
    }

    @Test
    fun rejects_usernames_and_other_clipboard_noise() {
        assertNull(W4OtpCode.extract("nc26abcd"))
        assertNull(W4OtpCode.extract("NC26AbCd"))
        assertNull(W4OtpCode.extract("Nc00jjen"))
        assertNull(W4OtpCode.extract("nC99XXXX"))
        assertNull(W4OtpCode.extract("12345678"))
        assertNull(W4OtpCode.extract("5Z4IccM"))
        assertNull(W4OtpCode.extract("5Z4IccMBX"))
        assertNull(W4OtpCode.extract("Your code is 5Z4IccMB"))
        assertNull(W4OtpCode.extract(""))
        assertNull(W4OtpCode.extract(null))
        assertNull(W4OtpCode.extract("password1"))
    }

    @Test
    fun sanitize_strips_whitespace_and_caps_length() {
        assertEquals("5Z4IccMB", W4OtpCode.sanitizeInput(" 5Z4IccMB\n"))
        assertEquals("5Z4IccMB", W4OtpCode.sanitizeInput("5Z4IccMBXXXX"))
    }
}
