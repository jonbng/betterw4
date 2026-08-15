package dk.betterlectio.android.feature.feedback

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Shared shake bus for [dk.betterlectio.android.ui.feedback.FeedbackHost] and
 * first-login onboarding. One detector emits here; listeners decide whether to
 * show the feedback confirm chip or unlock the onboarding gate.
 *
 * [practiceMode] lets onboarding reuse the real confirm chip without opening
 * the feedback sheet: chip tap emits [practiceChipConfirmed] instead.
 */
@Singleton
class ShakeInteractionGate @Inject constructor() {
    private val _shakeEvents = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val shakeEvents: SharedFlow<Unit> = _shakeEvents.asSharedFlow()

    private val _practiceChipConfirmed = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val practiceChipConfirmed: SharedFlow<Unit> = _practiceChipConfirmed.asSharedFlow()

    private val shakePromptSuppressors = ConcurrentHashMap.newKeySet<String>()

    private val _practiceMode = MutableStateFlow(false)
    val practiceMode: StateFlow<Boolean> = _practiceMode.asStateFlow()

    fun onShakeDetected() {
        _shakeEvents.tryEmit(Unit)
    }

    fun setShakePromptSuppressed(source: String, suppressed: Boolean) {
        if (suppressed) shakePromptSuppressors.add(source) else shakePromptSuppressors.remove(source)
    }

    fun isShakePromptSuppressed(): Boolean = shakePromptSuppressors.isNotEmpty()

    fun setPracticeMode(enabled: Boolean) {
        _practiceMode.value = enabled
    }

    fun isPracticeMode(): Boolean = _practiceMode.value

    fun notifyPracticeChipConfirmed() {
        _practiceChipConfirmed.tryEmit(Unit)
    }
}
