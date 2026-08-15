package dk.betterlectio.android.feature.directory

import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Rich BetterLectio student profile fields from Supabase `students`.
 * Lectio directory identity remains the fallback when this is null / inactive.
 */
data class StudentProfile(
    val id: String,
    val name: String? = null,
    val description: String? = null,
    val instagram: String? = null,
    val birthdate: String? = null,
    val showBirthday: Boolean = false,
    val customPfpUrl: String? = null,
    val lectioPfpUrl: String? = null,
    val className: String? = null,
    val lastSeenAt: String? = null,
    val extensionInstalledAt: String? = null,
    val extensionUninstalledAt: String? = null,
    val appInstalledAt: String? = null,
) {
    /** Matches extension ProfilePage: active heartbeat/install or app installed. */
    val hasBetterLectio: Boolean
        get() = isActiveStudent() || !appInstalledAt.isNullOrBlank()

    fun displayName(fallback: String): String {
        val preferred = name?.trim().orEmpty()
        return preferred.ifBlank { fallback }
    }

    fun pictureUrl(fallback: String?): String? {
        val custom = customPfpUrl?.trim().orEmpty()
        if (custom.isNotEmpty()) return custom
        val lectio = lectioPfpUrl?.trim().orEmpty()
        if (lectio.isNotEmpty()) return lectio
        return fallback?.takeIf { it.isNotBlank() }
    }

    fun formattedBirthday(): String? {
        if (!showBirthday) return null
        val raw = birthdate?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return formatDanishBirthdate(raw)
    }

    private fun isActiveStudent(nowMs: Long = System.currentTimeMillis()): Boolean {
        if (!extensionUninstalledAt.isNullOrBlank()) return false
        val ts = lastSeenAt ?: extensionInstalledAt ?: return false
        val parsed = runCatching { Instant.parse(ts).toEpochMilli() }.getOrNull() ?: return false
        return nowMs - parsed <= ACTIVE_WINDOW_MS
    }

    companion object {
        const val ACTIVE_WINDOW_DAYS = 14L
        private val ACTIVE_WINDOW_MS = TimeUnit.DAYS.toMillis(ACTIVE_WINDOW_DAYS)
    }
}

object InstagramHandles {
    fun normalize(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) return null

        var handle = trimmed
        val urlMatch = Regex(
            """(?:https?://)?(?:www\.)?instagram\.com/([^/?#]+)""",
            RegexOption.IGNORE_CASE,
        ).find(handle)
        if (urlMatch != null) {
            handle = urlMatch.groupValues[1]
        }

        handle = handle.replace(Regex("^@+"), "")
            .replace(Regex("^/+|/+$"), "")
            .trim()
        return handle.takeIf { it.isNotEmpty() }
    }

    fun format(value: String?): String {
        val handle = normalize(value) ?: return ""
        return "@$handle"
    }

    fun profileUrl(value: String?): String? {
        val handle = normalize(value) ?: return null
        return "https://instagram.com/$handle"
    }
}

/** Extension parity: `12. maj 2008` style. */
fun formatDanishBirthdate(isoDate: String): String {
    val months = listOf(
        "jan", "feb", "mar", "apr", "maj", "jun",
        "jul", "aug", "sep", "okt", "nov", "dec",
    )
    val parts = isoDate.trim().split('-')
    if (parts.size < 3) return isoDate
    val year = parts[0]
    val month = parts[1].toIntOrNull() ?: return isoDate
    val day = parts[2].toIntOrNull() ?: return isoDate
    val monthName = months.getOrNull(month - 1) ?: parts[1]
    return "$day. $monthName $year"
}
