package dk.betterlectio.android.feature.teams

import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.demo.DemoData
import org.jsoup.Jsoup
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ModuleStatRepository @Inject constructor(
    private val client: LectioClient,
    private val session: SessionController,
) {
    suspend fun load(): AppResult<List<ModuleStat>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(DemoData.moduleStats)
        return when (val res = client.get("subnav/modul_oversigt.aspx")) {
            is AppResult.Failure -> when (val alt = client.get("moduler_elev.aspx")) {
                is AppResult.Success -> AppResult.Success(parse(alt.data.body))
                is AppResult.Failure -> res
            }
            is AppResult.Success -> AppResult.Success(parse(res.data.body))
        }
    }

    private fun parse(html: String): List<ModuleStat> {
        val doc = Jsoup.parse(html)
        return doc.select("table tr").drop(1).mapNotNull { row ->
            val cells = row.select("td")
            if (cells.size < 2) return@mapNotNull null
            ModuleStat(
                team = cells[0].text().trim(),
                held = cells.getOrNull(1)?.text()?.filter { it.isDigit() }?.toIntOrNull() ?: 0,
                cancelled = cells.getOrNull(2)?.text()?.filter { it.isDigit() }?.toIntOrNull() ?: 0,
                changed = cells.getOrNull(3)?.text()?.filter { it.isDigit() }?.toIntOrNull() ?: 0,
            )
        }.filter { it.team.isNotBlank() }
    }
}
