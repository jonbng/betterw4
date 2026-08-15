package dk.betterlectio.android.feature.supabase

import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import io.ktor.http.ContentType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import timber.log.Timber
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Submit private feedback via `submit_feedback` + Storage attachment upload.
 */
@Singleton
class SupabaseFeedbackService @Inject constructor(
    private val manager: SupabaseManager,
) {
    data class SubmitRequest(
        val studentId: String,
        val schoolId: Int,
        val category: String,
        val message: String,
        val context: Map<String, Any?>,
        val screenshotJpeg: ByteArray? = null,
        val screenshotWidth: Int? = null,
        val screenshotHeight: Int? = null,
    )

    data class SubmitResult(
        val feedbackId: String,
        val attachmentId: String? = null,
    )

    suspend fun submit(request: SubmitRequest): SubmitResult {
        val client = manager.client
            ?: error("Supabase not configured")
        val session = manager.awaitSessionReady()
        if (session is SupabaseSessionState.Unavailable) {
            throw SupabaseUnavailableException(session.reason)
        }

        val contextJson = buildJsonObject {
            for ((key, value) in request.context) {
                when (value) {
                    null -> Unit
                    is Boolean -> put(key, JsonPrimitive(value))
                    is Number -> put(key, JsonPrimitive(value))
                    else -> {
                        val text = value.toString()
                        if (text.isNotBlank()) put(key, JsonPrimitive(text))
                    }
                }
            }
        }

        val feedbackId = client.postgrest.rpc(
            function = "submit_feedback",
            parameters = SubmitFeedbackParams(
                pStudentId = request.studentId,
                pSchoolId = request.schoolId,
                pCategory = request.category,
                pMessage = request.message,
                pPlatform = "android",
                pContext = contextJson,
            ),
        ).decodeAs<String>()

        Timber.i("feedback submitted id=%s", feedbackId)

        var attachmentId: String? = null
        val jpeg = request.screenshotJpeg
        if (jpeg != null && jpeg.isNotEmpty()) {
            val path =
                "${request.schoolId}/${request.studentId}/$feedbackId/${UUID.randomUUID()}.jpg"
            try {
                client.storage.from(BUCKET).upload(path, jpeg) {
                    upsert = false
                    contentType = ContentType.Image.JPEG
                }
                attachmentId = client.postgrest.rpc(
                    function = "register_feedback_attachment",
                    parameters = RegisterAttachmentParams(
                        pFeedbackId = feedbackId,
                        pKind = "screenshot",
                        pStoragePath = path,
                        pMimeType = "image/jpeg",
                        pByteSize = jpeg.size,
                        pWidth = request.screenshotWidth,
                        pHeight = request.screenshotHeight,
                    ),
                ).decodeAs<String>()
                Timber.i("feedback attachment registered id=%s path=%s", attachmentId, path)
            } catch (t: Throwable) {
                // Feedback row already exists — don't fail the whole submit on attachment.
                Timber.e(t, "feedback attachment upload/register failed path=%s", path)
            }
        }

        return SubmitResult(feedbackId = feedbackId, attachmentId = attachmentId)
    }

    @Serializable
    private data class SubmitFeedbackParams(
        @SerialName("p_student_id") val pStudentId: String,
        @SerialName("p_school_id") val pSchoolId: Int,
        @SerialName("p_category") val pCategory: String,
        @SerialName("p_message") val pMessage: String,
        @SerialName("p_platform") val pPlatform: String,
        @SerialName("p_context") val pContext: JsonObject,
    )

    @Serializable
    private data class RegisterAttachmentParams(
        @SerialName("p_feedback_id") val pFeedbackId: String,
        @SerialName("p_kind") val pKind: String,
        @SerialName("p_storage_path") val pStoragePath: String,
        @SerialName("p_mime_type") val pMimeType: String? = null,
        @SerialName("p_byte_size") val pByteSize: Int? = null,
        @SerialName("p_width") val pWidth: Int? = null,
        @SerialName("p_height") val pHeight: Int? = null,
    )

    companion object {
        const val BUCKET = "feedback-attachments"
    }
}
