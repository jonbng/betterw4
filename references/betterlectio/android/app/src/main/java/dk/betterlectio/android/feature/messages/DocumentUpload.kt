package dk.betterlectio.android.feature.messages

import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.Buffer
import org.json.JSONObject
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Lectio document upload used by message compose/reply attachments.
 *
 * Extension parity: `uploadFileToLectio` in `beskeder-submit.ts`
 *   POST /lectio/{schoolId}/dokumentupload.aspx
 *   multipart field name: `file`
 *   response: JSON `{ serializedId: "…" }` or text containing serializedId
 */
@Singleton
class DocumentUpload @Inject constructor(
    private val client: LectioClient,
) {
    suspend fun upload(
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        priority: FetchPriority = FetchPriority.Important,
    ): AppResult<String> {
        if (bytes.isEmpty()) {
            return AppResult.Failure(AppError.Unknown("Tom fil"))
        }
        if (bytes.size > MAX_BYTES) {
            return AppResult.Failure(AppError.Unknown("Filen er for stor (max ${MAX_BYTES / (1024 * 1024)} MB)"))
        }
        val mediaType = (mimeType.ifBlank { "application/octet-stream" }).toMediaTypeOrNull()
            ?: "application/octet-stream".toMediaTypeOrNull()!!
        val multipart = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart(
                "file",
                fileName.ifBlank { "file.bin" },
                bytes.toRequestBody(mediaType),
            )
            .build()
        val buffer = Buffer()
        multipart.writeTo(buffer)
        val bodyBytes = buffer.readByteArray()
        // contentType() is the RequestBody API (property access is private on MultipartBody)
        val contentType = multipart.contentType()?.toString()
            ?: "multipart/form-data; boundary=${multipart.boundary}"

        return when (
            val res = client.postMultipart(
                pathOrUrl = UPLOAD_PATH,
                body = bodyBytes,
                contentType = contentType,
                priority = priority,
            )
        ) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val id = parseSerializedId(res.data.body)
                if (id.isNullOrBlank()) {
                    AppResult.Failure(AppError.Unknown("Kunne ikke parse upload-svar fra Lectio"))
                } else {
                    AppResult.Success(id)
                }
            }
        }
    }

    companion object {
        const val UPLOAD_PATH = "dokumentupload.aspx"
        const val MAX_BYTES = 25 * 1024 * 1024

        private val SERIALIZED_ID_REGEX =
            Regex("""serializedId['":\s]+['"]([^'"]+)['"]""")

        fun parseSerializedId(responseBody: String): String? {
            val trimmed = responseBody.trim()
            if (trimmed.isEmpty()) return null
            try {
                val json = JSONObject(trimmed)
                val id = json.optString("serializedId", "")
                if (id.isNotBlank()) return id
            } catch (_: Exception) {
                // fall through to regex
            }
            return SERIALIZED_ID_REGEX.find(trimmed)?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() }
        }
    }
}
