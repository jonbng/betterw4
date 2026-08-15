package dk.betterw4.android.feature.terms

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.session.SessionController
import javax.inject.Inject
import javax.inject.Singleton

data class SchoolTerm(val id: String, val name: String, val selected: Boolean)

@Singleton
class TermRepository @Inject constructor(
    private val session: SessionController,
) {
    suspend fun loadTerms(): AppResult<List<SchoolTerm>> {
        if (session.currentStudent?.isDemo == true) {
            return AppResult.Success(
                listOf(
                    SchoolTerm("current", "2025/2026", true),
                    SchoolTerm("prev", "2024/2025", false),
                ),
            )
        }
        return AppResult.Success(listOf(SchoolTerm("current", "Current year", true)))
    }

    suspend fun selectTerm(@Suppress("UNUSED_PARAMETER") termId: String): AppResult<Unit> =
        AppResult.Success(Unit)
}
