package dk.betterw4.android.ui.screens.homework

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.feature.homework.HomeworkDayGroup
import dk.betterw4.android.feature.homework.HomeworkItem
import dk.betterw4.android.feature.homework.HomeworkRepository
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
import javax.inject.Inject

data class HomeworkUiState(
    val loading: Boolean = true,
    val items: List<HomeworkItem> = emptyList(),
    val groups: List<HomeworkDayGroup> = emptyList(),
    val selected: HomeworkItem? = null,
    val error: AppError? = null,
)

@HiltViewModel
class HomeworkViewModel @Inject constructor(
    private val repository: HomeworkRepository,
    private val settings: SettingsStore,
    private val reviewPromptCoordinator: ReviewPromptCoordinator,
) : ViewModel() {
    private val _state = MutableStateFlow(HomeworkUiState())
    val state: StateFlow<HomeworkUiState> = _state.asStateFlow()

    val lessonMappings = settings.lessonMappings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.lessonMappings.value)

    fun displayTeam(team: String): String =
        settings.displayNameForSubject(team, fallback = team)

    init {
        refresh()
    }

    fun refresh(force: Boolean = false) {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            when (val res = repository.load(force)) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        loading = false,
                        items = res.data,
                        groups = res.data.groupedByDate(),
                    )
                }
                is AppResult.Failure -> {
                    reviewPromptCoordinator.reportRecentError()
                    _state.update { it.copy(loading = false, error = res.error) }
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
}
