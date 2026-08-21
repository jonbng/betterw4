package dk.betterw4.android.ui.screens.absence

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.core.FeatureFlags
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.absence.AbsenceOverview
import dk.betterw4.android.feature.absence.AbsenceRegisterForm
import dk.betterw4.android.feature.absence.AbsenceRegistration
import dk.betterw4.android.feature.absence.AbsenceRepository
import dk.betterw4.android.feature.absence.AbsenceSource
import dk.betterw4.android.feature.schedule.LessonAttendance
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleWeek
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

enum class AbsenceViewMode { WEEK, LIST }

data class AbsenceUiState(
    val loading: Boolean = true,
    val overview: AbsenceOverview? = null,
    val error: AppError? = null,
    val isDemo: Boolean = false,
    val source: AbsenceSource = AbsenceSource.ACADEMICS,
    val mode: AbsenceViewMode = AbsenceViewMode.WEEK,
    val selectedDate: LocalDate = LocalDate.now(),
    val showRegister: Boolean = false,
    val registerForm: AbsenceRegisterForm? = null,
    val registerLoading: Boolean = false,
    val registerError: String? = null,
    val selectedSlots: Set<String> = emptySet(),
    val wholeDay: Boolean = false,
    val reason: String = "",
    val showWebFallback: Boolean = false,
)

@HiltViewModel
class AbsenceViewModel @Inject constructor(
    private val absenceRepo: AbsenceRepository,
    session: SessionController,
) : ViewModel() {
    private val _state = MutableStateFlow(
        AbsenceUiState(isDemo = session.currentStudent?.isDemo == true),
    )
    val state: StateFlow<AbsenceUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh(force: Boolean = false) {
        val date = _state.value.selectedDate
        _state.update {
            it.copy(
                loading = it.overview == null,
                error = if (it.overview == null) null else it.error,
            )
        }
        viewModelScope.launch {
            when (
                val res = absenceRepo.loadOverview(
                    force = force,
                    year = IsoDateUtils.isoWeekYear(date),
                    week = IsoDateUtils.isoWeek(date),
                )
            ) {
                is AppResult.Success -> _state.update {
                    it.copy(loading = false, overview = res.data, error = null)
                }
                is AppResult.Failure -> _state.update { state ->
                    state.copy(
                        loading = false,
                        error = if (state.overview == null) res.error else state.error,
                    )
                }
            }
        }
    }

    fun setSource(source: AbsenceSource) {
        _state.update { it.copy(source = source) }
    }

    fun setMode(mode: AbsenceViewMode) {
        _state.update { it.copy(mode = mode) }
    }

    fun selectDate(date: LocalDate) {
        val current = _state.value.selectedDate
        val weekChanged = IsoDateUtils.isoWeek(date) != IsoDateUtils.isoWeek(current) ||
            IsoDateUtils.isoWeekYear(date) != IsoDateUtils.isoWeekYear(current)
        _state.update { it.copy(selectedDate = date) }
        if (weekChanged) refresh(force = false)
    }

    fun shiftWeek(delta: Int) {
        selectDate(_state.value.selectedDate.plusWeeks(delta.toLong()))
    }

    fun weekForSource(): ScheduleWeek? {
        val overview = _state.value.overview ?: return null
        return if (_state.value.source == AbsenceSource.EA) overview.eaWeek else overview.academicWeek
    }

    fun lessonsOnSelectedDay(): List<ScheduleEvent> {
        val date = _state.value.selectedDate
        return weekForSource()
            ?.days
            ?.firstOrNull { it.date == date }
            ?.events
            ?.filter { it.attendance != null }
            .orEmpty()
    }

    fun listForSource(): List<AbsenceRegistration> {
        val overview = _state.value.overview ?: return emptyList()
        val label = _state.value.source.label
        return overview.registrations.filter { it.lessonTitle.equals(label, ignoreCase = true) }
    }

    fun openRegister() {
        if (_state.value.isDemo) return
        _state.update { it.copy(showRegister = true, registerLoading = true, registerError = null) }
        viewModelScope.launch {
            when (val res = absenceRepo.loadRegisterForm(force = true)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        registerLoading = false,
                        registerForm = res.data,
                        selectedSlots = emptySet(),
                        wholeDay = false,
                        reason = "",
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(
                        showRegister = false,
                        registerLoading = false,
                        registerError = res.error.toString(),
                        showWebFallback = true,
                    )
                }
            }
        }
    }

    fun closeRegister() {
        _state.update {
            it.copy(showRegister = false, registerForm = null, registerError = null)
        }
    }

    fun openWebFallback() {
        _state.update { it.copy(showRegister = false, showWebFallback = true) }
    }

    fun closeWebFallback() {
        _state.update { it.copy(showWebFallback = false) }
    }

    fun setRegisterDate(dateRaw: String) {
        _state.update { it.copy(registerLoading = true, registerError = null) }
        viewModelScope.launch {
            when (val res = absenceRepo.loadRegisterForm(dateRaw = dateRaw, force = true)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        registerLoading = false,
                        registerForm = res.data,
                        selectedSlots = emptySet(),
                        wholeDay = false,
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(
                        showRegister = false,
                        registerLoading = false,
                        registerError = res.error.toString(),
                        showWebFallback = true,
                    )
                }
            }
        }
    }

    fun toggleSlot(value: String) {
        _state.update { state ->
            val next = state.selectedSlots.toMutableSet()
            if (!next.add(value)) next.remove(value)
            state.copy(selectedSlots = next, wholeDay = false)
        }
    }

    fun setWholeDay(value: Boolean) {
        _state.update { it.copy(wholeDay = value) }
    }

    fun setReason(value: String) {
        _state.update { it.copy(reason = value.take(60)) }
    }

    fun submitRegister() {
        val state = _state.value
        if (!FeatureFlags.ABSENCE_WRITES_ENABLED) return
        val form = state.registerForm ?: return
        val reason = state.reason.trim()
        if (reason.isEmpty()) {
            _state.update { it.copy(registerError = "Absence reason is required.") }
            return
        }
        val enabledValues = form.slots.filterNot { it.disabled }.map { it.value }.toSet()
        val slots = if (state.wholeDay) {
            enabledValues.toList()
        } else {
            state.selectedSlots.filter { it in enabledValues }
        }
        if (slots.isEmpty()) {
            _state.update { it.copy(registerError = "Select at least one class.") }
            return
        }
        _state.update { it.copy(registerLoading = true, registerError = null) }
        viewModelScope.launch {
            when (
                val res = absenceRepo.submitRegisterForm(
                    dateRaw = form.dateRaw,
                    slotValues = slots,
                    reason = reason,
                    wholeDay = state.wholeDay,
                )
            ) {
                is AppResult.Success -> {
                    closeRegister()
                    refresh(force = true)
                }
                is AppResult.Failure -> _state.update {
                    it.copy(
                        showRegister = false,
                        registerLoading = false,
                        registerError = res.error.toString(),
                        showWebFallback = true,
                    )
                }
            }
        }
    }

    fun attendanceLabel(kind: LessonAttendance?): String = when (kind) {
        LessonAttendance.UNCHECKED -> "Not marked"
        LessonAttendance.PRESENT -> "Present"
        LessonAttendance.ABSENT -> "Absent"
        LessonAttendance.PREARRANGED -> "Prearranged"
        LessonAttendance.UNKNOWN -> "Unknown"
        null -> ""
    }
}
