package dk.betterw4.android.feature.directory

/**
 * Country flags for the five UWC RCN boarding houses.
 * [emoji] is the regional-indicator pair (🇩🇰 …); Graduated has no flag.
 */
enum class HouseFlagKind {
    DENMARK, FINLAND, ICELAND, NORWAY, SWEDEN, GRADUATED;

    val emoji: String
        get() = when (this) {
            DENMARK -> "🇩🇰"
            FINLAND -> "🇫🇮"
            ICELAND -> "🇮🇸"
            NORWAY -> "🇳🇴"
            SWEDEN -> "🇸🇪"
            GRADUATED -> "🎓"
        }

    companion object {
        fun of(houseIdOrName: String?): HouseFlagKind? {
            val raw = houseIdOrName?.trim().orEmpty()
            if (raw.isEmpty()) return null
            val key = raw.lowercase()
                .replace("å", "a")
                .replace(Regex("""[^a-z0-9]+"""), "")
            return when (key) {
                "denmark", "dk" -> DENMARK
                "finland", "fi" -> FINLAND
                "iceland", "is" -> ICELAND
                "norway", "no" -> NORWAY
                "sweden", "se" -> SWEDEN
                "grad", "graduated" -> GRADUATED
                else -> null
            }
        }
    }
}

fun House.flagKind(): HouseFlagKind? = HouseFlagKind.of(id) ?: HouseFlagKind.of(name)

fun houseFlagLabel(name: String, houseId: String? = null): String {
    val kind = HouseFlagKind.of(houseId) ?: HouseFlagKind.of(name) ?: return name
    return "${kind.emoji} $name"
}
