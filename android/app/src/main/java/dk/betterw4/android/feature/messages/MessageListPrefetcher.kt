package dk.betterw4.android.feature.messages

import dk.betterw4.android.core.FeatureFlags
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Opportunistic message folder prefetch after auth.
 * iOS parity: MessageListPrefetcher warms Nyeste + Ulæst lists only — never opens
 * thread bodies (that would mark them read on Lectio while leaving the badge stale).
 */
@Singleton
class MessageListPrefetcher @Inject constructor(
    private val repository: MessageRepository,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun schedulePrefetch() {
        if (!FeatureFlags.MAIL_ENABLED) return
        scope.launch {
            try {
                repository.loadFolder(MessageFolder.INBOX, forceRefresh = true)
                repository.loadFolder(MessageFolder.SENT, forceRefresh = true)
                Timber.d("Message prefetch completed")
            } catch (t: Throwable) {
                Timber.w(t, "Message prefetch failed")
            }
        }
    }
}
