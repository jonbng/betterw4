package dk.betterw4.android.feature.campus

import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
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
        CampusStatusParser.parse(html)?.let { _status.value = it }
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
                if (parsed != null) {
                    _status.value = parsed
                    AppResult.Success(parsed)
                } else {
                    val fallback = _status.value ?: CampusStatus(onCampus = true)
                    _status.value = fallback
                    AppResult.Success(fallback)
                }
            }
            is AppResult.Failure -> res
        }
    }

    suspend fun set(
        option: CampusLocationOption,
        freeText: String? = null,
    ): AppResult<CampusStatus> {
        val body = CampusStatusParser.setStatusBody(option, freeText)
            ?: return AppResult.Failure(AppError.Unknown("Enter a location for Other."))
        if (session.currentStudent?.isDemo == true) {
            val next = CampusStatus(
                onCampus = option.isOnCampus,
                location = if (option.isOnCampus) null else body["location"],
                options = _status.value?.options ?: CampusLocationOption.defaults,
                selectedOptionId = option.id,
            )
            _status.value = next
            return AppResult.Success(next)
        }
        return when (
            val res = client.postAjax(
                routeOrUrl = W4Urls.Routes.SET_STATUS,
                fields = body,
            )
        ) {
            is AppResult.Success -> {
                applyHtml(res.data.body)
                if (_status.value == null) {
                    _status.value = CampusStatus(
                        onCampus = option.isOnCampus,
                        location = body["location"],
                        selectedOptionId = option.id,
                    )
                }
                refresh()
            }
            is AppResult.Failure -> res
        }
    }
}
