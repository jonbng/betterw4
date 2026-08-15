package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.w4.http.W4UserAgent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Public UWCRCN Google Calendar (`calendar@uwcrcn.no`). Same feed as the W4 Home embed.
 */
@Singleton
class SchoolCalendarRepository @Inject constructor(
    @param:Named("external") private val http: OkHttpClient,
    private val cache: SimpleCache,
) {
    suspend fun eventsForWeek(
        year: Int,
        week: Int,
        forceRefresh: Boolean = false,
    ): List<ScheduleEvent> = withContext(Dispatchers.IO) {
        val ics = loadIcs(forceRefresh) ?: return@withContext emptyList()
        runCatching { SchoolCalendar.eventsFromIcs(ics, year, week) }
            .onFailure { Timber.w(it, "Failed to parse school Google Calendar") }
            .getOrDefault(emptyList())
    }

    private fun loadIcs(forceRefresh: Boolean): String? {
        if (!forceRefresh) {
            cache.getWithMeta(CACHE_KEY)?.let { cached ->
                val age = System.currentTimeMillis() - cached.updatedAtMs
                if (age in 0 until CACHE_TTL_MS && cached.value.isNotBlank()) {
                    return cached.value
                }
            }
        }
        val fetched = fetchIcs()
        if (fetched != null) {
            runCatching { cache.put(CACHE_KEY, fetched) }
            return fetched
        }
        return cache.get(CACHE_KEY)?.takeIf { it.isNotBlank() }
    }

    private fun fetchIcs(): String? {
        val request = Request.Builder()
            .url(SchoolCalendar.ICS_URL)
            .header("User-Agent", W4UserAgent.VALUE)
            .header("Accept", "text/calendar, text/plain, */*")
            .get()
            .build()
        return try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Timber.w("School Google Calendar HTTP %s", response.code)
                    return null
                }
                val body = response.body?.string().orEmpty()
                if (!body.contains("BEGIN:VCALENDAR", ignoreCase = true)) {
                    Timber.w("School Google Calendar body was not iCalendar")
                    return null
                }
                body
            }
        } catch (e: Exception) {
            Timber.w(e, "School Google Calendar fetch failed")
            null
        }
    }

    companion object {
        const val CACHE_KEY = "school_gcal_ics"
        const val CACHE_TTL_MS = 6L * 60 * 60 * 1000
    }
}
