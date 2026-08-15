package dk.betterlectio.android.wear.data

import android.content.Context
import com.google.android.gms.wearable.Wearable
import dk.betterlectio.android.wear.model.WearScheduleProtocol
import kotlinx.coroutines.tasks.await

class WearScheduleRepository(context: Context) {
    private val appContext = context.applicationContext
    private val store = WearScheduleStore(appContext)

    val cached = store.cached

    suspend fun read(): CachedWearSchedule = store.read()

    suspend fun saveSnapshotJson(encoded: String): Boolean {
        val snapshot = runCatching {
            dk.betterlectio.android.wear.model.WearScheduleCodec.decode(encoded)
        }.getOrNull() ?: return false
        if (snapshot.schemaVersion > WearScheduleProtocol.SCHEMA_VERSION) return false
        store.save(snapshot)
        WearSurfaceUpdater.requestUpdates(appContext)
        return true
    }

    suspend fun requestRefresh(): Boolean {
        val nodes = runCatching {
            Wearable.getNodeClient(appContext).connectedNodes.await()
        }.getOrDefault(emptyList())
        if (nodes.isEmpty()) return false

        return nodes.map { node ->
            runCatching {
                Wearable.getMessageClient(appContext)
                    .sendMessage(node.id, WearScheduleProtocol.REFRESH_PATH, byteArrayOf())
                    .await()
            }.isSuccess
        }.any { it }
    }
}
