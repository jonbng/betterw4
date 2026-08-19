package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Html

/**
 * Shared directory helpers. W4 people lists are parsed by [W4PeopleParser].
 */
object DirectoryParser {

    fun mergeEntity(existing: DirectoryEntity?, incoming: DirectoryEntity): DirectoryEntity {
        if (existing == null) return incoming
        val name = when {
            looksLikeIdColumnLabel(incoming.name) && !looksLikeIdColumnLabel(existing.name) ->
                existing.name
            !looksLikeIdColumnLabel(incoming.name) -> incoming.name
            else -> existing.name.ifBlank { incoming.name }
        }
        val subtitle = incoming.subtitle?.takeIf { it.isNotBlank() } ?: existing.subtitle
        val avatar = pickAvatar(existing.avatarUrl, incoming.avatarUrl)
        val year = incoming.year ?: existing.year
        return incoming.copy(name = name, subtitle = subtitle, avatarUrl = avatar, year = year)
    }

    /**
     * Prefer a real W4 portrait (`/files/user_photos/…`) over a guessed `/photos/…`
     * URL. Name-only `a[href*=uwc_id]` links must not clobber the photo link.
     */
    fun pickAvatar(existing: String?, incoming: String?): String? {
        val a = usableAvatar(incoming)
        val b = usableAvatar(existing)
        return when {
            a != null && b != null -> if (avatarScore(a) >= avatarScore(b)) a else b
            a != null -> a
            else -> b
        }
    }

    private fun usableAvatar(url: String?): String? {
        val u = url?.takeIf { it.isNotBlank() } ?: return null
        if (u.contains("/images/user.png")) return null
        // Legacy guessed path; live portraits are `/files/user_photos/…`.
        if (u.contains("/photos/")) return null
        return W4PeopleParser.fullSizePhotoUrl(u)
    }

    private fun avatarScore(url: String): Int =
        if (url.contains("/files/user_photos/")) 2 else 1

    fun looksLikeIdColumnLabel(name: String): Boolean {
        val n = name.trim()
        return n.isEmpty() || n.equals("id", ignoreCase = true) || W4Html.UWC_ID.matches(n)
    }

    fun looksLikeNavChrome(name: String): Boolean {
        val n = name.trim().lowercase()
        return n in setOf("home", "logout", "profile", "password", "help")
    }
}
