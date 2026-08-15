package dk.betterw4.android.feature.plans

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlanRepository @Inject constructor(
    private val session: SessionController,
) {
    suspend fun load(): AppResult<List<StudyPlan>> {
        if (session.currentStudent?.isDemo == true) return AppResult.Success(DemoData.plans)
        return AppResult.Success(emptyList())
    }

    suspend fun loadDetail(plan: StudyPlan): AppResult<StudyPlan> = AppResult.Success(plan)
}
