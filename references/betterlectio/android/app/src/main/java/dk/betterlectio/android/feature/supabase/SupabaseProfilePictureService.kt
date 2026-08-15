package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.feature.profilepicture.ProfilePictureState
import dk.betterlectio.android.feature.profilepicture.ProfilePictureSubmission
import dk.betterlectio.android.feature.profilepicture.ProfilePictureSubmitResult
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.ktor.client.request.forms.MultiPartFormDataContent
import io.ktor.client.request.forms.formData
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SupabaseProfilePictureService @Inject constructor(
    private val manager: SupabaseManager,
) {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    suspend fun getState(studentId: String): ProfilePictureState? {
        if (studentId.isBlank()) return null
        val client = manager.client ?: return null
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return null
        return try {
            client.postgrest.rpc(
                function = "get_my_profile_picture_state",
                parameters = StateParams(studentId),
            ).decodeAs<StateRow>().toModel()
        } catch (t: Throwable) {
            Timber.w(t, "profile picture state failed")
            null
        }
    }

    suspend fun submit(
        studentId: String,
        schoolId: Int,
        bytes: ByteArray,
        mimeType: String,
    ): ProfilePictureSubmitResult {
        val client = manager.client ?: return ProfilePictureSubmitResult(false, "not_configured")
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) {
            return ProfilePictureSubmitResult(false, "session_unavailable")
        }
        return try {
            val response = client.functions.invoke("profile-picture-submit") {
                setBody(
                    MultiPartFormDataContent(
                        formData {
                            append("studentId", studentId)
                            append("schoolId", schoolId.toString())
                            append("platform", "android")
                            append(
                                "file",
                                bytes,
                                Headers.build {
                                    append(HttpHeaders.ContentType, mimeType)
                                    append(
                                        HttpHeaders.ContentDisposition,
                                        "filename=profile.${extensionFor(mimeType)}",
                                    )
                                },
                            )
                        },
                    ),
                )
            }
            val body = response.bodyAsText()
            val result = json.decodeFromString<SubmitRow>(body)
            ProfilePictureSubmitResult(result.ok, result.code, result.error)
        } catch (t: Throwable) {
            Timber.w(t, "profile picture submit failed")
            ProfilePictureSubmitResult(false, "upload_failed", t.message)
        }
    }

    private fun extensionFor(mimeType: String): String = when (mimeType) {
        "image/png" -> "png"
        "image/webp" -> "webp"
        else -> "jpg"
    }

    @Serializable
    private data class StateParams(@SerialName("p_student_id") val studentId: String)

    @Serializable
    private data class StateRow(
        val unlocked: Boolean = false,
        val referralConversions: Int = 0,
        val unlockThreshold: Int = 3,
        val currentUrl: String? = null,
        val approvedAt: String? = null,
        val nextEligibleAt: String? = null,
        val canSubmit: Boolean = false,
        val submission: SubmissionRow? = null,
    ) {
        fun toModel() = ProfilePictureState(
            unlocked = unlocked,
            referralConversions = referralConversions,
            unlockThreshold = unlockThreshold,
            currentUrl = currentUrl,
            approvedAt = approvedAt,
            nextEligibleAt = nextEligibleAt,
            canSubmit = canSubmit,
            submission = submission?.toModel(),
        )
    }

    @Serializable
    private data class SubmissionRow(
        val id: String,
        val status: String,
        val createdAt: String,
        val submittedAt: String? = null,
        val reviewedAt: String? = null,
        val rejectionReason: String? = null,
        val reviewNote: String? = null,
        val approvedUrl: String? = null,
    ) {
        fun toModel() = ProfilePictureSubmission(
            id, status, createdAt, submittedAt, reviewedAt,
            rejectionReason, reviewNote, approvedUrl,
        )
    }

    @Serializable
    private data class SubmitRow(
        val ok: Boolean = false,
        val code: String? = null,
        val error: String? = null,
    )
}
