package dk.betterlectio.android.feature.schedule

/**
 * Lectio private-event id conventions.
 * ScheduleParser stores `AFT{numeric}` from `aftaleid=` hrefs (iOS parity).
 */
object PrivateEventIds {

    private val prefixedNumeric = Regex("""(?i)^(?:AFT|PRIV)(\d+)$""")
    private val plainNumeric = Regex("""^\d+$""")
    private val aftaleInString = Regex("""(?i)aftaleid=(\d+)""")

    /** True for AFT…, PRIV…, or session-local private ids. */
    fun isPrivateEventId(id: String): Boolean {
        val t = id.trim()
        if (t.startsWith("local-private", ignoreCase = true)) return true
        if (prefixedNumeric.matches(t)) return true
        if (plainNumeric.matches(t) && t.length >= 1) return false // bare module ids are not private
        return false
    }

    /**
     * Whether the schedule event is a private aftale (edit/delete UI).
     * Matches parser AFT ids even when team is empty.
     */
    fun isPrivateEvent(event: ScheduleEvent): Boolean {
        if (isPrivateEventId(event.id)) return true
        if (event.team.equals(PRIVATE_EVENT_TEAM_TOKEN, ignoreCase = true)) return true
        if (event.href?.let { aftaleInString.containsMatchIn(it) } == true) return true
        return false
    }

    /**
     * Numeric Lectio `aftaleid` for update/delete URLs.
     * `AFT12345` → `12345`, `PRIV99` → `99`, `aftaleid=42` in string → `42`.
     */
    fun numericAftaleId(eventId: String): String? {
        val t = eventId.trim()
        prefixedNumeric.find(t)?.let { return it.groupValues[1] }
        plainNumeric.find(t)?.let { return it.value }
        aftaleInString.find(t)?.let { return it.groupValues[1] }
        return null
    }

    /** Storage id matching [ScheduleParser] (`AFT` + digits). */
    fun storageId(numericAftaleId: String): String = "AFT$numericAftaleId"

    /** `privat_aftale.aspx?aftaleid={n}` or null if [eventId] has no numeric aftale id. */
    fun updatePath(eventId: String): String? {
        val n = numericAftaleId(eventId) ?: return null
        return "privat_aftale.aspx?aftaleid=$n"
    }

    /**
     * Pull first aftaleid from a Lectio create/update response body (links / query strings).
     */
    fun extractAftaleIdFromResponse(html: String): String? =
        aftaleInString.find(html)?.groupValues?.get(1)
}
