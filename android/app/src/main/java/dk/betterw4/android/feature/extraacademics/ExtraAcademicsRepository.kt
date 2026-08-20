package dk.betterw4.android.feature.extraacademics

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import org.jsoup.Jsoup
import javax.inject.Inject
import javax.inject.Singleton

enum class ExtraAcademicsPage(val route: String, val displayName: String, val cacheKey: String) {
    MY_ACTIVITIES(W4Urls.Routes.EA_ACTIVITIES, "My activities", "ea_activities"),
    DIARY(W4Urls.Routes.EA_DIARY, "My EA diary", "ea_diary"),
    PORTFOLIO(W4Urls.Routes.EA_PORTFOLIO, "My portfolio", "ea_portfolio"),
    INTERVIEWS(W4Urls.Routes.EA_INTERVIEWS, "My CAS interviews", "ea_interviews"),
    SAFETY_NET(W4Urls.Routes.EA_SAFETYNET, "My SafetyNet", "ea_safetynet"),
}

data class W4PageSnapshot(
    val heading: String?,
    val contentFragmentHtml: String?,
    val url: String,
)

/**
 * Extra Academics pages have never been captured, so this repository returns
 * `#content_inner` for the UI to render — the same approach as iOS.
 */
@Singleton
class ExtraAcademicsRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun page(page: ExtraAcademicsPage, force: Boolean = false): AppResult<W4PageSnapshot> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val html = DemoData.extraAcademicsHtml(page.cacheKey.removePrefix("ea_"))
            return AppResult.Success(snapshotFrom(html, W4Urls.route(page.route).toString()))
        }
        val key = "${page.cacheKey}_${student.studentId}"
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.EXTRA_ACADEMICS)) {
                    return AppResult.Success(snapshotFrom(cached.value, W4Urls.route(page.route).toString()))
                }
            }
        }
        return when (val res = client.get(page.route)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(snapshotFrom(res.data.body, W4Urls.route(page.route).toString()))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let {
                    return AppResult.Success(snapshotFrom(it, W4Urls.route(page.route).toString()))
                }
                res
            }
        }
    }

    private fun snapshotFrom(html: String, url: String): W4PageSnapshot {
        val inner = W4Html.contentInner(html)
        val fragment = inner ?: html
        val heading = Jsoup.parse(fragment).selectFirst("h1, h2, h3")?.text()?.trim()
        return W4PageSnapshot(heading = heading, contentFragmentHtml = fragment, url = url)
    }
}
