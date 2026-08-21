package dk.betterw4.android.ui.screens.more

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.R
import dk.betterw4.android.core.FeatureFlags
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.i18n.UiText
import dk.betterw4.android.core.i18n.toUiText
import dk.betterw4.android.core.w4.auth.AuthSessionInstaller
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.model.Student
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.feature.absence.AbsenceCauses
import dk.betterw4.android.feature.absence.AbsenceOverview
import dk.betterw4.android.feature.absence.AbsenceRepository
import dk.betterw4.android.feature.classes.MyClass
import dk.betterw4.android.feature.classes.MyClassRepository
import dk.betterw4.android.feature.teachers.MyTeacher
import dk.betterw4.android.feature.teachers.MyTeacherRepository
import dk.betterw4.android.feature.schedule.ClassNextLesson
import dk.betterw4.android.feature.schedule.ClassNextLessons
import dk.betterw4.android.feature.schedule.PersonClass
import dk.betterw4.android.feature.schedule.ScheduleRepository
import dk.betterw4.android.feature.classes.W4ClassParser
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.directory.DirectoryPinRepository
import dk.betterw4.android.feature.directory.DirectoryRepository
import dk.betterw4.android.feature.directory.House
import dk.betterw4.android.feature.directory.HousePlacement
import dk.betterw4.android.feature.directory.HouseRepository
import dk.betterw4.android.feature.directory.RoomScheduleRepository
import dk.betterw4.android.feature.directory.StudentProfile
import dk.betterw4.android.feature.directory.placementOf
import dk.betterw4.android.feature.documents.W4DocumentKind
import dk.betterw4.android.feature.documents.W4DocumentNode
import dk.betterw4.android.feature.documents.W4DocumentsRepository
import dk.betterw4.android.feature.grades.GradeAverage
import dk.betterw4.android.feature.grades.GradeRepository
import dk.betterw4.android.feature.grades.GradeRow
import dk.betterw4.android.feature.grades.GradeSubjectDetail
import dk.betterw4.android.feature.grades.GradesReport
import dk.betterw4.android.feature.messages.MessageRecipient
import dk.betterw4.android.feature.messages.PendingComposeRecipient
import dk.betterw4.android.feature.plans.PlanRepository
import dk.betterw4.android.feature.plans.StudyPlan
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleWeek
import dk.betterw4.android.feature.settings.AppLanguage
import dk.betterw4.android.feature.settings.AppearanceMode
import dk.betterw4.android.feature.settings.CalendarStyle
import dk.betterw4.android.feature.settings.SettingsStore
import dk.betterw4.android.feature.settings.SubjectInfo
import dk.betterw4.android.feature.settings.SubjectMapper
import dk.betterw4.android.feature.studiekort.StudentCard
import dk.betterw4.android.feature.studiekort.StudiekortRepository
import dk.betterw4.android.feature.teams.ModuleStat
import dk.betterw4.android.feature.teams.ModuleStatRepository
import dk.betterw4.android.feature.terms.SchoolTerm
import dk.betterw4.android.feature.terms.TermRepository
import dk.betterw4.android.feature.trips.W4TripsRepository
import dk.betterw4.android.feature.extraacademics.ExtraAcademicsPage
import dk.betterw4.android.feature.updates.AppUpdateProbe
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class MoreDestination {
    ROOT, HOME, NOTIFICATIONS, GRADES, ASSESSMENTS, ABSENCE, EXTRA_ACADEMICS, EA_PAGE,
    DIRECTORY, MAIL, ROOMS, HOUSES, STUDIEKORT, PLANS, MODULE_STATS, TERM, SETTINGS, SETTINGS_PRIVACY,
    DOCUMENTS, TRIPS, ON_DUTY, BIRTHDAYS, MY_CLASSES, MY_TEACHERS,
}

data class DocumentNav(
    val folderId: String? = null,
    val pageId: String? = null,
)

data class RoomTarget(
    val id: String,
    val name: String,
    val subtitle: String? = null,
)

enum class PersonProfileTab { SCHEDULE, ABOUT }

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
    val directoryKind: DirectoryEntityKind = DirectoryEntityKind.STUDENT,
    /** `null` = every year, `"1"` / `"2"` = that IB year. Ignored for teachers. */
    val directoryYear: String? = null,
    /** Person selected for action sheet (large photo + actions). */
    val selectedPerson: DirectoryEntity? = null,
    /** Other person schedule (student/teacher) under directory. */
    val personEntity: DirectoryEntity? = null,
    val personSchedule: ScheduleWeek? = null,
    /** Extra directory profile when viewing a student (null = Lectio-only). */
    val studentProfile: StudentProfile? = null,
    val personTab: PersonProfileTab = PersonProfileTab.SCHEDULE,
    val personOpenedHouseId: String? = null,
    val personOpenedClass: MyClass? = null,
    val personWeekYear: Int = IsoDateUtils.isoWeekYear(),
    val personWeek: Int = IsoDateUtils.isoWeek(),
    val pinnedIds: Set<String> = emptySet(),
    val roomSchedule: ScheduleWeek? = null,
    val roomTarget: RoomTarget? = null,
    val roomWeekYear: Int = IsoDateUtils.isoWeekYear(),
    val roomWeek: Int = IsoDateUtils.isoWeek(),
    /** Live room occupancy list (in-use flags). */
    val roomsOccupancy: List<dk.betterw4.android.feature.directory.RoomParser.RoomWithOccupancy> = emptyList(),
    val houses: List<House> = emptyList(),
    val selectedHouseId: String? = null,
    val myClasses: List<MyClass> = emptyList(),
    val selectedClassId: String? = null,
    val classNextLessons: Map<String, ClassNextLesson> = emptyMap(),
    val myTeachers: List<MyTeacher> = emptyList(),
    val card: StudentCard? = null,
    val plans: List<StudyPlan> = emptyList(),
    val planDetail: StudyPlan? = null,
    val moduleStats: List<ModuleStat> = emptyList(),
    val terms: List<SchoolTerm> = emptyList(),
    /** Subject currently open in the edit sheet (canonical code). */
    val editingSubjectCode: String? = null,
    val updateMessage: String? = null,
    val message: UiText? = null,
    val documents: dk.betterw4.android.feature.documents.W4DocumentListing? = null,
    val documentsStack: List<DocumentNav> = emptyList(),
    val trips: List<dk.betterw4.android.feature.trips.W4Trip> = emptyList(),
    val letterUri: android.net.Uri? = null,
    val eaPage: ExtraAcademicsPage? = null,
    val documentsExtraAcademics: Boolean = false,
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
    private val houseRepo: HouseRepository,
    private val myClassRepo: MyClassRepository,
    private val myTeacherRepo: MyTeacherRepository,
    private val scheduleRepo: ScheduleRepository,
    private val roomScheduleRepo: RoomScheduleRepository,
    private val pendingCompose: PendingComposeRecipient,
    private val studiekortRepo: StudiekortRepository,
    private val plansRepo: PlanRepository,
    private val moduleStatRepo: ModuleStatRepository,
    private val termRepo: TermRepository,
    private val documentsRepo: W4DocumentsRepository,
    private val tripsRepo: W4TripsRepository,
    private val cache: SimpleCache,
    private val appUpdateProbe: AppUpdateProbe,
    val settings: SettingsStore,
) : ViewModel() {

    private val _state = MutableStateFlow(
        MoreUiState(
            student = session.currentStudent,
            pinnedIds = pinRepo.pinnedIds(),
        ),
    )
    val state: StateFlow<MoreUiState> = _state.asStateFlow()

    private val personWeekCache = ConcurrentHashMap<String, ScheduleWeek>()
    private val roomWeekCache = ConcurrentHashMap<String, ScheduleWeek>()

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
    }

    val appearance = settings.appearance.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.appearance.value)
    val language = settings.language.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.language.value)
    val calendarStyle = settings.calendarStyle.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.calendarStyle.value)
    val useSubjectColors = settings.useSubjectColors
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.useSubjectColors.value)
    val showSchoolCalendar = settings.showSchoolCalendar
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.showSchoolCalendar.value)
    val notifEvents = settings.notifEvents
    val notifAssignments = settings.notifAssignments
    val notifTrips = settings.notifTrips
    val disableSignature = settings.disableSignature
    val lessonMappings = settings.lessonMappings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.lessonMappings.value)
    val notificationHistory = settings.notificationHistory
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.notificationHistory.value)

    fun navigate(dest: MoreDestination) {
        if (dest == MoreDestination.MAIL && !FeatureFlags.MAIL_ENABLED) return
        _state.update {
            it.copy(
                destination = dest,
                message = null,
                gradeDetail = null,
                selectedPerson = null,
                personEntity = null,
                personSchedule = null,
                studentProfile = null,
                personTab = PersonProfileTab.SCHEDULE,
                personOpenedHouseId = null,
                personOpenedClass = null,
                roomSchedule = null,
                roomTarget = null,
                selectedHouseId = if (dest == MoreDestination.HOUSES) it.selectedHouseId else null,
                selectedClassId = if (dest == MoreDestination.MY_CLASSES) it.selectedClassId else null,
                planDetail = null,
                documentsStack = if (dest == MoreDestination.DOCUMENTS) emptyList() else it.documentsStack,
                documentsExtraAcademics = false,
                eaPage = if (dest == MoreDestination.EA_PAGE) it.eaPage else null,
            )
        }
        when (dest) {
            MoreDestination.GRADES -> {
                loadGrades()
            }
            MoreDestination.ABSENCE -> {
                loadAbsence()
            }
            MoreDestination.DIRECTORY -> {
                searchDirectory()
                if (_state.value.houses.isEmpty()) loadHouses()
            }
            MoreDestination.ROOMS -> loadRoomsOccupancy()
            MoreDestination.HOUSES -> loadHouses()
            MoreDestination.MY_CLASSES -> loadMyClasses()
            MoreDestination.MY_TEACHERS -> loadMyTeachers()
            MoreDestination.STUDIEKORT -> {
                loadCard()
            }
            MoreDestination.PLANS -> loadPlans()
            MoreDestination.MODULE_STATS -> loadModuleStats()
            MoreDestination.TERM -> loadTerms()
            MoreDestination.SETTINGS -> {
                session.currentStudent?.let { student ->
                    if (!student.isDemo) {
                        settings.activateScope(student.studentId, student.gymId.toString())
                    }
                }
            }
            MoreDestination.DOCUMENTS -> loadDocuments()
            MoreDestination.TRIPS -> loadTrips()
            MoreDestination.HOME,
            MoreDestination.NOTIFICATIONS,
            MoreDestination.ON_DUTY,
            MoreDestination.BIRTHDAYS,
            MoreDestination.MAIL,
            MoreDestination.ASSESSMENTS,
            MoreDestination.EXTRA_ACADEMICS,
            MoreDestination.EA_PAGE,
            MoreDestination.SETTINGS_PRIVACY,
            MoreDestination.ROOT -> Unit
        }
    }

    fun openEaPage(page: ExtraAcademicsPage) {
        _state.update {
            it.copy(destination = MoreDestination.EA_PAGE, eaPage = page, message = null)
        }
    }

    fun openEaDocuments() {
        _state.update {
            it.copy(
                destination = MoreDestination.DOCUMENTS,
                documentsStack = emptyList(),
                documentsExtraAcademics = true,
                message = null,
            )
        }
        loadDocuments()
    }

    fun openSchoolDocuments() {
        _state.update {
            it.copy(
                destination = MoreDestination.DOCUMENTS,
                documentsStack = emptyList(),
                documentsExtraAcademics = false,
                message = null,
            )
        }
        loadDocuments()
    }

    fun back() {
        val s = _state.value
        when {
            s.gradeDetail != null -> _state.update { it.copy(gradeDetail = null) }
            s.planDetail != null -> _state.update { it.copy(planDetail = null) }
            s.personOpenedClass != null -> _state.update { it.copy(personOpenedClass = null) }
            s.personOpenedHouseId != null -> _state.update { it.copy(personOpenedHouseId = null) }
            s.personSchedule != null || s.personEntity != null -> _state.update {
                it.copy(
                    personSchedule = null,
                    personEntity = null,
                    studentProfile = null,
                    personTab = PersonProfileTab.SCHEDULE,
                    personOpenedHouseId = null,
                    personOpenedClass = null,
                )
            }
            s.roomSchedule != null || s.roomTarget != null -> _state.update {
                it.copy(roomSchedule = null, roomTarget = null)
            }
            s.selectedHouseId != null -> _state.update { it.copy(selectedHouseId = null) }
            s.selectedClassId != null -> _state.update { it.copy(selectedClassId = null) }
            s.destination == MoreDestination.DOCUMENTS && s.documentsStack.isNotEmpty() -> {
                _state.update { it.copy(documentsStack = it.documentsStack.dropLast(1)) }
                loadDocuments()
            }
            s.destination == MoreDestination.DOCUMENTS && s.documentsExtraAcademics -> _state.update {
                it.copy(
                    destination = MoreDestination.EXTRA_ACADEMICS,
                    documents = null,
                    documentsStack = emptyList(),
                    documentsExtraAcademics = false,
                )
            }
            s.destination == MoreDestination.EA_PAGE -> _state.update {
                it.copy(destination = MoreDestination.EXTRA_ACADEMICS, eaPage = null)
            }
            s.destination == MoreDestination.SETTINGS_PRIVACY -> _state.update {
                it.copy(destination = MoreDestination.SETTINGS)
            }
            else -> _state.update { it.copy(destination = MoreDestination.ROOT) }
        }
    }

    /**
     * Walk one step toward [root] instead of the More menu. Used by the Students tab so
     * backing out of a profile lands on the directory, not the More root.
     */
    fun backTo(root: MoreDestination) {
        val s = _state.value
        val atRoot = s.destination == root &&
            s.gradeDetail == null &&
            s.planDetail == null &&
            s.personEntity == null &&
            s.personSchedule == null &&
            s.personOpenedHouseId == null &&
            s.personOpenedClass == null &&
            s.roomTarget == null &&
            s.roomSchedule == null &&
            s.selectedHouseId == null &&
            s.selectedClassId == null
        if (atRoot) return
        back()
        if (_state.value.destination == MoreDestination.ROOT && root != MoreDestination.ROOT) {
            _state.update { it.copy(destination = root) }
        }
    }

    /** Jump straight to the top-level More menu (used when reselecting the More tab). */
    fun popToRoot() {
        _state.update {
            it.copy(
                destination = MoreDestination.ROOT,
                message = null,
                gradeDetail = null,
                selectedPerson = null,
                personEntity = null,
                personSchedule = null,
                studentProfile = null,
                personTab = PersonProfileTab.SCHEDULE,
                personOpenedHouseId = null,
                personOpenedClass = null,
                roomSchedule = null,
                roomTarget = null,
                selectedHouseId = null,
                selectedClassId = null,
                planDetail = null,
                documents = null,
                documentsStack = emptyList(),
                documentsExtraAcademics = false,
                trips = emptyList(),
                eaPage = null,
            )
        }
    }

    /** Students tab reselect: drop profile and stay on the directory list. */
    fun popToDirectory() {
        _state.update {
            it.copy(
                destination = MoreDestination.DIRECTORY,
                message = null,
                selectedPerson = null,
                personEntity = null,
                personSchedule = null,
                studentProfile = null,
                personTab = PersonProfileTab.SCHEDULE,
                personOpenedHouseId = null,
                personOpenedClass = null,
                roomSchedule = null,
                roomTarget = null,
            )
        }
    }

    fun selectedHouse(): House? {
        val id = _state.value.selectedHouseId ?: return null
        return _state.value.houses.firstOrNull { it.id == id }
    }

    fun openHouse(house: House) {
        _state.update { it.copy(selectedHouseId = house.id, message = null) }
    }

    fun setPersonTab(tab: PersonProfileTab) {
        _state.update { it.copy(personTab = tab) }
    }

    fun openPersonHouse() {
        val houseId = _state.value.studentProfile?.houseId ?: return
        if (_state.value.destination == MoreDestination.HOUSES &&
            _state.value.selectedHouseId == houseId
        ) {
            back()
            return
        }
        _state.update { it.copy(personOpenedHouseId = houseId, personOpenedClass = null) }
        if (_state.value.houses.none { it.id == houseId && it.loaded }) {
            loadHouses()
        }
    }

    fun openPersonRoom() {
        openPersonHouse()
    }

    fun openPersonClass(item: PersonClass) {
        val id = item.id?.trim().orEmpty()
        if (id.isEmpty()) return
        val existing = _state.value.myClasses.firstOrNull { it.id.equals(id, ignoreCase = true) }
        _state.update {
            it.copy(
                personOpenedClass = existing ?: MyClass(id = id, subject = item.name),
                personOpenedHouseId = null,
            )
        }
        if (existing?.loaded != true) loadMyClass(id)
        loadClassNextLessons()
    }

    fun selectedClass(): MyClass? {
        val id = _state.value.selectedClassId ?: return null
        return _state.value.myClasses.firstOrNull { it.id.equals(id, ignoreCase = true) }
    }

    fun openMyClass(item: MyClass) {
        _state.update { it.copy(selectedClassId = item.id, message = null) }
        if (!item.loaded) loadMyClass(item.id)
        loadClassNextLessons()
    }

    fun openClassRoom(room: dk.betterw4.android.feature.classes.ClassRoom) {
        val id = room.id ?: return
        openRoomSchedule(RoomTarget(id = id, name = room.name))
    }

    fun openMyTeacher(item: MyTeacher) {
        openStudentProfile(item.entity)
    }

    private fun loadMyTeachers() = viewModelScope.launch {
        _state.update { it.copy(loading = _state.value.myTeachers.isEmpty(), message = null) }
        when (val res = myTeacherRepo.load()) {
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
            is AppResult.Success -> _state.update {
                it.copy(myTeachers = res.data, loading = false)
            }
        }
    }

    fun selfClassMemberId(): String? {
        val student = _state.value.student ?: session.currentStudent ?: return null
        if (student.isDemo) return "S1"
        return student.studentId
    }

    fun refreshMyClasses() {
        val selected = _state.value.selectedClassId ?: _state.value.personOpenedClass?.id
        if (selected != null) {
            loadMyClass(selected, force = true)
        } else {
            loadMyClasses(force = true)
        }
    }

    private fun loadClassNextLessons() = viewModelScope.launch {
        val week = scheduleRepo.cachedWeek()
        val next = week?.let { ClassNextLessons.map(it, W4Dates.now()) }.orEmpty()
        _state.update { it.copy(classNextLessons = next) }
    }

    private fun loadMyClasses() = loadMyClasses(force = false)

    private fun loadMyClasses(force: Boolean) = viewModelScope.launch {
        _state.update { it.copy(loading = force || it.myClasses.isEmpty(), message = null) }
        loadClassNextLessons()
        when (val res = myClassRepo.loadIndex(force = force)) {
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
            is AppResult.Success -> {
                _state.update { it.copy(myClasses = res.data, loading = false) }
                res.data.forEachIndexed { index, item ->
                    val priority = if (index == 0) {
                        dk.betterw4.android.core.w4.model.FetchPriority.Important
                    } else {
                        dk.betterw4.android.core.w4.model.FetchPriority.Opportunistic
                    }
                    when (val page = myClassRepo.loadClass(item.id, priority = priority)) {
                        is AppResult.Success -> _state.update { state ->
                            val merged = W4ClassParser.merge(
                                state.myClasses.firstOrNull { existing ->
                                    existing.id.equals(page.data.id, ignoreCase = true)
                                } ?: item,
                                page.data,
                            )
                            state.copy(
                                myClasses = state.myClasses.map { existing ->
                                    if (existing.id.equals(merged.id, ignoreCase = true)) merged else existing
                                },
                            )
                        }
                        is AppResult.Failure -> Unit
                    }
                }
            }
        }
    }

    private fun loadMyClass(classId: String, force: Boolean = false) = viewModelScope.launch {
        if (force) _state.update { it.copy(loading = true, message = null) }
        loadClassNextLessons()
        when (val res = myClassRepo.loadClass(classId, force = force)) {
            is AppResult.Success -> _state.update { state ->
                val base = state.myClasses.firstOrNull { it.id.equals(classId, ignoreCase = true) }
                val merged = if (base != null) W4ClassParser.merge(base, res.data) else res.data
                val classes = if (state.myClasses.any { it.id.equals(classId, ignoreCase = true) }) {
                    state.myClasses.map { existing ->
                        if (existing.id.equals(classId, ignoreCase = true)) merged else existing
                    }
                } else {
                    state.myClasses + merged
                }
                state.copy(
                    myClasses = classes,
                    loading = false,
                    personOpenedClass = if (state.personOpenedClass?.id.equals(classId, ignoreCase = true)) {
                        merged
                    } else {
                        state.personOpenedClass
                    },
                )
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    private fun loadHouses() = viewModelScope.launch {
        _state.update { it.copy(loading = _state.value.houses.isEmpty(), message = null) }
        when (val res = houseRepo.loadIndex()) {
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
            is AppResult.Success -> {
                _state.update { it.copy(houses = res.data, loading = false) }
                res.data.forEachIndexed { index, house ->
                    val priority = if (index == 0) {
                        dk.betterw4.android.core.w4.model.FetchPriority.Important
                    } else {
                        dk.betterw4.android.core.w4.model.FetchPriority.Opportunistic
                    }
                    when (val page = houseRepo.loadHouse(house.id, priority = priority)) {
                        is AppResult.Success -> _state.update { state ->
                            state.copy(
                                houses = state.houses.map { existing ->
                                    if (existing.id == page.data.id) page.data else existing
                                },
                            )
                        }
                        is AppResult.Failure -> Unit
                    }
                }
            }
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

    fun onDirectoryKind(kind: DirectoryEntityKind) {
        if (_state.value.directoryKind == kind) return
        _state.update {
            it.copy(
                directoryKind = kind,
                directory = visibleDirectory(it.directory, kind, it.directoryYear),
            )
        }
        searchDirectory()
    }

    fun onDirectoryYear(year: String?) {
        if (_state.value.directoryYear == year) return
        _state.update {
            it.copy(
                directoryYear = year,
                directory = visibleDirectory(it.directory, it.directoryKind, year),
            )
        }
        searchDirectory()
    }

    private fun searchDirectory() = viewModelScope.launch {
        _state.update { it.copy(loading = it.directory.isEmpty()) }
        when (val res = directoryRepo.search(_state.value.directoryQuery, _state.value.directoryKind)) {
            is AppResult.Success -> {
                val classLabel = session.currentStudent?.classLabel
                val ranked = dk.betterw4.android.feature.directory.DirectorySearch.rank(
                    items = res.data,
                    query = _state.value.directoryQuery,
                    pinnedIds = pinRepo.pinnedIds(),
                    classmateClassLabel = classLabel,
                )
                _state.update {
                    it.copy(
                        loading = false,
                        directory = visibleDirectory(ranked, it.directoryKind, it.directoryYear),
                        pinnedIds = pinRepo.pinnedIds(),
                    )
                }
            }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    private fun visibleDirectory(
        items: List<DirectoryEntity>,
        kind: DirectoryEntityKind,
        year: String?,
    ): List<DirectoryEntity> = items.filter { person ->
        if (person.kind != kind) return@filter false
        if (kind != DirectoryEntityKind.STUDENT || year.isNullOrBlank()) return@filter true
        person.resolvedYear == year
    }

    fun togglePin(entity: DirectoryEntity) {
        pinRepo.toggle(entity.id)
        val classLabel = session.currentStudent?.classLabel
        _state.update {
            it.copy(
                pinnedIds = pinRepo.pinnedIds(),
                directory = visibleDirectory(
                    dk.betterw4.android.feature.directory.DirectorySearch.rank(
                        items = it.directory,
                        query = it.directoryQuery,
                        pinnedIds = pinRepo.pinnedIds(),
                        classmateClassLabel = classLabel,
                    ),
                    it.directoryKind,
                    it.directoryYear,
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
     * Open the dedicated person profile page (hero + about + week schedule).
     */
    fun openStudentProfile(entity: DirectoryEntity) = viewModelScope.launch {
        val year = IsoDateUtils.isoWeekYear()
        val week = IsoDateUtils.isoWeek()
        val isStaff = entity.kind == DirectoryEntityKind.TEACHER
        val cachedPlacement = if (isStaff) null else _state.value.houses.placementOf(entity.id)
        val cachedWeek = personWeekCache[personWeekKey(entity.id, year, week)]
            ?: roomScheduleRepo.cachedPersonWeek(entity, year, week)
        if (cachedWeek != null) {
            personWeekCache[personWeekKey(entity.id, year, week)] = cachedWeek
        }
        _state.update {
            it.copy(
                selectedPerson = null,
                loading = cachedWeek == null,
                personEntity = entity,
                personSchedule = cachedWeek,
                studentProfile = StudentProfile.from(entity, cachedPlacement),
                personTab = if (isStaff) PersonProfileTab.ABOUT else PersonProfileTab.SCHEDULE,
                personOpenedHouseId = null,
                personOpenedClass = null,
                personWeekYear = year,
                personWeek = week,
            )
        }
        coroutineScope {
            val weekDeferred = async { roomScheduleRepo.loadPersonWeek(entity, year, week) }
            val placementDeferred = async {
                if (isStaff) null else cachedPlacement ?: houseRepo.findPlacement(entity.id)
            }
            val profileDeferred = async { directoryRepo.loadProfile(entity) }
            val weekRes = weekDeferred.await()
            val placement = placementDeferred.await()
            val parsed = (profileDeferred.await() as? AppResult.Success)?.data
            rememberPlacement(placement)
            val weekData = (weekRes as? AppResult.Success)?.data
            if (weekData != null) {
                personWeekCache[personWeekKey(entity.id, year, week)] = weekData
            }
            _state.update {
                it.copy(
                    loading = false,
                    personSchedule = weekData ?: it.personSchedule,
                    studentProfile = StudentProfile.from(entity, placement, parsed),
                    message = (weekRes as? AppResult.Failure)?.error?.toUiText() ?: it.message,
                )
            }
        }
    }

    fun openPersonSchedule(entity: DirectoryEntity) = openStudentProfile(entity)

    fun shiftPersonWeek(delta: Int) {
        val currentStart = IsoDateUtils.weekStart(
            _state.value.personWeekYear,
            _state.value.personWeek,
        )
        loadPersonWeekForDate(currentStart.plusWeeks(delta.toLong()))
    }

    fun goToPersonToday() {
        val today = java.time.LocalDate.now()
        val year = IsoDateUtils.isoWeekYear(today)
        val week = IsoDateUtils.isoWeek(today)
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
        val year = IsoDateUtils.isoWeekYear(date)
        val week = IsoDateUtils.isoWeek(date)
        if (year == _state.value.personWeekYear &&
            week == _state.value.personWeek &&
            _state.value.personSchedule != null
        ) {
            return@launch
        }
        val cacheKey = personWeekKey(entity.id, year, week)
        val memory = personWeekCache[cacheKey]
        val cached = memory ?: roomScheduleRepo.cachedPersonWeek(entity, year, week)
        if (cached != null) {
            personWeekCache[cacheKey] = cached
        }
        _state.update {
            it.copy(
                loading = cached == null,
                personWeekYear = year,
                personWeek = week,
                personSchedule = cached,
            )
        }
        if (memory != null) return@launch
        when (val res = roomScheduleRepo.loadPersonWeek(entity, year, week)) {
            is AppResult.Success -> {
                personWeekCache[cacheKey] = res.data
                _state.update {
                    it.copy(
                        loading = false,
                        personWeekYear = year,
                        personWeek = week,
                        personSchedule = res.data,
                    )
                }
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    private fun personWeekKey(id: String, year: Int, week: Int) = "$id-$year-$week"

    private fun roomWeekKey(id: String, year: Int, week: Int) = "room-$id-$year-$week"

    private fun rememberPlacement(placement: HousePlacement?) {
        val house = placement?.house ?: return
        _state.update { state ->
            val existing = state.houses.indexOfFirst { it.id == house.id }
            val houses = if (existing >= 0) {
                state.houses.toMutableList().also { it[existing] = house }
            } else {
                state.houses + house
            }
            state.copy(houses = houses)
        }
    }

    fun displayTitleForEvent(event: ScheduleEvent): String = settings.displayTitleForEvent(event)

    fun accentArgbForEvent(event: ScheduleEvent): Long = settings.accentArgbFor(event)

    /**
     * Queue compose recipient and dismiss sheet. Caller opens the mailer.
     */
    fun composeToPerson(entity: DirectoryEntity) {
        if (!FeatureFlags.MAIL_ENABLED) {
            _state.update { it.copy(selectedPerson = null) }
            return
        }
        pendingCompose.offer(
            MessageRecipient(
                id = entity.id,
                name = entity.name,
                kind = entity.kind.name,
            ),
        )
        _state.update { it.copy(selectedPerson = null) }
    }

    fun openRoomSchedule(target: RoomTarget) = viewModelScope.launch {
        val year = IsoDateUtils.isoWeekYear()
        val week = IsoDateUtils.isoWeek()
        val cached = roomWeekCache[roomWeekKey(target.id, year, week)]
            ?: roomScheduleRepo.cachedRoomWeek(target.id, year, week)
        if (cached != null) {
            roomWeekCache[roomWeekKey(target.id, year, week)] = cached
        }
        _state.update {
            it.copy(
                loading = cached == null,
                roomTarget = target,
                roomSchedule = cached,
                roomWeekYear = year,
                roomWeek = week,
            )
        }
        when (val res = roomScheduleRepo.loadRoomWeek(target.id, year, week)) {
            is AppResult.Success -> {
                roomWeekCache[roomWeekKey(target.id, year, week)] = res.data
                _state.update { it.copy(loading = false, roomSchedule = res.data) }
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun shiftRoomWeek(delta: Int) {
        val currentStart = IsoDateUtils.weekStart(
            _state.value.roomWeekYear,
            _state.value.roomWeek,
        )
        loadRoomWeekForDate(currentStart.plusWeeks(delta.toLong()))
    }

    fun goToRoomToday() {
        val today = java.time.LocalDate.now()
        val year = IsoDateUtils.isoWeekYear(today)
        val week = IsoDateUtils.isoWeek(today)
        if (year == _state.value.roomWeekYear &&
            week == _state.value.roomWeek &&
            _state.value.roomSchedule != null
        ) {
            return
        }
        loadRoomWeekForDate(today)
    }

    fun loadRoomWeekForDate(date: java.time.LocalDate) = viewModelScope.launch {
        val target = _state.value.roomTarget ?: return@launch
        val year = IsoDateUtils.isoWeekYear(date)
        val week = IsoDateUtils.isoWeek(date)
        if (year == _state.value.roomWeekYear &&
            week == _state.value.roomWeek &&
            _state.value.roomSchedule != null
        ) {
            return@launch
        }
        val cacheKey = roomWeekKey(target.id, year, week)
        val memory = roomWeekCache[cacheKey]
        val cached = memory ?: roomScheduleRepo.cachedRoomWeek(target.id, year, week)
        if (cached != null) {
            roomWeekCache[cacheKey] = cached
        }
        _state.update {
            it.copy(
                loading = cached == null,
                roomWeekYear = year,
                roomWeek = week,
                roomSchedule = cached,
            )
        }
        if (memory != null) return@launch
        when (val res = roomScheduleRepo.loadRoomWeek(target.id, year, week)) {
            is AppResult.Success -> {
                roomWeekCache[cacheKey] = res.data
                _state.update {
                    it.copy(
                        loading = false,
                        roomWeekYear = year,
                        roomWeek = week,
                        roomSchedule = res.data,
                    )
                }
            }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun openRoomFromOccupancy(room: dk.betterw4.android.feature.directory.RoomParser.RoomWithOccupancy) {
        openRoomSchedule(
            RoomTarget(
                id = room.id,
                name = "${room.shortName} · ${room.name}",
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
                it.copy(
                    loading = false,
                    card = res.data,
                    profilePhotoUrl = res.data.photoUrl,
                    student = res.data.student,
                )
            }
            is AppResult.Failure -> _state.update { it.copy(loading = false, message = res.error.toUiText()) }
        }
    }

    fun openLetterOfAttendance() = viewModelScope.launch {
        when (val res = studiekortRepo.openLetterOfAttendance()) {
            is AppResult.Success -> _state.update { it.copy(letterUri = res.data) }
            is AppResult.Failure -> _state.update { it.copy(message = res.error.toUiText()) }
        }
    }

    fun consumeLetterUri() {
        _state.update { it.copy(letterUri = null) }
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

    private fun loadDocuments() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        val nav = _state.value.documentsStack.lastOrNull()
        when (
            val res = documentsRepo.load(
                folderId = nav?.folderId,
                pageId = nav?.pageId,
                extraAcademics = _state.value.documentsExtraAcademics,
                force = true,
            )
        ) {
            is AppResult.Success -> _state.update { it.copy(loading = false, documents = res.data) }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
        }
    }

    fun openDocument(node: W4DocumentNode) {
        val nav = when (node.kind) {
            W4DocumentKind.FOLDER -> DocumentNav(folderId = node.id)
            W4DocumentKind.PAGE -> DocumentNav(pageId = node.id)
        }
        _state.update { it.copy(documentsStack = it.documentsStack + nav) }
        loadDocuments()
    }

    private fun loadTrips() = viewModelScope.launch {
        _state.update { it.copy(loading = true) }
        when (val res = tripsRepo.load(force = true)) {
            is AppResult.Success -> _state.update { it.copy(loading = false, trips = res.data.trips) }
            is AppResult.Failure -> _state.update {
                it.copy(loading = false, message = res.error.toUiText())
            }
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
    fun setShowSchoolCalendar(v: Boolean) = settings.setShowSchoolCalendar(v)
    fun setNotifEvents(v: Boolean) = settings.setNotifEvents(v)
    fun setNotifAssignments(v: Boolean) = settings.setNotifAssignments(v)
    fun setNotifTrips(v: Boolean) = settings.setNotifTrips(v)
    fun setDisableSignature(v: Boolean) = settings.setDisableSignature(v)

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

    val privacyPolicyUrl: String get() = SettingsStore.PRIVACY_POLICY_URL

    val absenceCauses get() = AbsenceCauses.all
}
