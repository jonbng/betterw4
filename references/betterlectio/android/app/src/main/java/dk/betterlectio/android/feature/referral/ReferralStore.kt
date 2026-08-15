package dk.betterlectio.android.feature.referral

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Local flags for referral finalize (at-most-once) and the soft share nudge.
 */
@Singleton
class ReferralStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs = context.applicationContext.getSharedPreferences("bl_referral", Context.MODE_PRIVATE)

    fun wasFinalizeAttempted(studentId: String): Boolean =
        prefs.getBoolean(finalizeKey(studentId), false)

    fun markFinalizeAttempted(studentId: String) {
        prefs.edit { putBoolean(finalizeKey(studentId), true) }
    }

    fun wasNudgeShown(studentId: String): Boolean =
        prefs.getBoolean(nudgeKey(studentId), false)

    fun markNudgeShown(studentId: String) {
        prefs.edit { putBoolean(nudgeKey(studentId), true) }
    }

    fun lastKnownConversions(studentId: String): Int =
        prefs.getInt(conversionsKey(studentId), -1)

    fun setLastKnownConversions(studentId: String, conversions: Int) {
        prefs.edit { putInt(conversionsKey(studentId), conversions) }
    }

    private fun finalizeKey(studentId: String) = "finalize_attempted:$studentId"
    private fun nudgeKey(studentId: String) = "nudge_shown:$studentId"
    private fun conversionsKey(studentId: String) = "conversions:$studentId"
}
