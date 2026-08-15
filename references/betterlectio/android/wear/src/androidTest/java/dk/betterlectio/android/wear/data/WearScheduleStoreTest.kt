package dk.betterlectio.android.wear.data

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dk.betterlectio.android.wear.model.WearScheduleEvent
import dk.betterlectio.android.wear.model.WearScheduleSnapshot
import dk.betterlectio.android.wear.model.WearSyncStatus
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearScheduleStoreTest {
    @Test
    fun errorStatusDoesNotDiscardLastReadySchedule() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val store = WearScheduleStore(context)
        val ready = WearScheduleSnapshot(
            generatedAtEpochMillis = 1,
            validUntilEpochMillis = 2,
            zoneId = "Europe/Copenhagen",
            events = listOf(
                WearScheduleEvent(
                    id = "math",
                    title = "Mathematics",
                    dateEpochDay = 20_000,
                ),
            ),
        )

        store.save(ready)
        store.save(
            ready.copy(
                generatedAtEpochMillis = 3,
                status = WearSyncStatus.ERROR,
                statusMessage = "offline",
                events = emptyList(),
            ),
        )
        val cached = store.read()

        assertNotNull(cached.schedule)
        assertEquals("math", cached.schedule?.events?.single()?.id)
        assertEquals(WearSyncStatus.ERROR, cached.latestStatus?.status)
    }
}
