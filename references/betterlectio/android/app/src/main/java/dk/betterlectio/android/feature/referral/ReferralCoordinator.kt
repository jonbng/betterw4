package dk.betterlectio.android.feature.referral

import com.posthog.PostHog
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.feature.supabase.SupabaseReferralService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Orchestrates Install Referrer → referral-finalize and soft share nudges.
 */
@Singleton
class ReferralCoordinator @Inject constructor(
    private val referrerReader: InstallReferrerReader,
    private val referralService: SupabaseReferralService,
    private val store: ReferralStore,
) {
    private val _nudgeVisible = MutableStateFlow(false)
    val nudgeVisible: StateFlow<Boolean> = _nudgeVisible.asStateFlow()

    private val _celebrationName = MutableStateFlow<String?>(null)
    val celebrationName: StateFlow<String?> = _celebrationName.asStateFlow()

    private val _cachedStats = MutableStateFlow<ReferralStats?>(null)
    val cachedStats: StateFlow<ReferralStats?> = _cachedStats.asStateFlow()

    /**
     * Call after Supabase session is ready (login or cold start). At-most-once per student.
     */
    suspend fun tryFinalizeAfterAuth(student: Student) {
        if (student.isDemo) return
        if (store.wasFinalizeAttempted(student.studentId)) return

        val cookieId = referrerReader.readReferralCookieId()
        // Mark attempted after we got a referrer response (even empty) so we don't
        // hammer Play's API — but only after a real network finalize attempt when
        // we have a cookie, or immediately when there is nothing to attribute.
        if (cookieId.isNullOrBlank()) {
            store.markFinalizeAttempted(student.studentId)
            Timber.d("Referral: no Install Referrer cookie — skipping finalize")
            return
        }

        val result = referralService.finalizeAndroid(
            studentId = student.studentId,
            schoolId = student.gymId,
            cookieId = cookieId,
        )
        // Only mark attempted on a definite HTTP response (success or attributed:false).
        // Network failures leave the flag unset so cold-start can retry.
        if (result != null) {
            store.markFinalizeAttempted(student.studentId)
            if (result.attributed) {
                PostHog.capture(
                    event = "referral attributed",
                    properties = mapOf(
                        "platform" to "android",
                        "referrer_student_id" to (result.referrerStudentId ?: ""),
                    ),
                )
            }
            Timber.i(
                "Referral finalize: attributed=%s reason=%s",
                result.attributed,
                result.reason,
            )
        }
    }

    suspend fun refreshStats(studentId: String): ReferralStats? {
        val stats = referralService.getStats(studentId) ?: return _cachedStats.value
        val previous = store.lastKnownConversions(studentId)
        if (previous >= 0 && stats.conversions > previous) {
            val newest = stats.recentReferrals.firstOrNull()?.name
            _celebrationName.value = newest ?: "En ven"
        }
        store.setLastKnownConversions(studentId, stats.conversions)
        _cachedStats.value = stats
        return stats
    }

    fun consumeCelebration() {
        _celebrationName.value = null
    }

    /**
     * After first successful skema load — show soft nudge once if under unlock threshold.
     */
    suspend fun maybeShowNudge(student: Student) {
        if (student.isDemo) return
        if (store.wasNudgeShown(student.studentId)) return
        val stats = refreshStats(student.studentId) ?: return
        if (referralUnlockProgress(stats.conversions).unlocked) {
            store.markNudgeShown(student.studentId)
            return
        }
        _nudgeVisible.value = true
    }

    fun dismissNudge(studentId: String) {
        store.markNudgeShown(studentId)
        _nudgeVisible.value = false
    }
}
