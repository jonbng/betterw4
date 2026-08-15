package dk.betterw4.android.feature.campus

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.w4.setCampusStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CampusStatusRepository @Inject constructor(
    private val client: W4Client,
    private val session: SessionController,
) {
    private val _status = MutableStateFlow<CampusStatus?>(null)
    val status: StateFlow<CampusStatus?> = _status.asStateFlow()

    fun applyHtml(html: String) {
        _status.value = CampusStatusParser.parse(html)
    }

    suspend fun refresh(): AppResult<CampusStatus> {
        if (session.currentStudent?.isDemo == true) {
            val demo = CampusStatus(onCampus = true)
            _status.value = demo
            return AppResult.Success(demo)
        }
        return when (val res = client.get(W4Urls.Routes.HOME)) {
            is AppResult.Success -> {
                val parsed = CampusStatusParser.parse(res.data.body)
                _status.value = parsed
                AppResult.Success(parsed)
            }
            is AppResult.Failure -> res
        }
    }

    suspend fun set(onCampus: Boolean, location: String?): AppResult<CampusStatus> {
        if (session.currentStudent?.isDemo == true) {
            val next = CampusStatus(
                onCampus = onCampus,
                location = if (onCampus) null else location,
                options = _status.value?.options ?: CampusStatus.defaultOptions,
            )
            _status.value = next
            return AppResult.Success(next)
        }
        val loc = when {
            onCampus -> null
            location.equals("On campus", ignoreCase = true) -> null
            location.equals("Other", ignoreCase = true) -> location
            else -> location
        }
        val actuallyOnCampus = onCampus || location.equals("On campus", ignoreCase = true)
        return when (
            val res = client.setCampusStatus(
                onCampus = actuallyOnCampus,
                location = if (actuallyOnCampus) null else loc,
            )
        ) {
            is AppResult.Success -> {
                applyHtml(res.data.body)
                if (_status.value == null) {
                    _status.value = CampusStatus(
                        onCampus = actuallyOnCampus,
                        location = loc,
                    )
                }
                refresh()
            }
            is AppResult.Failure -> res
        }
    }
}
