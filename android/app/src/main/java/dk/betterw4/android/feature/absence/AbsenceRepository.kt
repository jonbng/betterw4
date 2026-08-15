package dk.betterw4.android.feature.absence

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AbsenceRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun loadOverview(force: Boolean = false): AppResult<AbsenceOverview> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.absence)
        }
        val acKey = "absences_ac_${student.studentId}"
        val eaKey = "absences_ea_${student.studentId}"
        val homeKey = "absences_home_${student.studentId}"

        val acHtml = fetchHtml(W4Urls.Routes.ABSENCES, acKey, force)
        val eaHtml = fetchHtml(W4Urls.Routes.EA_ABSENCES, eaKey, force)
        if (acHtml is AppResult.Failure && eaHtml is AppResult.Failure) {
            return acHtml
        }

        val acPage = acHtml.getOrNull()?.let { W4AbsenceParser.parseList(it, AbsenceSource.ACADEMICS) }
        val eaPage = eaHtml.getOrNull()?.let { W4AbsenceParser.parseList(it, AbsenceSource.EA) }

        var academicMeter = acPage?.meter
        var eaMeter = eaPage?.meter
        if (academicMeter == null || eaMeter == null) {
            when (val home = fetchHtml(W4Urls.Routes.HOME, homeKey, force)) {
                is AppResult.Success -> {
                    val meters = W4AbsenceParser.parseHomeMeters(home.data)
                    if (academicMeter == null) academicMeter = meters.academic
                    if (eaMeter == null) eaMeter = meters.ea
                }
                is AppResult.Failure -> Unit
            }
        }

        return AppResult.Success(
            AbsenceOverview(
                teams = emptyList(),
                registrations = acPage?.registrations.orEmpty() + eaPage?.registrations.orEmpty(),
                academicMeter = academicMeter ?: W4AbsenceMeter(),
                eaMeter = eaMeter ?: W4AbsenceMeter(),
            ),
        )
    }

    suspend fun updateCause(
        @Suppress("UNUSED_PARAMETER") id: String,
        @Suppress("UNUSED_PARAMETER") cause: String,
        @Suppress("UNUSED_PARAMETER") note: String = "",
    ): AppResult<Unit> = AppResult.Success(Unit)

    private suspend fun fetchHtml(
        route: String,
        key: String,
        force: Boolean,
    ): AppResult<String> {
        if (!force) {
            cache.get(key)?.let { return AppResult.Success(it) }
        }
        return when (val res = client.get(route)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(res.data.body)
            }
            is AppResult.Failure -> cache.get(key)?.let { AppResult.Success(it) } ?: res
        }
    }
}
