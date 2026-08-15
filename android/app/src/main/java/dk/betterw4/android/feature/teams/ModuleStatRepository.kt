package dk.betterw4.android.feature.teams

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ModuleStatRepository @Inject constructor(
    private val session: SessionController,
) {
    suspend fun load(): AppResult<List<ModuleStat>> {
        if (session.currentStudent?.isDemo == true) return AppResult.Success(DemoData.moduleStats)
        return AppResult.Success(emptyList())
    }
}
