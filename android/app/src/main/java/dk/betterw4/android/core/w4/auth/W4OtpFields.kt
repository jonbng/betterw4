package dk.betterw4.android.core.w4.auth

/**
 * Live `site/verify2fa` field names from `references/pages/login.har` (16 Aug 2026).
 *
 * W4 does not set a remember-device cookie. Trust is a server-side binding of
 * [DEVICE_ID] flipped by [REMEMBER]=1 (“Trust this device for 30 days”).
 */
internal object W4OtpFields {
    const val DEVICE_ID = "OtpModel[deviceId]"
    const val REMEMBER = "OtpModel[remember]"

    fun build(challenge: W4OtpChallenge, code: String, deviceId: String): Map<String, String> {
        val fields = challenge.hiddenFields.toMutableMap()
        fields[challenge.otpFieldName] = code.trim()
        for (key in fields.keys.filter { it.contains("deviceId", ignoreCase = true) }) {
            fields[key] = deviceId
        }
        for (key in fields.keys.filter { it.contains("remember", ignoreCase = true) }) {
            fields[key] = "1"
        }
        fields[DEVICE_ID] = deviceId
        fields[REMEMBER] = "1"
        val submitName = challenge.submitName ?: "yt0"
        fields.putIfAbsent(submitName, challenge.submitValue ?: "Submit")
        return fields
    }
}
