package dk.betterlectio.android.feature.profilepicture

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

data class ProfilePictureSubmission(
    val id: String,
    val status: String,
    val createdAt: String,
    val submittedAt: String? = null,
    val reviewedAt: String? = null,
    val rejectionReason: String? = null,
    val reviewNote: String? = null,
    val approvedUrl: String? = null,
)

data class ProfilePictureState(
    val unlocked: Boolean = false,
    val referralConversions: Int = 0,
    val unlockThreshold: Int = 3,
    val currentUrl: String? = null,
    val approvedAt: String? = null,
    val nextEligibleAt: String? = null,
    val canSubmit: Boolean = false,
    val submission: ProfilePictureSubmission? = null,
) {
    val isPending: Boolean
        get() = submission?.status == "pending" || submission?.status == "uploading"

    val wasRejected: Boolean
        get() = submission?.status == "rejected"

    fun nextEligibleLabel(): String? {
        val instant = runCatching { Instant.parse(nextEligibleAt) }.getOrNull() ?: return null
        return DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG)
            .withZone(ZoneId.systemDefault())
            .format(instant)
    }
}

data class ProfilePictureSubmitResult(
    val ok: Boolean,
    val code: String? = null,
    val error: String? = null,
)

