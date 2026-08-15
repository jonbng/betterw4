package dk.betterlectio.android.feature.absence

import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.scrape.SmartPostback
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AbsenceRepository @Inject constructor(
    private val client: LectioClient,
    private val cache: SimpleCache,
    private val session: SessionController,
    private val demoAbsenceState: DemoAbsenceState,
) {
    suspend fun loadOverview(forceRefresh: Boolean = false): AppResult<AbsenceOverview> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoAbsenceState.overview())

        val key = "absence_${student.studentId}"
        if (!forceRefresh) {
            cache.get(key)?.let {
                val (att, written) = AbsenceParser.parseSummaryPercents(it)
                return AppResult.Success(
                    AbsenceOverview(
                        teams = AbsenceParser.parseOverview(it),
                        registrations = emptyList(),
                        attendanceAbsencePercent = att,
                        writtenAbsencePercent = written,
                    ),
                )
            }
        }
        // Flutter: subnav/fravaerelev.aspx?elevid=…
        val paths = listOf(
            "subnav/fravaerelev.aspx?elevid=${student.studentId}",
            "subnav/fravaerelev.aspx",
            "subnav/fravaereloversigt.aspx",
            "fravaer_oversigt.aspx",
        )
        var lastFailure: AppResult.Failure? = null
        for (path in paths) {
            when (val res = client.get(path)) {
                is AppResult.Failure -> lastFailure = res
                is AppResult.Success -> {
                    cache.put(key, res.data.body)
                    val teams = AbsenceParser.parseOverview(res.data.body)
                    val (att, written) = AbsenceParser.parseSummaryPercents(res.data.body)
                    val regs = loadRegistrations()
                    return AppResult.Success(
                        AbsenceOverview(
                            teams = teams,
                            registrations = (regs as? AppResult.Success)?.data.orEmpty(),
                            attendanceAbsencePercent = att,
                            writtenAbsencePercent = written,
                        ),
                    )
                }
            }
        }
        return lastFailure ?: AppResult.Failure(AppError.Unknown("Kunne ikke hente fravær"))
    }

    suspend fun loadRegistrations(): AppResult<List<AbsenceRegistration>> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoAbsenceState.registrations())
        val paths = listOf(
            "subnav/fravaerelev_fravaersaarsager.aspx?elevid=${student.studentId}",
            "subnav/fravaerelev_fravaersaarsager.aspx",
        )
        for (path in paths) {
            when (val res = client.get(path)) {
                is AppResult.Success -> return AppResult.Success(AbsenceParser.parseRegistrations(res.data.body))
                is AppResult.Failure -> continue
            }
        }
        return AppResult.Success(emptyList())
    }

    /**
     * Flutter absence update: `fravaer_aarsag.aspx?elevid=&id=&atype=aa`
     * fields: StudentReasonDD$dd, cancelStudentNote$tb
     * target: savecancelapplyBtn$svbtn
     */
    suspend fun updateCause(registrationId: String, cause: String, note: String = ""): AppResult<Unit> {
        if (session.currentStudent?.isDemo == true) {
            val ok = demoAbsenceState.updateCause(registrationId, cause, note)
            return if (ok) AppResult.Success(Unit)
            else AppResult.Failure(AppError.Unknown("Ukendt registrering: $registrationId"))
        }
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        val path =
            "fravaer_aarsag.aspx?elevid=${student.studentId}&id=$registrationId&atype=aa"
        return when (val page = client.get(path)) {
            is AppResult.Failure -> {
                // Last-resort legacy list postback
                client.postback(
                    "subnav/fravaerelev_fravaersaarsager.aspx",
                    "s\$m\$Content\$Content\$savecancelapplyBtn\$svbtn",
                    mapOf(
                        "s\$m\$Content\$Content\$StudentReasonDD\$dd" to cause,
                        "s\$m\$Content\$Content\$cancelStudentNote\$tb" to note,
                    ),
                ).let {
                    when (it) {
                        is AppResult.Success -> AppResult.Success(Unit)
                        is AppResult.Failure -> it
                    }
                }
            }
            is AppResult.Success -> {
                val html = page.data.body
                val resolved = SmartPostback.resolve(
                    html = html,
                    preferredTargets = listOf(
                        "s\$m\$Content\$Content\$savecancelapplyBtn\$svbtn",
                        "s\$m\$Content\$Content\$savebtn",
                        "m\$Content\$Content\$savecancelapplyBtn\$svbtn",
                    ),
                    extra = mapOf(
                        "s\$m\$Content\$Content\$StudentReasonDD\$dd" to cause,
                        "s\$m\$Content\$Content\$cancelStudentNote\$tb" to note,
                    ),
                    nameContainsAny = listOf("save", "gem", "apply", "svbtn"),
                )
                when (val post = client.postForm(path, resolved.fields)) {
                    is AppResult.Success -> AppResult.Success(Unit)
                    is AppResult.Failure -> post
                }
            }
        }
    }
}
