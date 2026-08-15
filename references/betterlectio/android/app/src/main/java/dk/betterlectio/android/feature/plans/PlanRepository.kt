package dk.betterlectio.android.feature.plans

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.R
import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import org.jsoup.Jsoup
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlanRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val client: LectioClient,
    private val session: SessionController,
    private val cache: SimpleCache,
) {
    suspend fun load(): AppResult<List<StudyPlan>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(DemoData.plans)
        return when (val res = client.get("studieplan.aspx")) {
            is AppResult.Failure -> when (val alt = client.get("DokumentOversigt.aspx?type=studieplan")) {
                is AppResult.Success -> AppResult.Success(parseList(alt.data.body))
                is AppResult.Failure -> res
            }
            is AppResult.Success -> AppResult.Success(parseList(res.data.body))
        }
    }

    suspend fun loadDetail(plan: StudyPlan): AppResult<StudyPlan> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                plan.copy(
                    detailHtml = "<p><b>${plan.title}</b></p><p>Demo for ${plan.team.ifBlank { context.getString(R.string.plan_subject_fallback) }}.</p>",
                ),
            )
        }
        // List keys may append "#index" for uniqueness; strip before network fetch.
        val href = plan.id.replace(Regex("#\\d+$"), "")
        if (!href.contains("http") && !href.contains(".aspx") && !href.contains("/")) {
            return AppResult.Success(plan.copy(detailHtml = plan.title))
        }
        val path = if (href.startsWith("http")) href else href.removePrefix("/")
        val key = "plan_${student.studentId}_${href.hashCode()}"
        cache.get(key)?.let {
            return AppResult.Success(plan.copy(detailHtml = extractBody(it)))
        }
        return when (val res = client.get(path)) {
            is AppResult.Failure -> AppResult.Success(plan)
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(plan.copy(detailHtml = extractBody(res.data.body)))
            }
        }
    }

    private fun parseList(html: String): List<StudyPlan> {
        val doc = Jsoup.parse(html)
        // Prefer unique hrefs; fall back to index-stable ids so LazyColumn keys never collide
        // when Lectio reuses the same studieplan.aspx URL for multiple rows.
        return doc.select("a[href*=studieplan], table tr a, .lp-studieplan a")
            .mapIndexed { i, a ->
                val href = a.attr("href").trim()
                val title = a.text().trim().ifBlank { context.getString(R.string.plan_fallback_title) }
                StudyPlan(
                    id = if (href.isNotBlank()) "$href#$i" else "plan-$i",
                    title = title,
                    team = "",
                )
            }
            .distinctBy { it.title }
            .ifEmpty {
                listOf(StudyPlan("empty", context.getString(R.string.plan_empty), ""))
            }
    }

    private fun extractBody(html: String): String {
        val doc = Jsoup.parse(html)
        val content = doc.selectFirst("#s_m_Content_Content, #m_Content, .ls-paper, main")
            ?: doc.body()
        return content?.html().orEmpty().ifBlank { html.take(2000) }
    }
}
