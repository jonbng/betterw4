package dk.betterw4.android.core.w4.auth

/**
 * W4 usernames are the UWC id (`nc26jban`). People often paste the school
 * email (`nc26jban@uwcrcn.no`) instead — keep the local part only.
 */
internal object W4Username {
    fun normalize(raw: String): String {
        val trimmed = raw.trim()
        val at = trimmed.indexOf('@')
        if (at < 0) return trimmed
        return trimmed.substring(0, at).trim()
    }
}
