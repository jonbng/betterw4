package dk.betterlectio.android.ui.screens.more

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.posthog.PostHog
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.R
import dk.betterlectio.android.core.cache.SimpleCache
import dk.betterlectio.android.core.i18n.UiText
import dk.betterlectio.android.core.i18n.toUiText
import dk.betterlectio.android.core.lectio.auth.AuthSessionInstaller
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.absence.AbsenceCauses
import dk.betterlectio.android.feature.absence.AbsenceOverview
import dk.betterlectio.android.feature.absence.AbsenceRepository
import dk.betterlectio.android.feature.feedback.FeedbackOpenRequests
import dk.betterlectio.android.core.util.LectioDateUtils
import dk.betterlectio.android.feature.directory.DirectoryEntity
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.directory.DirectoryParser
import dk.betterlectio.android.feature.directory.DirectoryPinRepository
import dk.betterlectio.android.feature.directory.DirectoryRepository
import dk.betterlectio.android.feature.directory.RoomScheduleRepository
import dk.betterlectio.android.feature.directory.StudentProfile
import dk.betterlectio.android.feature.grades.GradeAverage
import dk.betterlectio.android.feature.grades.GradeRepository
import dk.betterlectio.android.feature.grades.GradeRow
import dk.betterlectio.android.feature.grades.GradeSubjectDetail
import dk.betterlectio.android.feature.grades.GradesReport
import dk.betterlectio.android.feature.messages.MessageRecipient
import dk.betterlectio.android.feature.messages.PendingComposeRecipient
import dk.betterlectio.android.feature.plans.PlanRepository
import dk.betterlectio.android.feature.plans.StudyPlan
import dk.betterlectio.android.feature.referral.ReferralCoordinator
import dk.betterlectio.android.feature.referral.ReferralStats
import dk.betterlectio.android.feature.referral.buildReferralUrl
import dk.betterlectio.android.feature.profilepicture.ProfilePictureState
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.ScheduleWeek
import dk.betterlectio.android.feature.settings.AppLanguage
import dk.betterlectio.android.feature.settings.AppearanceMode
import dk.betterlectio.android.feature.settings.CalendarStyle
import dk.betterlectio.android.feature.settings.SettingsStore
import dk.betterlectio.android.feature.settings.SubjectInfo
import dk.betterlectio.android.feature.settings.SubjectMapper
import dk.betterlectio.android.feature.studiekort.StudentCard
import dk.betterlectio.android.feature.studiekort.StudiekortRepository
import dk.betterlectio.android.feature.supabase.SupabaseStudentProfileService
import dk.betterlectio.android.feature.supabase.SupabaseProfilePictureService
import dk.betterlectio.android.feature.teams.ModuleStat
import dk.betterlectio.android.feature.teams.ModuleStatRepository
import dk.betterlectio.android.feature.terms.SchoolTerm
import dk.betterlectio.android.feature.terms.TermRepository
import dk.betterlectio.android.feature.updates.AppUpdateProbe
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class MoreDestination {
    ROOT, GRADES, ABSENCE, DIRECTORY, ROOMS, STUDIEKORT, PLANS, MODULE_STATS, TERM, SETTINGS, REFERRAL
}

data class MoreUiState(
    val destination: MoreDestination = MoreDestination.ROOT,
    val student: Student? = null,
    val profilePhotoUrl: String? = null,
    val loading: Boolean = false,
    val gradesReport: GradesReport? = null,
    /** null = Alle (show every column; multi-stat averages). */
    val selectedGradeColumnKey: String? = null,
    val gradeDetail: GradeSubjectDetail? = null,
    val absence: AbsenceOverview? = null,
    val directory: List<DirectoryEntity> = emptyList(),
    val directoryQuery: String = "",
    val directoryKind: DirectoryEntityKind? = null,
    val directoryMembers: List<DirectoryEntity> = emptyList(),
    val directoryParent: DirectoryEntity? = null,
    /** Person selected for action sheet (large photo + actions). */
    val selectedPerson: DirectoryEntity? = null,
    /** Other person schedule (student/teacher) under directory. */
    val personEntity: DirectoryEntity? = null,
    val personSchedule: ScheduleWeek? = null,
    /** Rich Supabase profile when viewing a student (null = Lectio-only / inactive). */
    val studentProfile: StudentProfile? = null,
    val personWeekYear: Int = LectioDateUtils.isoWeekYear(),
    val personWeek: Int = LectioDateUtils.isoWeek(),
    val pinnedIds: Set<String> = emptySet(),
    val roomSchedule: ScheduleWeek? = null,
    val roomEntity: DirectoryEntity? = null,
    val roomWeekYear: Int = LectioDateUtils.isoWeekYear(),
    val roomWeek: Int = LectioDateUtils.isoWeek(),
    /** Live room occupancy list (in-use flags). */
    val roomsOccupancy: List<dk.betterlectio.android.feature.directory.RoomParser.RoomWithOccupancy> = emptyList(),
    val card: StudentCard? = null,
    val plans: List<StudyPlan> = emptyList(),
    val planDetail: StudyPlan? = null,
    val moduleStats: List<ModuleStat> = emptyList(),
    val terms: List<SchoolTerm> = emptyList(),
    /** Subject currently open in the edit sheet (canonical code). */
    val editingSubjectCode: String? = null,
    val updateMessage: String? = null,
    val message: UiText? = null,
    val referralStats: ReferralStats? = null,
    val referralStatsLoading: Boolean = false,
    val referralCopied: Boolean = false,
    val profilePictureState: ProfilePictureState? = null,
    val profilePictureLoading: Boolean = false,
    val profilePictureUploading: Boolean = false,
    val profilePictureError: UiText? = null,
)

@HiltViewModel
class MoreViewModel @Inject constructor(
    @ApplicationContext private val appContext: Context,
    private val session: SessionController,
    private val auth: AuthSessionInstaller,
    private val gradesRepo: GradeRepository,
    private val absenceRepo: AbsenceRepository,
    private val directoryRepo: DirectoryRepository,
    private val pinRepo: DirectoryPinRepository,
    private val roomScheduleRepo: RoomScheduleRepository,
    private val studentProfileService: SupabaseStudentProfileService,
    private val pendingCompose: PendingComposeRecipient,
    private val studiekortRepo: StudiekortRepository,
    private val plansRepo: PlanRepository,
    private val moduleStatRepo: ModuleStatRepository,
    private val termRepo: TermRepository,
    private val cache: SimpleCache,
    private val appUpdateProbe: AppUpdateProbe,
    val settings: SettingsStore,
    private val referralCoordinator: ReferralCoordinator,
    private val profilePictureService: SupabaseProfilePictureService,
    private val feedbackOpenRequests: FeedbackOpenRequests,
) : ViewModel() {

    private val _state = MutableStateFlow(
        MoreUiState(
            student = session.currentStudent,
            pinnedIds = pinRepo.pinnedIds(),
        ),
    )
    val state: StateFlow<MoreUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            when (val res = studiekortRepo.loadCardScraped()) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        card = res.data,
                        profilePhotoUrl = res.data.photoUrl,
                        student = res.data.student,
                    )
                }
                is AppResult.Failure -> Unit
            }
        }
        viewModelScope.launch {
            refreshReferralStats()
        }
        refreshProfilePictureState()
    }

    val appearance = settings.appearance.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.appearance.value)
    val language = settings.language.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.language.value)
    val calendarStyle = settings.calendarStyle.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.calendarStyle.value)
    val useSubjectColors = settings.useSubjectColors
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.useSubjectColors.value)
    val notifEvents = settings.notifEvents
    val notifMessages = settings.notifMessages
    val notifAssignments = settings.notifAssignments
    val disableSignature = settings.disableSignature
    val lessonMappings = settings.lessonMappings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.lessonMappings.value)
    val notificationHistory = settings.notificationHistory
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.notificationHistory.value)

    fun openFeedback() {
        feedbackOpenRequests.requestOpen()
    }

    fun navigate(dest: MoreDestination) {
        _state.update {
            it.copy(
                destination = dest,
                message = null,
                gradeDetail = null,
                directoryMembers = emptyList(),
                directoryParent = null,
                selectedPerson = null,
                personEntity = null,
                personSchedule = null,
                studentProfile = null,
                roomSchedule = null,
                roomEntity = null,
                planDetail = null,
            )
        }
        when (dest) {
            MoreDestination.GRADES -> {
                PostHog.capture(event = "grades_viewed")
                loadGrades()
            }
            MoreDestination.ABSENCE -> {
                PostHog.capture(event = "absence_viewed")
                loadAbsence()
            }
            MoreDestination.DIRECTORY -> searchDirectory()
            MoreDestination.ROOMS -> loadRoomsOccupancy()
            MoreDestination.STUDIEKORT -> {
                loadCard()
                refreshProfilePictureState()
            }
            MoreDestination.PLANS -> loadPlans()
            MoreDestination.MODULE_STATS -> loadModuleStats()
            MoreDestination.TERM -> loadTerms()
            MoreDestination.SETTINGS -> {
                session.currentStudent?.let { student ->
                    if (!student.isDemo) {
                        settings.activateScope(student.studentId, student.gymId.toString())
                        viewModelScope.launch {
                            settings.syncSubjectsFromSupabaseNow(student)
                        }
                    }
                }
            }
            MoreDestination.REFERRAL -> {
                PostHog.capture(event = "referral_screen_opened", properties = mapOf("platform" to "android"))
                refreshReferralStats()
            }
            else -> Unit
        }
    }

    fun back() {
        val s = _state.value
        when {
            s.gradeDetail != null -> _state.update { it.copy(gradeDetail = null) }
            s.planDetail != null -> _state.update { it.copy(planDetail = null) }
            s.personSchedule != null || s.personEntity != null -> _state.update {
                it.copy(
                    personSchedule = null,
                    personEntity = null,
                    studentProfile = null,
                )
            }
            s.roomSchedule != null || s.roomEntity != null -> _state.update {
                it.copy(roomSchedule = null, roomEntity = null)
            }
            s.directoryParent != null -> _state.update {
                it.copy(directoryParent = null, directoryMembers = emptyList())
            }
            else -> _state.update { it.copy(destination = MoreDestination.ROOT) }
        }
    }

    /** Jump straight to the top-level More menu (used when reselecting the More tab). */
    fun popToRoot() {
        _state.update {
            it.copy(
                destination = MoreDestination.ROOT,
                message = null,
                gradeDetail = null,
                directoryMembers = emptyList(),
                directoryParent = null,
                selectedPerson = null,
                personEntity = null,
                personSchedule = null,
                studentProfile = null,
                roomSchedule = null,
                roomEntity = null,
                planDetail = null,
            )
        }
    }

    fun logout() = auth.logout()

    fun clearCache() {
        cache.clearAll()
        _state.update { it.copy(message = UiText.Res(R.string.msg_cache_cleared)) }
    }

    private fun loadGrades() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = gradesRepo.load(true)) {
            is AppResult.Success -> {
                val report = res.data
                val defaultKey = GradeAverage.defaultColumnKey(report.columns, report.grades)
                _state.update {
                    it.copy(
                        loading = false,
                        gradesReport = report,
                        selectedGradeColumnKey = defaultKey,
                    )
                }
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun openGradeDetail(row: GradeRow) = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        val report = _state.value.gradesReport
        when (val res = gradesRepo.loadSubjectDetail(row, report)) {
            is AppResult.Success -> _state.update { it.copy(loading = false, gradeDetail = res.data) }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    /** null = Alle. */
    fun setGradeColumnKey(columnKey: String?) {
        _state.update { it.copy(selectedGradeColumnKey = columnKey) }
    }

    fun visibleGrades(): List<GradeRow> {
        val report = _state.value.gradesReport ?: return emptyList()
        return GradeAverage.filterRows(report.grades, _state.value.selectedGradeColumnKey)
    }

    fun gradesAverageDisplay(): String? {
        val report = _state.value.gradesReport ?: return null
        val key = _state.value.selectedGradeColumnKey ?: return null
        return GradeAverage.weightedAverageDisplay(report.grades, key)
    }

    fun openDirectoryKind(kind: DirectoryEntityKind) {
        _state.update {
            it.copy(
                destination = MoreDestination.DIRECTORY,
                directoryKind = kind,
                directoryQuery = "",
                directoryMembers = emptyList(),
                directoryParent = null,
                message = null,
            )
        }
        searchDirectory()
    }

    private fun loadAbsence() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = absenceRepo.loadOverview(true)) {
            is AppResult.Success -> _state.update { it.copy(loading = false, absence = res.data) }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    fun updateAbsenceCause(id: String, cause: String, note: String = "") = viewModelScope.launch {
        when (val res = absenceRepo.updateCause(id, cause, note)) {
            is AppResult.Success -> {
                PostHog.capture(event = "absence_cause_updated")
                settings.appendNotificationHistory(
                    appContext.getString(R.string.msg_absence_cause_history, cause),
                )
                _state.update { it.copy(message = UiText.Res(R.string.msg_absence_cause_updated, cause)) }
                loadAbsence()
            }
            is AppResult.Failure -> _state.update { it.copy(message = res.error.toUiText()) }
        }
    }

    fun onDirectoryQuery(q: String) {
        _state.update { it.copy(directoryQuery = q) }
        searchDirectory()
    }

    fun onDirectoryKind(kind: DirectoryEntityKind?) {
        _state.update { it.copy(directoryKind = kind) }
        searchDirectory()
    }

    private fun searchDirectory() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = directoryRepo.search(_state.value.directoryQuery, _state.value.directoryKind)) {
            is AppResult.Success -> {
                val classLabel = session.currentStudent?.classLabel
                val ranked = dk.betterlectio.android.feature.directory.DirectorySearch.rank(
                    items = res.data,
                    query = _state.value.directoryQuery,
                    pinnedIds = pinRepo.pinnedIds(),
                    classmateClassLabel = classLabel,
                )
                _state.update {
                    it.copy(
                        loading = false,
                        directory = ranked,
                        pinnedIds = pinRepo.pinnedIds(),
                    )
                }
            }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    fun togglePin(entity: DirectoryEntity) {
        pinRepo.toggle(entity.id)
        val classLabel = session.currentStudent?.classLabel
        _state.update {
            it.copy(
                pinnedIds = pinRepo.pinnedIds(),
                directory = dk.betterlectio.android.feature.directory.DirectorySearch.rank(
                    items = it.directory,
                    query = it.directoryQuery,
                    pinnedIds = pinRepo.pinnedIds(),
                    classmateClassLabel = classLabel,
                ),
            )
        }
    }

    fun isPinned(id: String): Boolean = pinRepo.isPinned(id)

    fun openPersonSheet(entity: DirectoryEntity) {
        if (entity.kind != DirectoryEntityKind.STUDENT && entity.kind != DirectoryEntityKind.TEACHER) {
            return
        }
        _state.update { it.copy(selectedPerson = entity) }
    }

    fun dismissPersonSheet() {
        _state.update { it.copy(selectedPerson = null) }
    }

    /**
     * Open the dedicated student profile page (rich hero + week schedule).
     * Supabase profile failures fall back to Lectio identity without blocking schedule.
     */
    fun openStudentProfile(entity: DirectoryEntity) = viewModelScope.launch {
        if (entity.kind != DirectoryEntityKind.STUDENT) {
            openPersonSchedule(entity)
            return@launch
        }
        val year = LectioDateUtils.isoWeekYear()
        val week = LectioDateUtils.isoWeek()
        _state.update {
            it.copy(
                selectedPerson = null,
                loading = true,
                personEntity = entity,
                personSchedule = null,
                studentProfile = null,
                personWeekYear = year,
                personWeek = week,
            )
        }
        val numericId = DirectoryParser.numericId(entity.id)
        val profileDeferred = async { studentProfileService.getStudent(numericId) }
        val scheduleDeferred = async { roomScheduleRepo.loadPersonWeek(entity, year, week) }
        val profile = profileDeferred.await()
        when (val res = scheduleDeferred.await()) {
            is AppResult.Success -> _state.update {
                it.copy(
                    loading = false,
                    studentProfile = profile,
                    personSchedule = res.data,
                )
            }
            is AppResult.Failure -> _state.update {
                it.copy(
                    loading = false,
                    studentProfile = profile,
                    message = res.error.toUiText(),
                )
            }
        }
    }

    fun openPersonSchedule(entity: DirectoryEntity) = viewModelScope.launch {
        val year = LectioDateUtils.isoWeekYear()
        val week = LectioDateUtils.isoWeek()
        _state.update {
            it.copy(
                selectedPerson = null,
                loading = true,
                personEntity = entity,
                personSchedule = null,
                studentProfile = null,
                personWeekYear = year,
                personWeek = week,
            )
        }
        when (val res = roomScheduleRepo.loadPersonWeek(entity, year, week)) {
            is AppResult.Success -> _state.update {
                it.copy(loading = false, personSchedule = res.data)
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun shiftPersonWeek(delta: Int) {
        val currentStart = LectioDateUtils.weekStart(
            _state.value.personWeekYear,
            _state.value.personWeek,
        )
        loadPersonWeekForDate(currentStart.plusWeeks(delta.toLong()))
    }

    fun goToPersonToday() {
        val today = java.time.LocalDate.now()
        val year = LectioDateUtils.isoWeekYear(today)
        val week = LectioDateUtils.isoWeek(today)
        if (year == _state.value.personWeekYear &&
            week == _state.value.personWeek &&
            _state.value.personSchedule != null
        ) {
            // Already on the right week; UI selects today locally.
            return
        }
        loadPersonWeekForDate(today)
    }

    fun loadPersonWeekForDate(date: java.time.LocalDate) = viewModelScope.launch {
        val entity = _state.value.personEntity ?: return@launch
        val year = LectioDateUtils.isoWeekYear(date)
        val week = LectioDateUtils.isoWeek(date)
        if (year == _state.value.personWeekYear &&
            week == _state.value.personWeek &&
            _state.value.personSchedule != null
        ) {
            return@launch
        }
        _state.update { it.copy(loading = true) }
        when (val res = roomScheduleRepo.loadPersonWeek(entity, year, week)) {
            is AppResult.Success -> _state.update {
                it.copy(
                    loading = false,
                    personWeekYear = year,
                    personWeek = week,
                    personSchedule = res.data,
                )
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun displayTitleForEvent(event: ScheduleEvent): String {
        val key = event.team.ifBlank { event.title }
        return settings.displayNameForSubject(key, fallback = event.title.ifBlank { key })
    }

    fun accentArgbForEvent(event: ScheduleEvent): Long = settings.accentArgbFor(event)

    /**
     * Queue compose recipient and dismiss sheet. Caller navigates to the Messages tab.
     */
    fun composeToPerson(entity: DirectoryEntity) {
        pendingCompose.offer(
            MessageRecipient(
                id = entity.id,
                name = entity.name,
                kind = entity.kind.name,
            ),
        )
        _state.update { it.copy(selectedPerson = null) }
    }

    fun openPersonClass(entity: DirectoryEntity) = viewModelScope.launch {
        val label = entity.subtitle?.trim().orEmpty()
        if (label.isEmpty()) {
            _state.update { it.copy(message = UiText.Res(R.string.directory_class_not_found)) }
            return@launch
        }
        when (val res = directoryRepo.search(label, DirectoryEntityKind.CLASS)) {
            is AppResult.Failure -> _state.update {
                it.copy(message = res.error.toUiText())
            }
            is AppResult.Success -> {
                val match = res.data.firstOrNull {
                    it.name.equals(label, ignoreCase = true)
                } ?: res.data.firstOrNull {
                    it.name.contains(label, ignoreCase = true) ||
                        label.contains(it.name, ignoreCase = true)
                }
                if (match == null) {
                    // Fallback: hold with same label (member lists often use hold names).
                    when (val holdRes = directoryRepo.search(label, DirectoryEntityKind.HOLD)) {
                        is AppResult.Failure -> _state.update {
                            it.copy(message = UiText.Res(R.string.directory_class_not_found))
                        }
                        is AppResult.Success -> {
                            val hold = holdRes.data.firstOrNull {
                                it.name.equals(label, ignoreCase = true)
                            } ?: holdRes.data.firstOrNull {
                                it.name.contains(label, ignoreCase = true)
                            }
                            if (hold == null) {
                                _state.update {
                                    it.copy(message = UiText.Res(R.string.directory_class_not_found))
                                }
                            } else {
                                _state.update { it.copy(selectedPerson = null) }
                                openDirectoryMembers(hold)
                            }
                        }
                    }
                } else {
                    _state.update { it.copy(selectedPerson = null) }
                    openDirectoryMembers(match)
                }
            }
        }
    }

    fun openDirectoryMembers(entity: DirectoryEntity) = viewModelScope.launch {
        _state.update {
            it.copy(
                loading = true,
                directoryParent = entity,
                selectedPerson = null,
                personEntity = null,
                personSchedule = null,
                studentProfile = null,
            )
        }
        when (val res = directoryRepo.loadMembers(entity)) {
            is AppResult.Success -> _state.update {
                it.copy(loading = false, directoryMembers = res.data)
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun openRoomSchedule(entity: DirectoryEntity) = viewModelScope.launch {
        val year = LectioDateUtils.isoWeekYear()
        val week = LectioDateUtils.isoWeek()
        _state.update {
            it.copy(
                loading = true,
                roomEntity = entity,
                roomSchedule = null,
                roomWeekYear = year,
                roomWeek = week,
            )
        }
        when (val res = roomScheduleRepo.loadRoomWeek(entity, year, week)) {
            is AppResult.Success -> _state.update {
                it.copy(loading = false, roomSchedule = res.data)
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun shiftRoomWeek(delta: Int) {
        val currentStart = LectioDateUtils.weekStart(
            _state.value.roomWeekYear,
            _state.value.roomWeek,
        )
        loadRoomWeekForDate(currentStart.plusWeeks(delta.toLong()))
    }

    fun goToRoomToday() {
        val today = java.time.LocalDate.now()
        val year = LectioDateUtils.isoWeekYear(today)
        val week = LectioDateUtils.isoWeek(today)
        if (year == _state.value.roomWeekYear &&
            week == _state.value.roomWeek &&
            _state.value.roomSchedule != null
        ) {
            return
        }
        loadRoomWeekForDate(today)
    }

    fun loadRoomWeekForDate(date: java.time.LocalDate) = viewModelScope.launch {
        val entity = _state.value.roomEntity ?: return@launch
        val year = LectioDateUtils.isoWeekYear(date)
        val week = LectioDateUtils.isoWeek(date)
        if (year == _state.value.roomWeekYear &&
            week == _state.value.roomWeek &&
            _state.value.roomSchedule != null
        ) {
            return@launch
        }
        _state.update { it.copy(loading = true) }
        when (val res = roomScheduleRepo.loadRoomWeek(entity, year, week)) {
            is AppResult.Success -> _state.update {
                it.copy(
                    loading = false,
                    roomWeekYear = year,
                    roomWeek = week,
                    roomSchedule = res.data,
                )
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun openRoomFromOccupancy(room: dk.betterlectio.android.feature.directory.RoomParser.RoomWithOccupancy) {
        openRoomSchedule(
            DirectoryEntity(
                id = room.id,
                name = "${room.shortName} · ${room.name}",
                kind = DirectoryEntityKind.ROOM,
                subtitle = appContext.getString(
                    if (room.inUse) R.string.room_in_use else R.string.room_free,
                ),
            ),
        )
    }

    private fun loadRoomsOccupancy() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = roomScheduleRepo.listRoomsWithOccupancy()) {
            is AppResult.Success -> _state.update {
                it.copy(loading = false, roomsOccupancy = res.data)
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    private fun loadCard() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = studiekortRepo.loadCardScraped()) {
            is AppResult.Success -> _state.update {
                val preferredPhoto = it.profilePictureState?.currentUrl ?: res.data.photoUrl
                it.copy(
                    loading = false,
                    card = res.data.copy(photoUrl = preferredPhoto),
                    profilePhotoUrl = preferredPhoto,
                    student = res.data.student,
                )
            }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    private fun loadPlans() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = plansRepo.load()) {
            is AppResult.Success -> _state.update { it.copy(loading = false, plans = res.data) }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    fun openPlanDetail(plan: StudyPlan) = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = plansRepo.loadDetail(plan)) {
            is AppResult.Success -> _state.update { it.copy(loading = false, planDetail = res.data) }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    private fun loadModuleStats() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = moduleStatRepo.load()) {
            is AppResult.Success -> _state.update { it.copy(loading = false, moduleStats = res.data) }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    private fun loadTerms() = viewModelScope.launch {
        when (val res = termRepo.loadTerms()) {
            is AppResult.Success -> _state.update { it.copy(terms = res.data) }
            is AppResult.Failure -> _state.update { it.copy(message = res.error.toUiText()) }
        }
    }

    fun selectTerm(id: String) = viewModelScope.launch {
        termRepo.selectTerm(id)
        loadTerms()
    }

    fun setAppearance(mode: AppearanceMode) = settings.setAppearance(mode)
    fun setLanguage(language: AppLanguage) = settings.setLanguage(language)
    fun setCalendarStyle(style: CalendarStyle) = settings.setCalendarStyle(style)
    fun setUseSubjectColors(v: Boolean) = settings.setUseSubjectColors(v)
    fun setNotifEvents(v: Boolean) = settings.setNotifEvents(v)
    fun setNotifMessages(v: Boolean) = settings.setNotifMessages(v)
    fun setNotifAssignments(v: Boolean) = settings.setNotifAssignments(v)
    fun setDisableSignature(v: Boolean) = settings.setDisableSignature(v)

    fun dismissExtensionInvite() = settings.dismissExtensionInvite()

    fun curatedHues(): List<Int> = SubjectMapper.CURATED_HUES

    fun availableSubjects(): List<SubjectInfo> = settings.availableSubjects()

    fun colorForSubject(subject: String): Long = settings.colorForSubject(subject)

    fun displayNameForSubject(subject: String): String =
        settings.displayNameForSubject(subject, subject)

    fun defaultNameFor(subject: String): String = settings.defaultNameFor(subject)

    fun colorHueForSubject(subject: String): Int = settings.colorHueForSubject(subject)

    fun hasSubjectOverride(subject: String): Boolean = settings.hasAnyOverride(subject)

    fun openSubjectEditor(code: String) {
        _state.update { it.copy(editingSubjectCode = code) }
    }

    fun dismissSubjectEditor() {
        _state.update { it.copy(editingSubjectCode = null) }
    }

    fun saveSubjectCustomization(code: String, displayName: String?, colorHue: Int?) {
        settings.saveCustomization(code, displayName = displayName, colorHue = colorHue)
        _state.update {
            it.copy(
                editingSubjectCode = null,
                message = UiText.Res(R.string.msg_subject_name_saved),
            )
        }
    }

    fun resetSubject(code: String) {
        settings.resetMapping(code)
        _state.update {
            it.copy(
                editingSubjectCode = null,
                message = UiText.Res(R.string.msg_subject_reset),
            )
        }
    }

    fun resetAllSubjects() {
        settings.resetAllLessonMappings()
        _state.update { it.copy(message = UiText.Res(R.string.msg_subjects_reset_all)) }
    }

    fun clearNotificationHistory() {
        settings.clearNotificationHistory()
        _state.update { it.copy(message = UiText.Res(R.string.msg_notif_history_cleared)) }
    }

    fun checkForUpdates() {
        val result = appUpdateProbe.probe()
        _state.update {
            it.copy(
                updateMessage = result.message,
                message = UiText.Raw(result.message),
            )
        }
    }

    /** Full Play IAU flow when an Activity is available. */
    fun checkForUpdatesWithActivity(activity: android.app.Activity) {
        appUpdateProbe.checkAndStart(activity) { result ->
            _state.update {
                it.copy(
                    updateMessage = result.message,
                    message = UiText.Raw(result.message),
                )
            }
        }
    }

    fun appVersion(): String = appUpdateProbe.appVersionName()

    fun pullSubjectSync() = viewModelScope.launch {
        val student = session.currentStudent ?: return@launch
        if (student.isDemo) {
            _state.update { it.copy(message = UiText.Res(R.string.msg_supabase_not_configured)) }
            return@launch
        }
        val count = settings.syncSubjectsFromSupabaseNow(student)
        if (count == 0) {
            _state.update { it.copy(message = UiText.Res(R.string.msg_no_remote_subject_mapping)) }
        } else {
            _state.update { it.copy(message = UiText.Res(R.string.msg_subjects_synced, count)) }
        }
    }

    val privacyPolicyUrl: String get() = SettingsStore.PRIVACY_POLICY_URL

    val absenceCauses get() = AbsenceCauses.all

    fun referralShareUrl(): String? {
        val id = session.currentStudent?.studentId ?: return null
        if (session.currentStudent?.isDemo == true) return null
        return buildReferralUrl(id)
    }

    fun refreshReferralStats() {
        val student = session.currentStudent ?: return
        if (student.isDemo) return
        viewModelScope.launch {
            _state.update { it.copy(referralStatsLoading = true) }
            val stats = referralCoordinator.refreshStats(student.studentId)
            _state.update {
                it.copy(
                    referralStats = stats,
                    referralStatsLoading = false,
                )
            }
        }
    }

    fun refreshProfilePictureState() {
        val student = session.currentStudent ?: return
        if (student.isDemo) return
        viewModelScope.launch {
            _state.update { it.copy(profilePictureLoading = true, profilePictureError = null) }
            val pictureState = profilePictureService.getState(student.studentId)
            _state.update { current ->
                val preferred = pictureState?.currentUrl
                current.copy(
                    profilePictureState = pictureState ?: current.profilePictureState,
                    profilePictureLoading = false,
                    profilePhotoUrl = preferred ?: current.profilePhotoUrl,
                    card = if (preferred != null) current.card?.copy(photoUrl = preferred) else current.card,
                    profilePictureError = if (pictureState == null) {
                        UiText.Res(R.string.profile_picture_load_failed)
                    } else null,
                )
            }
        }
    }

    fun submitProfilePicture(bytes: ByteArray, mimeType: String) {
        val student = session.currentStudent ?: return
        val schoolId = student.gymId
        if (bytes.isEmpty() || bytes.size > 5 * 1024 * 1024 ||
            mimeType !in setOf("image/jpeg", "image/png", "image/webp")
        ) {
            _state.update { it.copy(profilePictureError = UiText.Res(R.string.profile_picture_invalid_file)) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(profilePictureUploading = true, profilePictureError = null) }
            val result = profilePictureService.submit(
                studentId = student.studentId,
                schoolId = schoolId,
                bytes = bytes,
                mimeType = mimeType,
            )
            if (result.ok) {
                _state.update { it.copy(profilePictureUploading = false) }
                refreshProfilePictureState()
            } else {
                val message = when (result.code) {
                    "not_unlocked" -> R.string.profile_picture_not_unlocked
                    "pending_exists" -> R.string.profile_picture_pending_exists
                    "cooldown" -> R.string.profile_picture_cooldown_active
                    "invalid_file" -> R.string.profile_picture_invalid_file
                    else -> R.string.profile_picture_upload_failed
                }
                _state.update {
                    it.copy(
                        profilePictureUploading = false,
                        profilePictureError = UiText.Res(message),
                    )
                }
            }
        }
    }

    fun onReferralShared(method: String) {
        PostHog.capture(
            event = "referral share",
            properties = mapOf(
                "method" to method,
                "platform" to "android",
            ),
        )
        session.currentStudent?.let { referralCoordinator.dismissNudge(it.studentId) }
    }

    fun markReferralCopied() {
        _state.update { it.copy(referralCopied = true) }
        onReferralShared("copy")
        viewModelScope.launch {
            kotlinx.coroutines.delay(2000)
            _state.update { it.copy(referralCopied = false) }
        }
    }
}
