package dk.betterw4.android.ui.screens.homework

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.feature.homework.AssessmentCalendarDay
import dk.betterw4.android.feature.homework.AssessmentDisplayMode
import dk.betterw4.android.feature.homework.AssessmentMonth
import dk.betterw4.android.feature.homework.HomeworkDayGroup
import dk.betterw4.android.feature.homework.HomeworkItem
import dk.betterw4.android.feature.homework.HomeworkRepository
import dk.betterw4.android.feature.homework.assessmentCalendarDays
import dk.betterw4.android.feature.homework.groupedByDate
import dk.betterw4.android.feature.review.ReviewPromptCoordinator
import dk.betterw4.android.feature.review.ReviewTrigger
import dk.betterw4.android.feature.settings.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

data class HomeworkUiState(
    val loading: Boolean = true,
    val items: List<HomeworkItem> = emptyList(),
    val groups: List<HomeworkDayGroup> = emptyList(),
    val selected: HomeworkItem? = null,
    val error: AppError? = null,
    val month: AssessmentMonth = AssessmentMonth.current(),
    val selectedDay: LocalDate? = null,
    val displayMode: AssessmentDisplayMode = AssessmentDisplayMode.MONTH,
    val calendarDays: List<AssessmentCalendarDay> = emptyList(),
) {
    val isShowingCurrentMonth: Boolean get() = month == AssessmentMonth.current()
    val monthTitle: String get() = month.title()
}

@HiltViewModel
class HomeworkViewModel @Inject constructor(
    private val repository: HomeworkRepository,
    private val settings: SettingsStore,
    private val reviewPromptCoordinator: ReviewPromptCoordinator,
) : ViewModel() {
    private val _state = MutableStateFlow(HomeworkUiState())
    val state: StateFlow<HomeworkUiState> = _state.asStateFlow()
    private var loadGeneration = 0

    val lessonMappings = settings.lessonMappings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.lessonMappings.value)

    fun displayTeam(team: String): String =
        settings.displayNameForSubject(team, fallback = team)

    init {
        refresh()
    }

    fun refresh(force: Boolean = false) {
        load(_state.value.month, force)
    }

    fun shiftMonth(delta: Int) {
        load(_state.value.month.offset(delta), force = false)
    }

    fun showCurrentMonth() {
        load(AssessmentMonth.current(), force = false)
    }

    fun selectDay(day: LocalDate?) {
        val current = _state.value.selectedDay
        val next = when {
            day == null -> null
            current == day -> null
            else -> day
        }
        _state.update { it.copy(selectedDay = next, groups = groupsFor(it.items, next)) }
    }

    fun setDisplayMode(mode: AssessmentDisplayMode) {
        _state.update { it.copy(displayMode = mode) }
    }

    private fun load(target: AssessmentMonth, force: Boolean) {
        val generation = ++loadGeneration
        val monthChanged = _state.value.month != target
        _state.update {
            it.copy(
                month = target,
                loading = it.items.isEmpty() || monthChanged,
                error = if (monthChanged) null else it.error,
                items = if (monthChanged) emptyList() else it.items,
                groups = if (monthChanged) emptyList() else it.groups,
                selectedDay = if (monthChanged) null else it.selectedDay,
                calendarDays = if (monthChanged) emptyList() else it.calendarDays,
            )
        }
        viewModelScope.launch {
            when (val res = repository.load(force, target)) {
                is AppResult.Success -> {
                    if (generation != loadGeneration) return@launch
                    _state.update {
                        it.copy(
                            loading = false,
                            items = res.data,
                            groups = groupsFor(res.data, it.selectedDay),
                            calendarDays = assessmentCalendarDays(target, res.data),
                            error = null,
                        )
                    }
                }
                is AppResult.Failure -> {
                    if (generation != loadGeneration) return@launch
                    reviewPromptCoordinator.reportRecentError()
                    _state.update { state ->
                        state.copy(
                            loading = false,
                            error = if (state.items.isEmpty()) res.error else state.error,
                        )
                    }
                }
            }
        }
    }

    fun toggleDone(id: String) {
        val entry = _state.value.items.firstOrNull { it.id == id }
        val wasDone = entry?.done ?: repository.isDone(id)
        repository.toggleDone(id, entry)
        if (!wasDone) {
            reviewPromptCoordinator.maybePrompt(ReviewTrigger.HomeworkDone)
        }
        refresh()
    }

    fun select(item: HomeworkItem?) {
        if (item == null) {
            _state.update { it.copy(selected = null) }
            return
        }
        _state.update { it.copy(selected = item) }
        viewModelScope.launch {
            when (val res = repository.loadDetail(item)) {
                is AppResult.Success -> _state.update { it.copy(selected = res.data) }
                is AppResult.Failure -> Unit
            }
        }
    }

    private fun groupsFor(items: List<HomeworkItem>, selectedDay: LocalDate?): List<HomeworkDayGroup> {
        val visible = if (selectedDay == null) {
            items
        } else {
            items.filter { it.date == selectedDay }
        }
        return visible.groupedByDate()
    }
}
