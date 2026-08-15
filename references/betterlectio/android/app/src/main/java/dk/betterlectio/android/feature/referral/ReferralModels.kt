package dk.betterlectio.android.feature.referral

/** Successful attributed invites needed to unlock Tilpasning. */
const val REFERRAL_UNLOCK_THRESHOLD = 3

data class ReferralStats(
    val totalClicks: Int = 0,
    val uniqueClickers: Int = 0,
    val conversions: Int = 0,
    val recentReferrals: List<RecentReferral> = emptyList(),
)

data class RecentReferral(
    val studentId: String,
    val name: String?,
    val attributedAt: String?,
)

data class ReferralUnlockProgress(
    val current: Int,
    val target: Int,
    val unlocked: Boolean,
    val remaining: Int,
)

fun referralUnlockProgress(conversions: Int): ReferralUnlockProgress {
    val current = conversions.coerceAtLeast(0)
    val target = REFERRAL_UNLOCK_THRESHOLD
    return ReferralUnlockProgress(
        current = current.coerceAtMost(target),
        target = target,
        unlocked = current >= target,
        remaining = (target - current).coerceAtLeast(0),
    )
}

fun buildReferralUrl(studentId: String): String = "https://betterlectio.dk/r/$studentId"
