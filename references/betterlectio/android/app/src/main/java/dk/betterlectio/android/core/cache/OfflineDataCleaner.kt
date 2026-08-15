package dk.betterlectio.android.core.cache

import dk.betterlectio.android.feature.attachments.AttachmentCache
import dk.betterlectio.android.feature.offline.OfflineDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Clears durable offline Lectio HTML / entity / Room caches on logout and session expiry
 * so the next account on the same device cannot read prior user data.
 */
@Singleton
class OfflineDataCleaner @Inject constructor(
    private val cache: SimpleCache,
    @param:Named("entityOffline") private val entityOffline: EntityOfflineStore,
    private val offlineDb: OfflineDatabase,
    private val attachmentCache: AttachmentCache,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun clearAll() {
        try {
            cache.clearAll()
        } catch (e: Exception) {
            Timber.w(e, "SimpleCache clear failed")
        }
        try {
            entityOffline.clear()
        } catch (e: Exception) {
            Timber.w(e, "EntityOfflineStore clear failed")
        }
        try {
            attachmentCache.clear()
        } catch (e: Exception) {
            Timber.w(e, "Attachment cache clear failed")
        }
        scope.launch {
            try {
                offlineDb.wipeOfflineData()
            } catch (e: Exception) {
                Timber.w(e, "Offline Room clear failed")
            }
        }
        Timber.i("Offline data cleared (logout / session expiry)")
    }
}
