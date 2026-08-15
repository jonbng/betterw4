package dk.betterlectio.android.feature.feedback

import android.graphics.Bitmap
import android.os.Build
import com.posthog.PostHog
import dk.betterlectio.android.BuildConfig
import dk.betterlectio.android.core.lectio.session.AuthState
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.feature.supabase.SupabaseFeedbackService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.ByteArrayOutputStream
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FeedbackRepository @Inject constructor(
    private val sessionController: SessionController,
    private val logBuffer: FeedbackLogBuffer,
    private val feedbackService: SupabaseFeedbackService,
) {

    fun currentLogs(): String = logBuffer.snapshot()

    suspend fun submit(submission: FeedbackSubmission): FeedbackSubmitResult =
        withContext(Dispatchers.IO) {
            try {
                val auth = sessionController.authState.value
                if (auth !is AuthState.Authenticated) {
                    Timber.w("Feedback submit blocked: not authenticated (%s)", auth::class.simpleName)
                    return@withContext FeedbackSubmitResult.Failure(
                        IllegalStateException("Not signed in"),
                    )
                }
                if (auth.student.isDemo) {
                    Timber.w("Feedback submit blocked: demo session")
                    return@withContext FeedbackSubmitResult.Failure(
                        IllegalStateException("Demo mode"),
                    )
                }

                val screenshot = if (
                    submission.includeScreenshot &&
                    submission.capture.screenshot != null &&
                    !submission.capture.screenshot.isRecycled
                ) {
                    encodeScreenshot(submission.capture.screenshot)
                } else {
                    null
                }

                val logs = if (submission.includeLogs) {
                    submission.capture.logs.ifBlank { logBuffer.snapshot() }
                        .take(FeedbackLogBuffer.MAX_SNAPSHOT_CHARS)
                } else {
                    null
                }

                val context = linkedMapOf<String, Any?>(
                    "app_version" to BuildConfig.VERSION_NAME,
                    "app_version_code" to BuildConfig.VERSION_CODE,
                    "build_type" to BuildConfig.BUILD_TYPE,
                    "os_version" to Build.VERSION.SDK_INT.toString(),
                    "device_model" to Build.MODEL.orEmpty(),
                    "device_manufacturer" to Build.MANUFACTURER.orEmpty(),
                    "locale" to Locale.getDefault().toLanguageTag(),
                    "include_logs" to (logs != null),
                    "logs" to logs,
                    "posthog_session_id" to PostHog.getSessionId()?.toString(),
                    "posthog_distinct_id" to "lectio:${auth.student.studentId}",
                )

                val result = feedbackService.submit(
                    SupabaseFeedbackService.SubmitRequest(
                        studentId = auth.student.studentId,
                        schoolId = auth.student.gymId,
                        category = submission.category.analyticsKey,
                        message = submission.message.trim().take(MAX_MESSAGE_CHARS),
                        context = context,
                        screenshotJpeg = screenshot?.bytes,
                        screenshotWidth = screenshot?.width,
                        screenshotHeight = screenshot?.height,
                    ),
                )

                // Thin analytics breadcrumb only — payload lives in Supabase.
                runCatching {
                    PostHog.capture(
                        event = EVENT_NAME,
                        properties = mapOf(
                            "feedback_id" to result.feedbackId,
                            "category" to submission.category.analyticsKey,
                            "platform" to "android",
                            "has_screenshot" to (screenshot != null),
                            "has_logs" to (logs != null),
                        ),
                    )
                }

                Timber.i(
                    "Feedback submitted id=%s category=%s messageLen=%d screenshot=%s logs=%s",
                    result.feedbackId,
                    submission.category.analyticsKey,
                    submission.message.length,
                    screenshot != null,
                    logs != null,
                )
                FeedbackSubmitResult.Success
            } catch (t: Throwable) {
                Timber.e(t, "Feedback submit failed")
                FeedbackSubmitResult.Failure(t)
            }
        }

    /**
     * JPEG bytes for Storage upload. Soft size budget (~500 KB) — higher than the old
     * PostHog event limit because attachments no longer ride event properties.
     */
    private fun encodeScreenshot(bitmap: Bitmap): EncodedScreenshot? {
        var quality = 82
        var working = bitmap
        var recycledWorking = false
        try {
            while (quality >= 40) {
                val bytes = compressJpeg(working, quality) ?: return null
                if (bytes.size <= MAX_SCREENSHOT_BYTES) {
                    return EncodedScreenshot(
                        bytes = bytes,
                        width = working.width,
                        height = working.height,
                    )
                }
                if (working.width > 480) {
                    val nextW = (working.width * 0.75f).toInt().coerceAtLeast(480)
                    val nextH = (working.height * (nextW.toFloat() / working.width)).toInt()
                        .coerceAtLeast(1)
                    val scaled = Bitmap.createScaledBitmap(working, nextW, nextH, true)
                    if (recycledWorking && working !== bitmap) working.recycle()
                    working = scaled
                    recycledWorking = working !== bitmap
                }
                quality -= 12
            }
            Timber.w("Feedback screenshot too large after compression — omitting")
            return null
        } catch (oom: OutOfMemoryError) {
            Timber.w(oom, "Feedback screenshot encode OOM")
            return null
        } finally {
            if (recycledWorking && working !== bitmap && !working.isRecycled) {
                working.recycle()
            }
        }
    }

    private fun compressJpeg(bitmap: Bitmap, quality: Int): ByteArray? {
        return try {
            val stream = ByteArrayOutputStream()
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)) return null
            stream.toByteArray()
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    private data class EncodedScreenshot(
        val bytes: ByteArray,
        val width: Int,
        val height: Int,
    )

    companion object {
        const val EVENT_NAME = "app_feedback_submitted"
        private const val MAX_MESSAGE_CHARS = 4_000
        private const val MAX_SCREENSHOT_BYTES = 500_000
    }
}
