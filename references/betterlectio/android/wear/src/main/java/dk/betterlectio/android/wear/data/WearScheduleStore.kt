package dk.betterlectio.android.wear.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dk.betterlectio.android.wear.model.WearScheduleCodec
import dk.betterlectio.android.wear.model.WearScheduleSnapshot
import dk.betterlectio.android.wear.model.WearSyncStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.scheduleDataStore by preferencesDataStore(name = "wear_schedule")

data class CachedWearSchedule(
    val schedule: WearScheduleSnapshot? = null,
    val latestStatus: WearScheduleSnapshot? = null,
) {
    val effectiveStatus: WearSyncStatus
        get() = latestStatus?.status ?: schedule?.status ?: WearSyncStatus.ERROR
}

class WearScheduleStore(private val context: Context) {
    val cached: Flow<CachedWearSchedule> = context.scheduleDataStore.data.map { preferences ->
        CachedWearSchedule(
            schedule = preferences[READY_SNAPSHOT]?.decodeOrNull(),
            latestStatus = preferences[STATUS_SNAPSHOT]?.decodeOrNull(),
        )
    }

    suspend fun read(): CachedWearSchedule = cached.first()

    suspend fun save(snapshot: WearScheduleSnapshot) {
        context.scheduleDataStore.edit { preferences ->
            val encoded = WearScheduleCodec.encode(snapshot)
            if (snapshot.status == WearSyncStatus.READY) {
                preferences[READY_SNAPSHOT] = encoded
                preferences.remove(STATUS_SNAPSHOT)
            } else {
                preferences[STATUS_SNAPSHOT] = encoded
            }
        }
    }

    private fun String.decodeOrNull(): WearScheduleSnapshot? =
        runCatching { WearScheduleCodec.decode(this) }.getOrNull()

    private companion object {
        val READY_SNAPSHOT = stringPreferencesKey("ready_snapshot")
        val STATUS_SNAPSHOT = stringPreferencesKey("status_snapshot")
    }
}
