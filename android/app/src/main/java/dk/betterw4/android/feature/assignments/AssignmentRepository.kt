package dk.betterw4.android.feature.assignments

import dk.betterw4.android.core.result.AppResult
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AssignmentRepository @Inject constructor() {
    suspend fun load(@Suppress("UNUSED_PARAMETER") forceRefresh: Boolean = false): AppResult<List<AssignmentItem>> =
        AppResult.Success(emptyList())
}
