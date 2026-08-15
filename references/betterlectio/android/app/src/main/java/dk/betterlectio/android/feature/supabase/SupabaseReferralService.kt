package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.feature.referral.RecentReferral
import dk.betterlectio.android.feature.referral.ReferralStats
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SupabaseReferralService @Inject constructor(
    private val manager: SupabaseManager,
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    suspend fun getStats(studentId: String): ReferralStats? {
        if (studentId.isBlank()) return null
        val client = manager.client ?: return null
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return null
        return try {
            val rows = client.postgrest.rpc(
                function = "get_referral_stats",
                parameters = StatsParams(pStudentId = studentId),
            ).decodeList<RawStatsRow>()
            val row = rows.firstOrNull()
            ReferralStats(
                totalClicks = row?.totalClicks?.toInt() ?: 0,
                uniqueClickers = row?.uniqueClickers?.toInt() ?: 0,
                conversions = row?.conversions?.toInt() ?: 0,
                recentReferrals = (row?.recentReferrals ?: emptyList()).map {
                    RecentReferral(
                        studentId = it.studentId,
                        name = it.name,
                        attributedAt = it.attributedAt,
                    )
                },
            )
        } catch (e: Exception) {
            Timber.w(e, "referral getStats failed")
            null
        }
    }

    /**
     * Attribute this install via Install Referrer cookie id.
     * Returns null when there was nothing to attribute or the call failed softly.
     */
    suspend fun finalizeAndroid(
        studentId: String,
        schoolId: Int?,
        cookieId: String,
    ): FinalizeResult? {
        val client = manager.client ?: return null
        if (manager.awaitSessionReady() !is SupabaseSessionState.Ready) return null
        if (client.auth.currentSessionOrNull() == null) return null
        return try {
            val response = client.functions.invoke("referral-finalize") {
                contentType(ContentType.Application.Json)
                setBody(
                    json.encodeToString(
                        FinalizeRequest.serializer(),
                        FinalizeRequest(
                            studentId = studentId,
                            schoolId = schoolId,
                            cookieId = cookieId,
                            platform = "android",
                        ),
                    ),
                )
            }
            val body = response.bodyAsText()
            json.decodeFromString(FinalizeResult.serializer(), body)
        } catch (e: Exception) {
            Timber.w(e, "referral finalize failed")
            null
        }
    }

    @Serializable
    private data class StatsParams(
        @SerialName("p_student_id") val pStudentId: String,
    )

    @Serializable
    private data class RawStatsRow(
        @SerialName("total_clicks") val totalClicks: Long? = null,
        @SerialName("unique_clickers") val uniqueClickers: Long? = null,
        @SerialName("conversions") val conversions: Long? = null,
        @SerialName("recent_referrals") val recentReferrals: List<RawRecent>? = null,
    )

    @Serializable
    private data class RawRecent(
        @SerialName("student_id") val studentId: String,
        val name: String? = null,
        @SerialName("attributed_at") val attributedAt: String? = null,
    )

    @Serializable
    private data class FinalizeRequest(
        val studentId: String,
        val schoolId: Int? = null,
        val cookieId: String,
        val platform: String,
    )

    @Serializable
    data class FinalizeResult(
        val attributed: Boolean = false,
        val reason: String? = null,
        val referrerStudentId: String? = null,
        val referrerName: String? = null,
        val referrerUnlocked: Boolean? = null,
    )
}
