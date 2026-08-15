package dk.betterlectio.android.feature.auth

import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.model.School
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import dk.betterlectio.android.feature.supabase.SupabaseManager
import dk.betterlectio.android.feature.supabase.SupabaseSchoolService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

@Singleton
class SchoolRepository @Inject constructor(
    @Named("lectio") private val client: OkHttpClient,
    private val cache: SimpleCache,
    private val supabaseManager: SupabaseManager,
    private val supabaseSchools: SupabaseSchoolService,
) {
    suspend fun loadSchools(forceRefresh: Boolean = false): AppResult<List<School>> =
        withContext(Dispatchers.IO) {
            // Prefer remote catalog when Supabase is configured (iOS: SupabaseSchoolService)
            if (supabaseManager.isConfigured) {
                val remote = supabaseSchools.fetchAllSchools()
                if (remote.isNotEmpty()) {
                    return@withContext AppResult.Success(remote)
                }
            }
            if (!forceRefresh) {
                cache.get(CACHE_KEY)?.let { html ->
                    val parsed = parseSchools(html)
                    if (parsed.isNotEmpty()) return@withContext AppResult.Success(parsed)
                }
            }
            try {
                val req = Request.Builder()
                    .url("https://www.lectio.dk")
                    .header("User-Agent", "Mozilla/5.0 BetterLectio/1.0")
                    .get()
                    .build()
                client.newCall(req).execute().use { resp ->
                    val body = resp.body?.string().orEmpty()
                    if (!resp.isSuccessful || body.isBlank()) {
                        return@withContext AppResult.Success(DemoData.schools)
                    }
                    cache.put(CACHE_KEY, body)
                    val parsed = parseSchools(body)
                    AppResult.Success(if (parsed.isEmpty()) DemoData.schools else parsed)
                }
            } catch (e: Exception) {
                val cached = cache.get(CACHE_KEY)?.let { parseSchools(it) }.orEmpty()
                if (cached.isNotEmpty()) AppResult.Success(cached)
                else AppResult.Success(DemoData.schools)
            }
        }

    private fun parseSchools(html: String): List<School> {
        val doc = Jsoup.parse(html)
        val list = doc.getElementById("schoolsdiv") ?: return emptyList()
        return list.select("a[href*=lectio]").mapNotNull { a ->
            val href = a.attr("href")
            val id = Regex("""/lectio/(\d+)/""").find(href)?.groupValues?.get(1)?.toIntOrNull()
                ?: Regex("""\d+""").find(href)?.value?.toIntOrNull()
                ?: return@mapNotNull null
            val name = a.text().trim()
            if (name.isBlank()) return@mapNotNull null
            School(id = id, name = name)
        }.distinctBy { it.id }.sortedBy { it.name.lowercase() }
    }

    companion object {
        private const val CACHE_KEY = "schools_list_html"
    }
}
