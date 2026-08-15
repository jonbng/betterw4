package dk.betterlectio.android.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import dk.betterlectio.android.wear.R
import dk.betterlectio.android.wear.WearScheduleViewModel
import dk.betterlectio.android.wear.model.CountdownKind
import dk.betterlectio.android.wear.model.WearCountdown
import dk.betterlectio.android.wear.model.WearCountdownProjector
import dk.betterlectio.android.wear.model.WearEventStatus
import dk.betterlectio.android.wear.model.WearScheduleEvent
import dk.betterlectio.android.wear.model.WearSyncStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.delay

@Composable
fun ScheduleHomeScreen(model: WearScheduleViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(30_000L - (now % 30_000L))
        }
    }
    ScheduleHomeContent(
        state = state,
        now = now,
        onRefresh = model::refresh,
        onMoveDay = model::moveDay,
    )
}

@Composable
internal fun ScheduleHomeContent(
    state: dk.betterlectio.android.wear.WearScheduleUiState,
    now: Long,
    onRefresh: () -> Unit,
    onMoveDay: (Long) -> Unit,
) {
    val snapshot = state.cached.schedule
    val countdown = remember(snapshot, now) {
        WearCountdownProjector.project(snapshot?.events.orEmpty(), now)
    }
    val dayEvents = snapshot?.events
        ?.filter { it.dateEpochDay == state.selectedEpochDay }
        ?.sortedWith(compareBy({ it.startEpochMillis }, { it.title }))
        .orEmpty()
    val listState = rememberScalingLazyListState()

    ScalingLazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(androidx.compose.ui.graphics.Color.Black),
        state = listState,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Text(
                text = stringResource(R.string.schedule).uppercase(Locale.getDefault()),
                color = BetterLectioWearColors.TextMuted,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
            )
        }
        item {
            Spacer(Modifier.height(6.dp))
            CountdownDial(countdown)
        }
        item {
            CountdownContext(countdown, snapshot?.zoneId)
        }
        if (snapshot == null) {
            item {
                EmptySyncState(
                    authRequired = state.cached.latestStatus?.status == WearSyncStatus.AUTH_REQUIRED,
                    refreshing = state.refreshing,
                    phoneUnavailable = state.phoneUnavailable,
                    onRefresh = onRefresh,
                )
            }
        } else {
            item {
                SyncBanner(
                    stale = snapshot.isStale(now),
                    authRequired = state.cached.latestStatus?.status == WearSyncStatus.AUTH_REQUIRED,
                    phoneUnavailable = state.phoneUnavailable,
                )
            }
            item {
                DaySelector(
                    epochDay = state.selectedEpochDay,
                    onPrevious = { onMoveDay(-1) },
                    onNext = { onMoveDay(1) },
                )
            }
            if (dayEvents.isEmpty()) {
                item {
                    Text(
                        text = stringResource(R.string.no_classes_today),
                        modifier = Modifier.padding(vertical = 12.dp),
                        color = BetterLectioWearColors.TextMuted,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            } else {
                items(dayEvents, key = { "${it.id}-${it.startEpochMillis}" }) { event ->
                    AgendaRow(event = event, zoneId = snapshot.zoneId)
                }
            }
            item {
                RefreshButton(refreshing = state.refreshing, onRefresh = onRefresh)
            }
            item {
                val updated = DateTimeFormatter
                    .ofLocalizedTime(FormatStyle.SHORT)
                    .withLocale(Locale.getDefault())
                    .withZone(ZoneId.systemDefault())
                    .format(Instant.ofEpochMilli(snapshot.generatedAtEpochMillis))
                Text(
                    text = stringResource(R.string.last_updated, updated),
                    modifier = Modifier.padding(vertical = 8.dp),
                    color = BetterLectioWearColors.TextMuted,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }
    }
}

@Composable
private fun CountdownDial(countdown: WearCountdown) {
    val progress = if (countdown.kind == CountdownKind.CURRENT) countdown.progress else 0f
    Box(modifier = Modifier.size(126.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 7.dp.toPx()
            val inset = stroke / 2
            drawArc(
                color = BetterLectioWearColors.BrandDim,
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = Size(size.width - stroke, size.height - stroke),
                style = Stroke(stroke, cap = StrokeCap.Round),
            )
            if (progress > 0f) {
                drawArc(
                    color = BetterLectioWearColors.Brand,
                    startAngle = -90f,
                    sweepAngle = progress * 360f,
                    useCenter = false,
                    topLeft = Offset(inset, inset),
                    size = Size(size.width - stroke, size.height - stroke),
                    style = Stroke(stroke, cap = StrokeCap.Round),
                )
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            val minutes = countdown.minutes
            Text(
                text = when {
                    countdown.kind == CountdownKind.NONE -> "—"
                    minutes == null -> "—"
                    minutes >= 60 -> "${minutes / 60}h ${minutes % 60}m"
                    else -> "$minutes"
                },
                color = androidx.compose.ui.graphics.Color.White,
                style = MaterialTheme.typography.displayMedium,
                fontWeight = FontWeight.Bold,
            )
            if (countdown.kind != CountdownKind.NONE && minutes != null && minutes < 60) {
                Text(
                    text = "MIN",
                    color = BetterLectioWearColors.TextMuted,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
private fun CountdownContext(countdown: WearCountdown, zoneId: String?) {
    val event = countdown.event
    if (event == null) {
        Text(
            text = stringResource(R.string.no_more_classes),
            modifier = Modifier.padding(top = 5.dp, bottom = 10.dp),
            color = BetterLectioWearColors.TextMuted,
            style = MaterialTheme.typography.bodyMedium,
        )
        return
    }
    val minutes = countdown.minutes ?: 0
    Text(
        text = when (countdown.kind) {
            CountdownKind.CURRENT ->
                if (minutes == 0L) stringResource(R.string.ends_now)
                else stringResource(R.string.ends_in, minutes)
            CountdownKind.NEXT ->
                if (minutes == 0L) stringResource(R.string.starts_now)
                else stringResource(R.string.starts_in, minutes)
            CountdownKind.NONE -> stringResource(R.string.no_more_classes)
        },
        modifier = Modifier.padding(top = 5.dp),
        color = BetterLectioWearColors.Brand,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
    )
    Text(
        text = event.title,
        modifier = Modifier.padding(horizontal = 10.dp),
        color = androidx.compose.ui.graphics.Color.White,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
    )
    val details = listOfNotNull(
        event.room?.takeIf { it.isNotBlank() },
        event.startEpochMillis?.let { formatTime(it, zoneId) },
    ).joinToString(" · ")
    if (details.isNotBlank()) {
        Text(
            text = details,
            color = BetterLectioWearColors.TextMuted,
            style = MaterialTheme.typography.labelSmall,
        )
    }
    Spacer(Modifier.height(10.dp))
}

@Composable
private fun DaySelector(
    epochDay: Long,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    val date = LocalDate.ofEpochDay(epochDay)
    val label = if (date == LocalDate.now()) {
        stringResource(R.string.today)
    } else {
        date.format(DateTimeFormatter.ofPattern("EEE d. MMM", Locale.getDefault()))
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = "‹",
            modifier = Modifier
                .clickable(onClick = onPrevious)
                .padding(horizontal = 12.dp, vertical = 6.dp),
            color = BetterLectioWearColors.Brand,
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            text = label,
            color = androidx.compose.ui.graphics.Color.White,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
        )
        Text(
            text = "›",
            modifier = Modifier
                .clickable(onClick = onNext)
                .padding(horizontal = 12.dp, vertical = 6.dp),
            color = BetterLectioWearColors.Brand,
            style = MaterialTheme.typography.titleLarge,
        )
    }
}

@Composable
private fun AgendaRow(event: WearScheduleEvent, zoneId: String) {
    val statusColor = when (event.status) {
        WearEventStatus.CANCELLED -> BetterLectioWearColors.Cancelled
        WearEventStatus.CHANGED -> BetterLectioWearColors.Changed
        WearEventStatus.NORMAL -> BetterLectioWearColors.Brand
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .background(BetterLectioWearColors.SurfaceRaised, RoundedCornerShape(16.dp))
            .padding(horizontal = 11.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(width = 3.dp, height = 34.dp)
                .background(statusColor, RoundedCornerShape(2.dp)),
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 8.dp),
        ) {
            Text(
                text = event.title,
                color = if (event.status == WearEventStatus.CANCELLED) {
                    BetterLectioWearColors.TextMuted
                } else {
                    androidx.compose.ui.graphics.Color.White
                },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textDecoration = if (event.status == WearEventStatus.CANCELLED) {
                    TextDecoration.LineThrough
                } else {
                    TextDecoration.None
                },
            )
            Text(
                text = eventTimeRange(event, zoneId) +
                    (event.room?.takeIf { it.isNotBlank() }?.let { " · $it" } ?: ""),
                color = BetterLectioWearColors.TextMuted,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SyncBanner(stale: Boolean, authRequired: Boolean, phoneUnavailable: Boolean) {
    val message = when {
        authRequired -> stringResource(R.string.open_phone)
        phoneUnavailable -> stringResource(R.string.phone_unavailable)
        stale -> stringResource(R.string.stale_schedule)
        else -> null
    } ?: return
    Text(
        text = message,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .background(BetterLectioWearColors.Surface, RoundedCornerShape(12.dp))
            .padding(8.dp),
        color = if (authRequired) BetterLectioWearColors.Changed else BetterLectioWearColors.TextMuted,
        style = MaterialTheme.typography.labelSmall,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun EmptySyncState(
    authRequired: Boolean,
    refreshing: Boolean,
    phoneUnavailable: Boolean,
    onRefresh: () -> Unit,
) {
    val message = when {
        authRequired -> stringResource(R.string.open_phone)
        refreshing -> stringResource(R.string.syncing)
        phoneUnavailable -> stringResource(R.string.phone_unavailable)
        else -> stringResource(R.string.syncing)
    }
    Text(
        text = message,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        color = BetterLectioWearColors.TextMuted,
        style = MaterialTheme.typography.bodyMedium,
        textAlign = TextAlign.Center,
    )
    RefreshButton(refreshing, onRefresh)
}

@Composable
private fun RefreshButton(refreshing: Boolean, onRefresh: () -> Unit) {
    Text(
        text = if (refreshing) stringResource(R.string.syncing) else stringResource(R.string.refresh),
        modifier = Modifier
            .padding(top = 6.dp)
            .background(BetterLectioWearColors.BrandDim, RoundedCornerShape(18.dp))
            .clickable(enabled = !refreshing, onClick = onRefresh)
            .padding(horizontal = 18.dp, vertical = 8.dp),
        color = androidx.compose.ui.graphics.Color.White,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
    )
}

private fun formatTime(epochMillis: Long, zoneId: String?): String =
    DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
        .withLocale(Locale.getDefault())
        .withZone(runCatching { ZoneId.of(zoneId) }.getOrDefault(ZoneId.systemDefault()))
        .format(Instant.ofEpochMilli(epochMillis))

private fun eventTimeRange(event: WearScheduleEvent, zoneId: String): String {
    if (event.isAllDay) return "All day"
    val start = event.startEpochMillis ?: return ""
    val end = event.endEpochMillis ?: return formatTime(start, zoneId)
    return "${formatTime(start, zoneId)}–${formatTime(end, zoneId)}"
}
