package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.core.model.School
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.Serializable
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Schools catalog from Supabase `schools` table (iOS: `SupabaseSchoolService`).
 */
@Singleton
class SupabaseSchoolService @Inject constructor(
    private val manager: SupabaseManager,
) {
    suspend fun fetchAllSchools(): List<School> {
        val client = manager.client ?: return emptyList()
        // Schools are public/anon-readable; no need to wait for user session.
        return try {
            val rows = client.from("schools")
                .select {
                    filter {
                        // select all rows; order applied below
                    }
                    order("name", Order.ASCENDING)
                }
                .decodeList<SchoolRow>()
            rows.map { School(id = it.id.toInt(), name = it.name) }
        } catch (e: Exception) {
            Timber.w(e, "Supabase schools fetch failed")
            emptyList()
        }
    }

    @Serializable
    private data class SchoolRow(
        val id: Long,
        val name: String,
    )
}
