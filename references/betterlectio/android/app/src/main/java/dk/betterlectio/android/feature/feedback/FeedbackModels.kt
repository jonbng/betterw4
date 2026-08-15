package dk.betterlectio.android.feature.feedback

import android.graphics.Bitmap
import androidx.annotation.StringRes
import dk.betterlectio.android.R

enum class FeedbackCategory(
    val analyticsKey: String,
    @param:StringRes val labelRes: Int,
    @param:StringRes val hintRes: Int,
) {
    BUG(
        analyticsKey = "bug",
        labelRes = R.string.feedback_category_bug,
        hintRes = R.string.feedback_hint_bug,
    ),
    IDEA(
        analyticsKey = "idea",
        labelRes = R.string.feedback_category_idea,
        hintRes = R.string.feedback_hint_idea,
    ),
    OTHER(
        analyticsKey = "other",
        labelRes = R.string.feedback_category_other,
        hintRes = R.string.feedback_hint_other,
    ),
}

/**
 * Snapshot of the screen + diagnostics captured at shake time (before the sheet covers UI).
 */
data class FeedbackCapture(
    val screenshot: Bitmap?,
    val logs: String,
    val capturedAtMs: Long = System.currentTimeMillis(),
)

data class FeedbackSubmission(
    val category: FeedbackCategory,
    val message: String,
    val includeScreenshot: Boolean,
    val includeLogs: Boolean,
    val capture: FeedbackCapture,
)

sealed class FeedbackSubmitResult {
    data object Success : FeedbackSubmitResult()
    data class Failure(val throwable: Throwable? = null) : FeedbackSubmitResult()
}
