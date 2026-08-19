package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HouseRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun loadIndex(force: Boolean = false): AppResult<List<House>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(DemoData.houses.map { it.copy(loaded = false) })

        val key = indexKey(student.studentId)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.PEOPLE)) {
                    return AppResult.Success(W4HouseParser.parseIndex(cached.value))
                }
            }
        }
        return when (
            val res = client.get(
                W4Urls.Routes.STUDENTS_BY_HOUSE,
                priority = FetchPriority.Important,
            )
        ) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4HouseParser.parseIndex(res.data.body))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(W4HouseParser.parseIndex(it)) }
                res
            }
        }
    }

    suspend fun loadHouse(
        houseId: String,
        force: Boolean = false,
        priority: FetchPriority = FetchPriority.Important,
    ): AppResult<House> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            val house = DemoData.houses.firstOrNull { it.id == houseId }
                ?: House(id = houseId, name = W4HouseParser.displayNameForId(houseId), loaded = true)
            return AppResult.Success(house.copy(loaded = true))
        }

        val key = houseKey(student.studentId, houseId)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.PEOPLE)) {
                    return AppResult.Success(W4HouseParser.parseHouse(cached.value, houseId))
                }
            }
        }
        return when (
            val res = client.get(
                W4Urls.Routes.STUDENTS_BY_HOUSE_INDEX,
                query = mapOf("house_id" to houseId),
                priority = priority,
            )
        ) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4HouseParser.parseHouse(res.data.body, houseId))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let {
                    return AppResult.Success(W4HouseParser.parseHouse(it, houseId))
                }
                res
            }
        }
    }

    /**
     * Walk every boarding-house page until [uwcId] is found.
     * Pages are cache-first, so a second lookup after More ▸ Houses is free.
     */
    suspend fun findPlacement(uwcId: String): HousePlacement? {
        val id = uwcId.trim().lowercase()
        if (id.isEmpty()) return null
        val index = when (val res = loadIndex()) {
            is AppResult.Success -> res.data
            is AppResult.Failure -> return null
        }
        index.forEachIndexed { offset, stub ->
            val priority = if (offset == 0) FetchPriority.Important else FetchPriority.Opportunistic
            val house = when (val res = loadHouse(stub.id, priority = priority)) {
                is AppResult.Success -> res.data
                is AppResult.Failure -> return@forEachIndexed
            }
            house.placementOf(id)?.let { return it }
        }
        return null
    }

    private fun indexKey(studentId: String) = "houses_index_$studentId"

    private fun houseKey(studentId: String, houseId: String) = "houses_${houseId}_$studentId"
}
