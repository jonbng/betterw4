package dk.betterw4.android.feature.studiekort

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.core.model.Student
import dk.betterw4.android.core.model.W4School
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.directory.W4PeopleParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

data class StudentCard(
    val student: Student,
    val photoUrl: String?,
    val qrUrl: String?,
    val birthday: String? = null,
    val email: String? = null,
    val house: String? = null,
    val country: String? = null,
    val pronouns: String? = null,
    val year: String? = null,
)

@Singleton
class StudiekortRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val session: SessionController,
    private val client: W4Client,
) {
    private val authority: String = "${context.packageName}.fileprovider"

    fun loadCard(): AppResult<StudentCard> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoCard(student))
        val photo = W4PeopleParser.guessPhotoUrl(student.studentId)
        return AppResult.Success(StudentCard(student = student, photoUrl = photo, qrUrl = null))
    }

    suspend fun loadCardScraped(): AppResult<StudentCard> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return loadCard()
        return when (val res = client.get(W4Urls.Routes.PROFILE)) {
            is AppResult.Failure -> {
                Timber.w("site/profile failed, using session identity")
                loadCard()
            }
            is AppResult.Success -> {
                val parsed = W4PeopleParser.parseProfile(res.data.body)
                if (parsed == null) return loadCard()
                val yearHouse = listOfNotNull(
                    parsed.year?.let { "Year $it" },
                    parsed.house,
                ).joinToString(" · ").ifBlank { student.classLabel }
                val enriched = student.copy(
                    name = parsed.entity.name.ifBlank { student.name },
                    classLabel = yearHouse,
                    schoolName = student.schoolName ?: W4School.NAME,
                    pictureId = parsed.entity.id,
                )
                AppResult.Success(
                    StudentCard(
                        student = enriched,
                        photoUrl = parsed.entity.avatarUrl,
                        qrUrl = null,
                        birthday = parsed.birthday,
                        email = parsed.email,
                        house = parsed.house,
                        country = parsed.country,
                        pronouns = parsed.pronouns,
                        year = parsed.year,
                    ),
                )
            }
        }
    }

    suspend fun openLetterOfAttendance(): AppResult<Uri> = withContext(Dispatchers.IO) {
        val student = session.currentStudent ?: return@withContext AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return@withContext AppResult.Failure(AppError.Unknown("Letter of Attendance is not available in demo"))
        }
        when (val res = client.getBytes(W4Urls.Routes.LETTER_ATTENDANCE)) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val bytes = res.data
                if (bytes.size < 5 || String(bytes.copyOfRange(0, 5)) != "%PDF-") {
                    return@withContext AppResult.Failure(
                        AppError.Parsing("Letter of Attendance was not a PDF"),
                    )
                }
                val dir = File(context.cacheDir, "letters").apply { mkdirs() }
                val file = File(dir, "letter-of-attendance.pdf")
                file.writeBytes(bytes)
                AppResult.Success(FileProvider.getUriForFile(context, authority, file))
            }
        }
    }

    private fun demoCard(student: Student) = StudentCard(
        student = student.copy(
            name = student.name ?: "Demo Elev",
            classLabel = student.classLabel ?: "Year 1 · Haugland",
            schoolName = student.schoolName ?: W4School.NAME,
        ),
        photoUrl = "https://www.gravatar.com/avatar/11111111111111111111111111111111?d=identicon&s=256",
        qrUrl = null,
        birthday = "1 January 2008",
        email = "demo@uwcrcn.no",
        house = "Haugland",
        country = "Denmark",
        pronouns = "they/them",
        year = "1",
    )
}
