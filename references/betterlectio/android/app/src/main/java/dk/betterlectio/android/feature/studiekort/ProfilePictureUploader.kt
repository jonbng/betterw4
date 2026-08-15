package dk.betterlectio.android.feature.studiekort

import android.content.Context
import android.net.Uri
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Profile picture change via Lectio PhotoDialog form post (Flutter parity).
 * Demo always succeeds. Live path GET dialog → POST form with image data-URL field.
 */
@Singleton
class ProfilePictureUploader @Inject constructor(
    private val session: SessionController,
    private val client: LectioClient,
    @ApplicationContext private val context: Context,
) {
    suspend fun upload(uri: Uri): AppResult<Unit> {
        val student = session.currentStudent
            ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(Unit)
        }
        return try {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return AppResult.Failure(AppError.Unknown("Kunne ikke læse billede"))
            if (bytes.isEmpty()) {
                return AppResult.Failure(AppError.Unknown("Tom fil"))
            }
            val mime = context.contentResolver.getType(uri) ?: "image/jpeg"
            val path = ProfilePhotoFormBuilder.dialogPath(student.studentId)
            when (val page = client.get(path, FetchPriority.Important)) {
                is AppResult.Failure -> page
                is AppResult.Success -> {
                    val fields = ProfilePhotoFormBuilder.buildFormFields(
                        pageHtml = page.data.body,
                        imageBytes = bytes,
                        mimeType = mime,
                    )
                    when (val post = client.postForm(path, fields, FetchPriority.Important)) {
                        is AppResult.Failure -> post
                        is AppResult.Success -> {
                            if (ProfilePhotoFormBuilder.isUploadAccepted(post.data.body)) {
                                AppResult.Success(Unit)
                            } else {
                                AppResult.Failure(
                                    AppError.Unknown("Lectio afviste profilbillede-ændringen"),
                                )
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            AppResult.Failure(AppError.Unknown(e.message ?: "Upload fejlede", e))
        }
    }
}
