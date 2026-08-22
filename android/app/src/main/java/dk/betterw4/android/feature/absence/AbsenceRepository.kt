package dk.betterw4.android.feature.absence

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.schedule.ScheduleWeek
import javax.inject.Inject
import javax.inject.Singleton

internal fun absenceRegisterFields(
    dateRaw: String,
    slotValues: List<String>,
    reason: String,
    wholeDay: Boolean,
): List<Pair<String, String>> = buildList {
    add("StudentAbsenceForm[absence_date]" to dateRaw)
    add("StudentAbsenceForm[absences]" to "")
    add("StudentAbsenceForm[reason]" to reason.take(60))
    if (wholeDay) add("StudentAbsenceForm_absences_all" to "1")
    slotValues.forEach { add("StudentAbsenceForm[absences][]" to it) }
    add("yt0" to "Register absences")
}

@Singleton
class AbsenceRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun loadOverview(
        force: Boolean = false,
        year: Int = IsoDateUtils.isoWeekYear(),
        week: Int = IsoDateUtils.isoWeek(),
    ): AppResult<AbsenceOverview> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(DemoData.absence)
        }
        val uwcId = student.studentId
        val homeKey = "absences_home_$uwcId"
        val acListKey = "absences_list_ac_$uwcId"
        val eaListKey = "absences_list_ea_$uwcId"
        val acWeekKey = "absences_week_ac_${uwcId}_${year}_$week"
        val eaWeekKey = "absences_week_ea_${uwcId}_${year}_$week"
        val weekQuery = mapOf("year" to year.toString(), "week" to week.toString(), "uwc_id" to uwcId)
        val listQuery = mapOf("uwc_id" to uwcId)

        val home = fetchHtml(W4Urls.Routes.HOME, homeKey, force)
        val meters = home.getOrNull()?.let { W4AbsenceParser.parseHomeMeters(it) }

        val acListHtml = fetchHtml(W4Urls.Routes.ABSENCES_LIST, acListKey, force, listQuery)
        val eaListHtml = fetchHtml(W4Urls.Routes.EA_ABSENCES_LIST, eaListKey, force, listQuery)
        val acWeekHtml = fetchHtml(W4Urls.Routes.ABSENCES_INDEX, acWeekKey, force, weekQuery)
        val eaWeekHtml = fetchHtml(W4Urls.Routes.EA_ABSENCES_INDEX, eaWeekKey, force, weekQuery)

        if (home is AppResult.Failure &&
            acListHtml is AppResult.Failure &&
            eaListHtml is AppResult.Failure &&
            acWeekHtml is AppResult.Failure &&
            eaWeekHtml is AppResult.Failure
        ) {
            return home
        }

        val acPage = acListHtml.getOrNull()?.let { W4AbsenceParser.parseList(it, AbsenceSource.ACADEMICS) }
        val eaPage = eaListHtml.getOrNull()?.let { W4AbsenceParser.parseList(it, AbsenceSource.EA) }
        val acWeek = acWeekHtml.getOrNull()?.let {
            W4AbsenceParser.parseWeek(it, AbsenceSource.ACADEMICS, year, week)
        }
        val eaWeek = eaWeekHtml.getOrNull()?.let {
            W4AbsenceParser.parseWeek(it, AbsenceSource.EA, year, week)
        }

        return AppResult.Success(
            AbsenceOverview(
                teams = emptyList(),
                registrations = acPage?.registrations.orEmpty() + eaPage?.registrations.orEmpty(),
                academicMeter = meters?.academic ?: acPage?.meter ?: W4AbsenceMeter(),
                eaMeter = meters?.ea ?: eaPage?.meter ?: W4AbsenceMeter(),
                academicWeek = acWeek,
                eaWeek = eaWeek,
            ),
        )
    }

    suspend fun loadWeek(
        source: AbsenceSource,
        year: Int,
        week: Int,
        force: Boolean = false,
    ): AppResult<ScheduleWeek> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Failure(AppError.Unknown("Not available in demo"))
        }
        val route = if (source == AbsenceSource.EA) {
            W4Urls.Routes.EA_ABSENCES_INDEX
        } else {
            W4Urls.Routes.ABSENCES_INDEX
        }
        val key = "absences_week_${source.id}_${student.studentId}_${year}_$week"
        val query = mapOf(
            "year" to year.toString(),
            "week" to week.toString(),
            "uwc_id" to student.studentId,
        )
        return when (val html = fetchHtml(route, key, force, query)) {
            is AppResult.Success -> AppResult.Success(
                W4AbsenceParser.parseWeek(html.data, source, year, week),
            )
            is AppResult.Failure -> html
        }
    }

    suspend fun loadRegisterForm(dateRaw: String? = null, force: Boolean = true): AppResult<AbsenceRegisterForm> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Failure(AppError.Unknown("Not available in demo"))
        }
        val query = dateRaw?.takeIf { it.isNotBlank() }?.let { mapOf("date" to it) } ?: emptyMap()
        val key = "absences_register_${student.studentId}_${dateRaw.orEmpty()}"
        return when (val html = fetchHtml(W4Urls.Routes.ABSENCES_REGISTER, key, force, query)) {
            is AppResult.Success -> {
                val form = W4AbsenceParser.parseRegisterForm(html.data)
                if (form.dateRaw.isBlank() && form.emptyDayMessage == null) {
                    AppResult.Failure(AppError.Unknown("W4 did not return an absence form"))
                } else {
                    AppResult.Success(form)
                }
            }
            is AppResult.Failure -> html
        }
    }

    suspend fun submitRegisterForm(
        dateRaw: String,
        slotValues: List<String>,
        reason: String,
        wholeDay: Boolean,
    ): AppResult<Unit> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Failure(AppError.Unknown("Not available in demo"))
        val body = absenceRegisterFields(dateRaw, slotValues, reason, wholeDay)
        return when (
            val res = client.postForm(
                routeOrUrl = W4Urls.Routes.ABSENCES_REGISTER,
                fields = body,
                query = mapOf("date" to dateRaw),
            )
        ) {
            is AppResult.Success -> W4AbsenceParser.parseSubmissionError(res.data.body)?.let {
                AppResult.Failure(AppError.Unknown(it))
            } ?: AppResult.Success(Unit)
            is AppResult.Failure -> res
        }
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
        query: Map<String, String> = emptyMap(),
    ): AppResult<String> {
        if (!force) {
            cache.get(key)?.let { return AppResult.Success(it) }
        }
        return when (val res = client.get(route, query = query)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(res.data.body)
            }
            is AppResult.Failure -> cache.get(key)?.let { AppResult.Success(it) } ?: res
        }
    }
}
