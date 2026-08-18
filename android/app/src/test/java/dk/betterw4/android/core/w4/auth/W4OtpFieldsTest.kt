package dk.betterw4.android.core.w4.auth

import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.scrape.W4Form
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class W4OtpFieldsTest {

    @Test
    fun always_trusts_device_and_overwrites_blank_device_id() {
        val challenge = W4OtpChallenge(
            credentials = W4Credentials(sessionId = "sid"),
            formAction = "https://w4.uwcrcn.no/index.php?r=site/verify2fa".toHttpUrl(),
            hiddenFields = mapOf(
                "OtpModel[deviceId]" to "",
                "OtpModel[remember]" to "0",
            ),
            otpFieldName = "OtpModel[otp]",
            submitName = "yt0",
            submitValue = "Submit",
        )
        val fields = W4OtpFields.build(challenge, code = "ABC12345", deviceId = "stable-device-id")

        assertEquals("stable-device-id", fields["OtpModel[deviceId]"])
        assertEquals("1", fields["OtpModel[remember]"])
        assertEquals("ABC12345", fields["OtpModel[otp]"])
        assertEquals("Submit", fields["yt0"])
        assertFalse(fields.values.contains("0"))
    }

    @Test
    fun live_verify2fa_fixture_posts_remember_and_device_id() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("w4/verify2fa.html")!!
            .bufferedReader()
            .readText()
        val parsed = W4Form.parse(html)!!
        val otpField = parsed.otpFieldName!!
        val hidden = parsed.fields.toMutableMap().apply { remove(otpField) }
        val challenge = W4OtpChallenge(
            credentials = W4Credentials(sessionId = "sid"),
            formAction = "https://w4.uwcrcn.no/index.php?r=site/verify2fa".toHttpUrl(),
            hiddenFields = hidden,
            otpFieldName = otpField,
            submitName = parsed.submitName,
            submitValue = parsed.submitValue,
        )
        val encoded = W4Form.encode(
            W4OtpFields.build(challenge, code = "KRxMTc9v", deviceId = "1416999358"),
        ).decodeToString()

        assertTrue(encoded.contains("OtpModel%5BdeviceId%5D=1416999358"))
        assertTrue(encoded.contains("OtpModel%5Bremember%5D=1"))
        assertTrue(encoded.contains("OtpModel%5Botp%5D=KRxMTc9v"))
        assertTrue(encoded.contains("yt0=Submit"))
        assertFalse(encoded.contains("OtpModel%5Bremember%5D=0"))
    }
}
