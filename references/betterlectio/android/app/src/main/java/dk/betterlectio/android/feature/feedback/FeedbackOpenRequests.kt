package dk.betterlectio.android.feature.feedback

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Lets non-shake call sites (More menu, rating pre-filter "could be better", etc.)
 * open the feedback sheet directly.
 */
@Singleton
class FeedbackOpenRequests @Inject constructor() {
    private val _requests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val requests: SharedFlow<Unit> = _requests.asSharedFlow()

    fun requestOpen() {
        _requests.tryEmit(Unit)
    }
}
