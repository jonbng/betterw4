package dk.betterlectio.android.core.lectio.session

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * App-wide Lectio session signals.
 * iOS parity: Notification.Name.lectioSessionExpired
 */
@Singleton
class SessionEvents @Inject constructor() {
    private val _sessionExpired = MutableSharedFlow<Unit>(
        extraBufferCapacity = 1,
        replay = 0,
    )
    val sessionExpired: SharedFlow<Unit> = _sessionExpired.asSharedFlow()

    fun emitSessionExpired() {
        _sessionExpired.tryEmit(Unit)
    }
}
