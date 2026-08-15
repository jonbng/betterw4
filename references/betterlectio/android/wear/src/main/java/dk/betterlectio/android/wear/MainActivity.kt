package dk.betterlectio.android.wear

import android.app.Application
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import dk.betterlectio.android.wear.data.CachedWearSchedule
import dk.betterlectio.android.wear.data.WearScheduleRepository
import dk.betterlectio.android.wear.ui.BetterLectioWearTheme
import dk.betterlectio.android.wear.ui.ScheduleHomeScreen
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BetterLectioWearTheme {
                val model: WearScheduleViewModel = viewModel()
                ScheduleHomeScreen(model)
            }
        }
    }
}

data class WearScheduleUiState(
    val cached: CachedWearSchedule = CachedWearSchedule(),
    val selectedEpochDay: Long = LocalDate.now().toEpochDay(),
    val refreshing: Boolean = false,
    val phoneUnavailable: Boolean = false,
)

class WearScheduleViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = WearScheduleRepository(application)
    private val _state = MutableStateFlow(WearScheduleUiState())
    val state: StateFlow<WearScheduleUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.cached.collect { cached ->
                _state.update { it.copy(cached = cached) }
            }
        }
        refresh()
    }

    fun refresh() {
        if (_state.value.refreshing) return
        viewModelScope.launch {
            _state.update { it.copy(refreshing = true, phoneUnavailable = false) }
            val sent = repository.requestRefresh()
            _state.update { it.copy(refreshing = false, phoneUnavailable = !sent) }
        }
    }

    fun moveDay(offset: Long) {
        _state.update { current ->
            val available = current.cached.schedule?.events
                ?.map { it.dateEpochDay }
                ?.distinct()
                ?.sorted()
                .orEmpty()
            val target = current.selectedEpochDay + offset
            val bounded = when {
                available.isEmpty() -> target
                target < available.first() -> available.first()
                target > available.last() -> available.last()
                else -> target
            }
            current.copy(selectedEpochDay = bounded)
        }
    }
}
