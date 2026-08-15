package dk.betterlectio.android.ui.screens.assignments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.posthog.PostHog
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.assignments.AssignmentDetail
import dk.betterlectio.android.feature.assignments.AssignmentFilter
import dk.betterlectio.android.feature.assignments.AssignmentItem
import dk.betterlectio.android.feature.assignments.AssignmentRepository
import dk.betterlectio.android.feature.assignments.matches
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AssignmentsUiState(
    val loading: Boolean = true,
    val items: List<AssignmentItem> = emptyList(),
    val filtered: List<AssignmentItem> = emptyList(),
    val filter: AssignmentFilter = AssignmentFilter.ALL,
    val detail: AssignmentDetail? = null,
    val error: AppError? = null,
)

@HiltViewModel
class AssignmentsViewModel @Inject constructor(
    private val repository: AssignmentRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(AssignmentsUiState())
    val state: StateFlow<AssignmentsUiState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh(force: Boolean = false) {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            when (val res = repository.load(force)) {
                is AppResult.Success -> {
                    val f = _state.value.filter
                    _state.update {
                        it.copy(
                            loading = false,
                            items = res.data,
                            filtered = res.data.filter { a -> a.matches(f) },
                        )
                    }
                }
                is AppResult.Failure -> _state.update { it.copy(loading = false, error = res.error) }
            }
        }
    }

    fun setFilter(filter: AssignmentFilter) {
        _state.update {
            it.copy(
                filter = filter,
                filtered = it.items.filter { a -> a.matches(filter) },
            )
        }
    }

    fun openDetail(item: AssignmentItem) {
        PostHog.capture(
            event = "assignment_detail_viewed",
            properties = mapOf("assignment_status" to item.status),
        )
        viewModelScope.launch {
            _state.update { it.copy(loading = true) }
            when (val res = repository.loadDetail(item)) {
                is AppResult.Success -> _state.update { it.copy(loading = false, detail = res.data) }
                is AppResult.Failure -> _state.update {
                    it.copy(loading = false, detail = AssignmentDetail(item), error = res.error)
                }
            }
        }
    }

    fun closeDetail() {
        _state.update { it.copy(detail = null) }
    }
}
