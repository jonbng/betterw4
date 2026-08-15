package dk.betterlectio.android.wear.ui

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.core.app.ApplicationProvider
import dk.betterlectio.android.wear.R
import dk.betterlectio.android.wear.WearScheduleUiState
import dk.betterlectio.android.wear.data.CachedWearSchedule
import dk.betterlectio.android.wear.model.WearScheduleEvent
import dk.betterlectio.android.wear.model.WearScheduleSnapshot
import dk.betterlectio.android.wear.model.WearSyncStatus
import org.junit.Rule
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class ScheduleHomeScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val zone = ZoneId.of("Europe/Copenhagen")
    private val date = LocalDate.of(2026, 7, 23)
    private val now = date.atTime(8, 30).atZone(zone).toInstant().toEpochMilli()

    @Test
    fun currentLessonShowsCountdownAndTitle() {
        compose.setContent {
            BetterLectioWearTheme {
                ScheduleHomeContent(stateWith(event("Mathematics", 8, 9)), now, {}, {})
            }
        }

        compose.onNodeWithText(context.getString(R.string.ends_in, 30L)).assertExists()
        compose.onNodeWithText("Mathematics").assertExists()
    }

    @Test
    fun missingScheduleShowsPhoneSignInMessage() {
        val auth = snapshot(
            events = emptyList(),
            status = WearSyncStatus.AUTH_REQUIRED,
        )
        compose.setContent {
            BetterLectioWearTheme {
                ScheduleHomeContent(
                    WearScheduleUiState(
                        cached = CachedWearSchedule(latestStatus = auth),
                        selectedEpochDay = date.toEpochDay(),
                    ),
                    now,
                    {},
                    {},
                )
            }
        }

        compose.onNodeWithText(context.getString(R.string.open_phone)).assertExists()
    }

    @Test
    fun agendaShowsCancelledLesson() {
        val cancelled = event("Physics", 10, 11).copy(
            status = dk.betterlectio.android.wear.model.WearEventStatus.CANCELLED,
        )
        compose.setContent {
            BetterLectioWearTheme {
                ScheduleHomeContent(stateWith(cancelled), now, {}, {})
            }
        }

        compose.onNode(hasScrollAction()).performScrollToIndex(5)
        compose.onNodeWithText("Physics").assertExists()
    }

    private fun stateWith(vararg events: WearScheduleEvent) = WearScheduleUiState(
        cached = CachedWearSchedule(schedule = snapshot(events.toList())),
        selectedEpochDay = date.toEpochDay(),
    )

    private fun snapshot(
        events: List<WearScheduleEvent>,
        status: WearSyncStatus = WearSyncStatus.READY,
    ) = WearScheduleSnapshot(
        generatedAtEpochMillis = now,
        validUntilEpochMillis = now + 86_400_000,
        zoneId = zone.id,
        status = status,
        events = events,
    )

    private fun event(title: String, startHour: Int, endHour: Int) = WearScheduleEvent(
        id = title,
        title = title,
        room = "A12",
        startEpochMillis = date.atTime(startHour, 0).atZone(zone).toInstant().toEpochMilli(),
        endEpochMillis = date.atTime(endHour, 0).atZone(zone).toInstant().toEpochMilli(),
        dateEpochDay = date.toEpochDay(),
    )
}
