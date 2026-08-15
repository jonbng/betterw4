package dk.betterlectio.android.feature.studiekort

import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.directory.AvatarUrls
import javax.inject.Inject
import javax.inject.Singleton

data class StudentCard(
    val student: Student,
    val photoUrl: String?,
    val qrUrl: String?,
    val birthday: String? = null,
)

@Singleton
class StudiekortRepository @Inject constructor(
    private val session: SessionController,
    private val client: LectioClient,
) {
    fun loadCard(): AppResult<StudentCard> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)

        if (student.isDemo) {
            val demoPhoto = DEMO_PHOTO_URL
            val demoQr = demoQrUrl(student)
            val enriched = student.copy(
                name = student.name ?: "Demo Elev",
                classLabel = student.classLabel ?: "3.x",
                schoolName = student.schoolName ?: "Demo Gymnasium",
                pictureId = student.pictureId ?: "demo",
            )
            return AppResult.Success(
                StudentCard(enriched, demoPhoto, demoQr, birthday = "1. januar 2008"),
            )
        }

        // Constructed fallbacks while scrape may be async
        val photo = student.pictureId?.let {
            AvatarUrls.fromPictureId(student.gymId, it)
        }
        val t = System.currentTimeMillis()
        val qr =
            "https://www.lectio.dk/lectio/${student.gymId}/GetImage.aspx?type=studiekortqr&studentid=${student.studentId}&time=$t"
        return AppResult.Success(StudentCard(student, photo, qr, birthday = null))
    }

    /** Full scrape path: elevforside / studiekort HTML → photo + QR. */
    suspend fun loadCardScraped(): AppResult<StudentCard> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return loadCard()

        // Flutter: digitaltStudiekort.aspx; keep elevforside fallbacks
        val paths = listOf(
            "digitaltStudiekort.aspx?elevid=${student.studentId}",
            "digitaltStudiekort.aspx",
            "Studiekort.aspx?elevid=${student.studentId}",
            "elevforside.aspx?elevid=${student.studentId}",
            "elevkort.aspx?elevid=${student.studentId}",
        )
        for (path in paths) {
            when (val res = client.get(path)) {
                is AppResult.Failure -> continue
                is AppResult.Success -> {
                    val parsed = StudiekortParser.parse(
                        res.data.body,
                        student.gymId,
                        student.studentId,
                    )
                    if (parsed.photoUrl != null || parsed.qrUrl != null || parsed.name != null) {
                        val enriched = student.copy(
                            name = parsed.name ?: student.name,
                            classLabel = parsed.classLabel ?: student.classLabel,
                            schoolName = parsed.schoolName ?: student.schoolName,
                            pictureId = parsed.pictureId ?: student.pictureId,
                        )
                        return AppResult.Success(
                            StudentCard(
                                student = enriched,
                                photoUrl = parsed.photoUrl,
                                qrUrl = parsed.qrUrl,
                                birthday = parsed.birthday,
                            ),
                        )
                    }
                }
            }
        }
        return loadCard()
    }

    companion object {
        const val DEMO_PHOTO_URL =
            "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&f=y&s=256"

        fun demoQrUrl(student: Student): String {
            val payload = "betterlectio-demo:${student.studentId}:${student.gymId}"
            return "https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=" +
                java.net.URLEncoder.encode(payload, Charsets.UTF_8.name())
        }
    }
}
