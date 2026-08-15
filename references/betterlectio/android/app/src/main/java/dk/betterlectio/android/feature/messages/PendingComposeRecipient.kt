package dk.betterlectio.android.feature.messages

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import javax.inject.Singleton

/**
 * One-shot handoff: directory (or elsewhere) offers a recipient, Messages tab consumes
 * it into compose. Survives tab switches without nesting nav graphs.
 */
@Singleton
class PendingComposeRecipient @Inject constructor() {
    private val _pending = MutableStateFlow<MessageRecipient?>(null)
    val pending: StateFlow<MessageRecipient?> = _pending.asStateFlow()

    fun offer(recipient: MessageRecipient) {
        _pending.value = recipient
    }

    /** Returns and clears the pending recipient, or null if none. */
    fun consume(): MessageRecipient? {
        var taken: MessageRecipient? = null
        _pending.update { current ->
            taken = current
            null
        }
        return taken
    }
}
