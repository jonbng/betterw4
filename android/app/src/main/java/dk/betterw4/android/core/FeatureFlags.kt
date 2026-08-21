package dk.betterw4.android.core

/**
 * Temporary product gates. Flip these rather than deleting a vertical.
 */
object FeatureFlags {
    /**
     * W4 Mailer: inbox, compose, write-message-to-person, and mail notifications.
     * Hidden until the mailer is ready to ship.
     */
    val MAIL_ENABLED: Boolean = false

    /** Native POST of `people/students/absences/register`. Form is captured; success HTML is not. */
    val ABSENCE_WRITES_ENABLED: Boolean = true
}
