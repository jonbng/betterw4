package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.feature.directory.StudentProfile
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Read rich student profile fields through the privacy-masked RPC.
 * Missing rows / failures return null.
 */
@Singleton
class SupabaseStudentProfileService @Inject constructor(
    private val manager: SupabaseManager,
) {
    suspend fun getStudent(studentId: String): StudentProfile? {
        val id = studentId.trim()
        if (id.isEmpty()) return null
        val client = manager.client ?: return null
        return try {
            if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return null
            client.postgrest.rpc(
                function = "get_student_profile",
                parameters = GetStudentProfileParams(id),
            )
                .decodeList<StudentProfileRow>()
                .firstOrNull()
                ?.toProfile()
        } catch (e: Exception) {
            Timber.w(e, "student profile fetch failed for id=%s", id)
            null
        }
    }
}

@Serializable
private data class GetStudentProfileParams(
    @SerialName("p_student_id") val studentId: String,
)

@Serializable
private data class StudentProfileRow(
    val id: String,
    val name: String? = null,
    val description: String? = null,
    val instagram: String? = null,
    val birthdate: String? = null,
    @SerialName("show_birthday") val showBirthday: Boolean = false,
    @SerialName("custom_pfp_url") val customPfpUrl: String? = null,
    @SerialName("lectio_pfp_url") val lectioPfpUrl: String? = null,
    @SerialName("class_name") val className: String? = null,
    @SerialName("last_seen_at") val lastSeenAt: String? = null,
    @SerialName("extension_installed_at") val extensionInstalledAt: String? = null,
    @SerialName("extension_uninstalled_at") val extensionUninstalledAt: String? = null,
    @SerialName("app_installed_at") val appInstalledAt: String? = null,
) {
    fun toProfile() = StudentProfile(
        id = id,
        name = name,
        description = description,
        instagram = instagram,
        birthdate = birthdate,
        showBirthday = showBirthday,
        customPfpUrl = customPfpUrl,
        lectioPfpUrl = lectioPfpUrl,
        className = className,
        lastSeenAt = lastSeenAt,
        extensionInstalledAt = extensionInstalledAt,
        extensionUninstalledAt = extensionUninstalledAt,
        appInstalledAt = appInstalledAt,
    )
}
