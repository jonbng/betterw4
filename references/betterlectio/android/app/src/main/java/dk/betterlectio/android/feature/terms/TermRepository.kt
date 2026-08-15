package dk.betterlectio.android.feature.terms

import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import org.jsoup.Jsoup
import javax.inject.Inject
import javax.inject.Singleton

data class SchoolTerm(val id: String, val name: String, val selected: Boolean)

@Singleton
class TermRepository @Inject constructor(
    private val client: LectioClient,
    private val session: SessionController,
) {
    suspend fun loadTerms(): AppResult<List<SchoolTerm>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                listOf(
                    SchoolTerm("2025", "2025/2026", true),
                    SchoolTerm("2024", "2024/2025", false),
                ),
            )
        }
        return when (val res = client.get("forside.aspx")) {
            is AppResult.Failure -> res
            is AppResult.Success -> {
                val doc = Jsoup.parse(res.data.body)
                val options = doc.select("select[name*=term], select[id*=Term] option")
                if (options.isEmpty()) {
                    AppResult.Success(listOf(SchoolTerm("current", "Nuværende år", true)))
                } else {
                    AppResult.Success(
                        options.map {
                            SchoolTerm(
                                id = it.attr("value"),
                                name = it.text().trim(),
                                selected = it.hasAttr("selected"),
                            )
                        },
                    )
                }
            }
        }
    }

    suspend fun selectTerm(termId: String): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) return AppResult.Success(Unit)
        return when (
            client.postback(
                "forside.aspx",
                "s\$m\$ChooseTerm\$term",
                mapOf("s\$m\$ChooseTerm\$term" to termId),
            )
        ) {
            is AppResult.Success -> AppResult.Success(Unit)
            is AppResult.Failure -> AppResult.Success(Unit) // best-effort
        }
    }
}
