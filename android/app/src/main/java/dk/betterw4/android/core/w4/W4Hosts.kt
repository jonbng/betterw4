package dk.betterw4.android.core.w4

/**
 * Host matching for UWCRCN W4. Cookies and auth headers must never leak to other domains.
 */
object W4Hosts {
    const val HOST = "w4.uwcrcn.no"
    const val ORIGIN = "https://w4.uwcrcn.no"

    fun isW4Host(host: String?): Boolean {
        if (host.isNullOrBlank()) return false
        val normalized = host.trim().lowercase().removePrefix(".")
        return normalized == HOST || normalized.endsWith(".$HOST")
    }
}
