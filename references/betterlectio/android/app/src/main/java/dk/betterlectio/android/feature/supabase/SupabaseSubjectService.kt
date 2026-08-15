package dk.betterlectio.android.feature.supabase

import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import timber.log.Timber
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

data class SupabaseSubjectMapping(
    val mappingId: String,
    val canonicalKey: String,
    val defaultName: String,
    val defaultColorHue: Int,
    val icon: String?,
    val displayName: String,
    val displayColorHue: Int,
    val displayIcon: String?,
    val deletedAt: String?,
)

/**
 * Subject / lesson mapping sync (iOS: `SupabaseSubjectService`).
 * RPCs: `get_student_lesson_mappings_v2`, `upsert_user_lesson_override_v2`,
 * `reset_user_lesson_override_v2`.
 */
@Singleton
class SupabaseSubjectService @Inject constructor(
    private val manager: SupabaseManager,
) {
    suspend fun fetchMappings(studentId: String, schoolId: String): List<SupabaseSubjectMapping> {
        val client = manager.client ?: return emptyList()
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return emptyList()
        return try {
            client.postgrest.rpc(
                function = "get_student_lesson_mappings_v2",
                parameters = FetchMappingsParams(
                    pSchoolId = schoolId,
                    pStudentId = studentId,
                ),
            ).decodeList<MappingRow>().mapNotNull { it.toMapping() }
        } catch (e: Exception) {
            Timber.w(e, "subject fetchMappings failed")
            emptyList()
        }
    }

    suspend fun upsertMappingOverride(
        studentId: String,
        schoolId: String,
        mappingId: String,
        displayName: String?,
        colorHue: Int?,
        icon: String?,
    ) {
        val client = manager.client ?: return
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return
        try {
            client.postgrest.rpc(
                function = "upsert_user_lesson_override_v2",
                parameters = UpsertOverrideParams(
                    pSchoolId = schoolId,
                    pStudentId = studentId,
                    pMappingId = mappingId.lowercase(),
                    pDisplayName = displayName,
                    pColorHue = colorHue,
                    pIcon = icon,
                    pClientUpdatedAt = clientTimestamp(),
                    pLastModifiedBy = "android",
                ),
            )
        } catch (e: Exception) {
            Timber.w(e, "subject upsertMappingOverride failed")
        }
    }

    suspend fun resetMappingOverride(
        studentId: String,
        schoolId: String,
        mappingId: String,
    ) {
        val client = manager.client ?: return
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return
        try {
            client.postgrest.rpc(
                function = "reset_user_lesson_override_v2",
                parameters = ResetOverrideParams(
                    pSchoolId = schoolId,
                    pStudentId = studentId,
                    pMappingId = mappingId.lowercase(),
                    pClientUpdatedAt = clientTimestamp(),
                    pLastModifiedBy = "android",
                ),
            )
        } catch (e: Exception) {
            Timber.w(e, "subject resetMappingOverride failed")
        }
    }

    @Serializable
    private data class FetchMappingsParams(
        @SerialName("p_school_id") val pSchoolId: String,
        @SerialName("p_student_id") val pStudentId: String,
    )

    @Serializable
    private data class UpsertOverrideParams(
        @SerialName("p_school_id") val pSchoolId: String,
        @SerialName("p_student_id") val pStudentId: String,
        @SerialName("p_mapping_id") val pMappingId: String,
        @SerialName("p_display_name") val pDisplayName: String?,
        @SerialName("p_color_hue") val pColorHue: Int?,
        @SerialName("p_icon") val pIcon: String?,
        @SerialName("p_client_updated_at") val pClientUpdatedAt: String,
        @SerialName("p_last_modified_by") val pLastModifiedBy: String,
    )

    @Serializable
    private data class ResetOverrideParams(
        @SerialName("p_school_id") val pSchoolId: String,
        @SerialName("p_student_id") val pStudentId: String,
        @SerialName("p_mapping_id") val pMappingId: String,
        @SerialName("p_client_updated_at") val pClientUpdatedAt: String,
        @SerialName("p_last_modified_by") val pLastModifiedBy: String,
    )

    @Serializable
    private data class MappingRow(
        val id: String? = null,
        @SerialName("mapping_id") val mappingId: String? = null,
        @SerialName("canonical_key") val canonicalKey: String? = null,
        @SerialName("default_name") val defaultName: String? = null,
        @SerialName("default_color_hue") val defaultColorHue: Int? = null,
        val icon: String? = null,
        @SerialName("default_icon") val defaultIcon: String? = null,
        @SerialName("display_name") val displayName: String? = null,
        @SerialName("display_color_hue") val displayColorHue: Int? = null,
        @SerialName("display_icon") val displayIcon: String? = null,
        @SerialName("deleted_at") val deletedAt: String? = null,
    ) {
        fun toMapping(): SupabaseSubjectMapping? {
            val mid = mappingId ?: id ?: return null
            val key = canonicalKey?.takeIf { it.isNotBlank() } ?: return null
            val defName = defaultName?.takeIf { it.isNotBlank() } ?: key
            val defHue = defaultColorHue ?: 210
            val ico = icon ?: defaultIcon
            return SupabaseSubjectMapping(
                mappingId = mid,
                canonicalKey = key,
                defaultName = defName,
                defaultColorHue = defHue,
                icon = ico,
                displayName = displayName?.takeIf { it.isNotBlank() } ?: defName,
                displayColorHue = displayColorHue ?: defHue,
                displayIcon = displayIcon ?: ico,
                deletedAt = deletedAt,
            )
        }
    }

    companion object {
        private val TIMESTAMP_FORMAT: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneOffset.UTC)

        private fun clientTimestamp(): String = TIMESTAMP_FORMAT.format(Instant.now())

        /** Convert 0–360 hue to ARGB (fixed S/V, matching iOS lesson colors). */
        fun hueToArgb(hue: Int): Long {
            val h = ((hue % 360) + 360) % 360 / 360f
            val s = 0.62f
            val v = 0.88f
            val i = (h * 6).toInt()
            val f = h * 6 - i
            val p = v * (1 - s)
            val q = v * (1 - f * s)
            val t = v * (1 - (1 - f) * s)
            val (r, g, b) = when (i % 6) {
                0 -> Triple(v, t, p)
                1 -> Triple(q, v, p)
                2 -> Triple(p, v, t)
                3 -> Triple(p, q, v)
                4 -> Triple(t, p, v)
                else -> Triple(v, p, q)
            }
            val ri = (r * 255).toInt().coerceIn(0, 255)
            val gi = (g * 255).toInt().coerceIn(0, 255)
            val bi = (b * 255).toInt().coerceIn(0, 255)
            return 0xFF000000L or (ri.toLong() shl 16) or (gi.toLong() shl 8) or bi.toLong()
        }

        fun argbToHue(argb: Long): Int {
            val r = ((argb shr 16) and 0xFF) / 255f
            val g = ((argb shr 8) and 0xFF) / 255f
            val b = (argb and 0xFF) / 255f
            val max = maxOf(r, g, b)
            val min = minOf(r, g, b)
            val d = max - min
            if (d < 1e-6f) return 0
            val h = when (max) {
                r -> ((g - b) / d + if (g < b) 6 else 0)
                g -> (b - r) / d + 2
                else -> (r - g) / d + 4
            } / 6f
            return ((h * 360f).toInt() % 360 + 360) % 360
        }
    }
}
