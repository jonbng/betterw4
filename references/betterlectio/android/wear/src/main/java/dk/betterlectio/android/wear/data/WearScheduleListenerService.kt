package dk.betterlectio.android.wear.data

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import dk.betterlectio.android.wear.model.WearScheduleProtocol
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class WearScheduleListenerService : WearableListenerService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents
            .filter {
                it.type == DataEvent.TYPE_CHANGED &&
                    it.dataItem.uri.path == WearScheduleProtocol.SNAPSHOT_PATH
            }
            .forEach { event ->
                val encoded = DataMapItem.fromDataItem(event.dataItem)
                    .dataMap
                    .getString(WearScheduleProtocol.SNAPSHOT_JSON_KEY)
                    ?: return@forEach
                scope.launch {
                    WearScheduleRepository(applicationContext).saveSnapshotJson(encoded)
                }
            }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
