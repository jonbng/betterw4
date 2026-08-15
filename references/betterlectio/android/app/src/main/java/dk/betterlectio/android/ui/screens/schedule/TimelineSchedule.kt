package dk.betterlectio.android.ui.screens.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.ScheduleMultiDay
import dk.betterlectio.android.feature.schedule.timeLabelText
import dk.betterlectio.android.ui.components.PersonAvatar
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.math.max

// iOS professional timeline: ~1dp per minute, day starts 08:00
private const val REFERENCE_HOUR = 8
private val MinCardHeight = 30.dp
private val TimeGutter = 52.dp

private data class EventLayout(
    val event: ScheduleEvent,
    val column: Int,
    val totalColumns: Int,
    val startMin: Int,
    val endMin: Int,
)

/**
 * iOS ModernTimelineListView-style hour grid with subject-tinted cards,
 * overlap columns, and a red now-line with leading dot.
 */
@Composable
fun TimelineDayView(
    date: LocalDate,
    events: List<ScheduleEvent>,
    displayTitle: (ScheduleEvent) -> String,
    accentFor: (ScheduleEvent) -> Color,
    onEventClick: (ScheduleEvent) -> Unit,
    modifier: Modifier = Modifier,
    dayStartHour: Int = REFERENCE_HOUR,
    dayEndHour: Int = 16,
    minuteHeight: Dp = 1.dp,
) {
    val allDay = events.filter { it.isAllDay }
    val timed = events.filter { !it.isAllDay }
    val dark = isSystemInDarkTheme()
    val neutralBlend = if (dark) Color(0xFF2C2C2E) else Color.White

    val layouts = remember(timed, date, dayStartHour) {
        calculateOverlapLayouts(timed, date, dayStartHour)
    }
    val latestEnd = layouts.maxOfOrNull { it.endMin } ?: ((dayEndHour - dayStartHour) * 60)
    val spanMinutes = max((dayEndHour - dayStartHour) * 60, latestEnd + 40)
    val totalHeight = minuteHeight * spanMinutes
    val scroll = rememberScrollState()
    val now = LocalDateTime.now()
    val showNow = now.toLocalDate() == date

    Column(modifier.fillMaxSize()) {
        if (allDay.isNotEmpty()) {
            AllDayStrip(
                events = allDay,
                displayTitle = displayTitle,
                accentFor = accentFor,
                onEventClick = onEventClick,
            )
        }

        if (timed.isEmpty() && allDay.isEmpty()) {
            EmptyDayState(Modifier.fillMaxSize())
            return@Column
        }

        if (timed.isEmpty()) return@Column

        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(scroll),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(totalHeight + 80.dp)
                    .padding(top = 8.dp),
            ) {
                val maxHour = dayStartHour + (spanMinutes / 60) + 1
                for (hour in dayStartHour..maxHour) {
                    val yMin = (hour - dayStartHour) * 60
                    if (yMin < 0 || yMin > spanMinutes + 60) continue
                    Row(
                        Modifier
                            .offset(y = minuteHeight * yMin - 7.dp)
                            .fillMaxWidth()
                            .height(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "%d:00".format(hour),
                            modifier = Modifier
                                .width(TimeGutter)
                                .padding(end = 6.dp),
                            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                            textAlign = TextAlign.End,
                        )
                        Box(
                            Modifier
                                .weight(1f)
                                .height(1.dp)
                                .background(
                                    MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f),
                                ),
                        )
                    }
                }

                layouts.forEach { layout ->
                    val event = layout.event
                    val top = minuteHeight * layout.startMin
                    val h = (minuteHeight * (layout.endMin - layout.startMin)).coerceAtLeast(MinCardHeight)
                    val widthFraction = 1f / layout.totalColumns
                    val xFraction = layout.column.toFloat() / layout.totalColumns
                    val accent = accentFor(event)
                    val cancelled = event.status == EventStatus.CANCELLED

                    BoxWithConstraints(
                        Modifier
                            .fillMaxWidth()
                            .padding(start = TimeGutter),
                    ) {
                        val contentW = maxWidth * widthFraction
                        val x = maxWidth * xFraction
                        ModernScheduleCard(
                            title = displayTitle(event),
                            room = event.room,
                            teacher = event.teacher,
                            teacherId = event.teacherId,
                            status = event.status,
                            accent = accent,
                            neutralBlend = neutralBlend,
                            dark = dark,
                            showTeacherAvatar = true,
                            modifier = Modifier
                                .offset(x = x + 2.dp, y = top)
                                .width(contentW - 4.dp)
                                .height(h)
                                .clickable { onEventClick(event) }
                                .alpha(if (cancelled) 0.5f else 1f),
                        )
                    }
                }

                if (showNow) {
                    val nowMin = (now.hour * 60 + now.minute) - dayStartHour * 60
                    if (nowMin in 0 until spanMinutes) {
                        val y = minuteHeight * nowMin
                        Row(
                            Modifier
                                .offset(y = y - 3.dp)
                                .fillMaxWidth()
                                .padding(start = TimeGutter - 6.dp)
                                .height(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(
                                Modifier
                                    .size(6.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFFE53935)),
                            )
                            Box(
                                Modifier
                                    .weight(1f)
                                    .height(1.5.dp)
                                    .background(Color(0xFFE53935)),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AllDayStrip(
    events: List<ScheduleEvent>,
    displayTitle: (ScheduleEvent) -> String,
    accentFor: (ScheduleEvent) -> Color,
    onEventClick: (ScheduleEvent) -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            stringResource(R.string.event_all_day),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            events.forEachIndexed { index, ev ->
                val accent = accentFor(ev)
                val cancelled = ev.status == EventStatus.CANCELLED
                Row(
                    modifier = Modifier
                        .then(if (index == events.lastIndex) Modifier.weight(1f) else Modifier)
                        .clip(RoundedCornerShape(10.dp))
                        .background(accent.copy(alpha = 0.18f))
                        .clickable { onEventClick(ev) }
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        subjectIcon(displayTitle(ev)),
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                    )
                    Text(
                        displayTitle(ev),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (cancelled) TextDecoration.LineThrough else null,
                    )
                }
            }
        }
    }
}

@Composable
private fun ModernScheduleCard(
    title: String,
    room: String?,
    teacher: String?,
    status: EventStatus,
    accent: Color,
    neutralBlend: Color,
    dark: Boolean,
    showTeacherAvatar: Boolean = false,
    teacherId: String? = null,
    modifier: Modifier = Modifier,
) {
    val bg = when (status) {
        EventStatus.CANCELLED -> if (dark) Color(0xFF3A3A3C) else Color(0xFFF2F2F7)
        else -> accent.blend(neutralBlend, if (dark) 0.60f else 0.85f)
    }
    val shape = RoundedCornerShape(15.dp)

    Box(modifier.clip(shape).background(bg)) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = 14.dp, end = 12.dp, top = 12.dp, bottom = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textDecoration = if (status == EventStatus.CANCELLED) {
                        TextDecoration.LineThrough
                    } else {
                        null
                    },
                )
                if (showTeacherAvatar && !teacher.isNullOrBlank()) {
                    PersonAvatar(
                        name = teacher,
                        size = 20.dp,
                        teacherNumericId = teacherId,
                        kind = DirectoryEntityKind.TEACHER,
                    )
                    Spacer(Modifier.width(6.dp))
                }
                Icon(
                    subjectIcon(title),
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                )
            }
            val meta = buildList {
                room?.takeIf { it.isNotBlank() }?.let(::add)
                teacher?.takeIf { it.isNotBlank() }?.let { add("· $it") }
            }.joinToString(" ")
            if (meta.isNotBlank()) {
                Text(
                    meta,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Light,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(Modifier.weight(1f, fill = true))
        }

        if (status != EventStatus.NORMAL) {
            Icon(
                imageVector = if (status == EventStatus.CANCELLED) {
                    Icons.Default.Cancel
                } else {
                    Icons.Default.Error
                },
                contentDescription = null,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(14.dp),
                tint = if (status == EventStatus.CANCELLED) {
                    Color(0xFFE53935)
                } else {
                    Color(0xFFFF9800)
                },
            )
        }
    }
}

@Composable
fun EmptyDayState(modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxSize()
            .padding(vertical = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Outlined.CalendarMonth,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
        )
        Spacer(Modifier.height(16.dp))
        Text(
            stringResource(R.string.empty_schedule_day),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun calculateOverlapLayouts(
    timed: List<ScheduleEvent>,
    date: LocalDate,
    dayStartHour: Int,
): List<EventLayout> {
    val minDuration = 29
    // Clamp multi-day ranges to this day's segment so overnight / multi-day
    // events get correct height (not clock-only math across dates).
    val ranges = timed.mapNotNull { event ->
        val segment = ScheduleMultiDay.segmentMinutesOnDay(
            event = event,
            date = date,
            dayStartHour = dayStartHour,
            minDurationMinutes = minDuration,
        )
        if (segment != null) {
            Triple(event, segment.first, segment.second)
        } else {
            // Timed event missing start/end — fall back to a one-hour stub at day start.
            val start = event.start
            val end = event.end
            if (start == null || end == null) {
                Triple(event, 0, minDuration)
            } else {
                null
            }
        }
    }.sortedBy { it.second }

    val columnEndTimes = mutableMapOf<Int, Int>()
    val assignments = mutableListOf<EventLayout>()

    for ((event, startMin, endMin) in ranges) {
        var column = 0
        while ((columnEndTimes[column] ?: 0) > startMin) column++
        columnEndTimes[column] = endMin
        assignments += EventLayout(event, column, 1, startMin, endMin)
    }

    return assignments.map { a ->
        val maxCol = assignments
            .filter { o -> o.startMin < a.endMin && a.startMin < o.endMin }
            .maxOfOrNull { it.column } ?: 0
        a.copy(totalColumns = maxCol + 1)
    }
}

/** Blend this color toward [other] by [fraction] (0 = self, 1 = other). */
fun Color.blend(other: Color, fraction: Float): Color {
    val f = fraction.coerceIn(0f, 1f)
    return Color(
        red = red + (other.red - red) * f,
        green = green + (other.green - green) * f,
        blue = blue + (other.blue - blue) * f,
        alpha = 1f,
    )
}

/**
 * Standard (list) day content — subject-tinted cards stacked vertically.
 */
@Composable
fun StandardDayList(
    events: List<ScheduleEvent>,
    displayTitle: (ScheduleEvent) -> String,
    accentFor: (ScheduleEvent) -> Color,
    onEventClick: (ScheduleEvent) -> Unit,
    modifier: Modifier = Modifier,
) {
    val allDay = events.filter { it.isAllDay }
    val timed = events.filter { !it.isAllDay }
    val dark = isSystemInDarkTheme()
    val neutral = if (dark) Color(0xFF2C2C2E) else Color.White
    val scroll = rememberScrollState()

    if (events.isEmpty()) {
        EmptyDayState(modifier.fillMaxSize())
        return
    }

    Column(
        modifier
            .fillMaxSize()
            .verticalScroll(scroll)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (allDay.isNotEmpty()) {
            AllDayStrip(
                events = allDay,
                displayTitle = displayTitle,
                accentFor = accentFor,
                onEventClick = onEventClick,
            )
        }
        timed.forEach { event ->
            val accent = accentFor(event)
            val cancelled = event.status == EventStatus.CANCELLED
            val bg = when (event.status) {
                EventStatus.CANCELLED -> if (dark) Color(0xFF3A3A3C) else Color(0xFFF2F2F7)
                else -> accent.blend(neutral, if (dark) 0.55f else 0.82f)
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(bg)
                    .clickable { onEventClick(event) }
                    .padding(14.dp)
                    .alpha(if (cancelled) 0.55f else 1f),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    subjectIcon(displayTitle(event)),
                    contentDescription = null,
                    modifier = Modifier.size(22.dp),
                    tint = accent.copy(alpha = 0.85f),
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        displayTitle(event),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (cancelled) TextDecoration.LineThrough else null,
                    )
                    Text(
                        event.timeLabelText(),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                    )
                    val meta = listOfNotNull(event.room, event.teacher).joinToString(" · ")
                    if (meta.isNotBlank()) {
                        Text(
                            meta,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                event.teacher?.takeIf { it.isNotBlank() }?.let { t ->
                    PersonAvatar(
                        name = t,
                        size = 28.dp,
                        teacherNumericId = event.teacherId,
                        kind = DirectoryEntityKind.TEACHER,
                    )
                    Spacer(Modifier.width(8.dp))
                }
                if (event.status != EventStatus.NORMAL) {
                    Icon(
                        if (event.status == EventStatus.CANCELLED) Icons.Default.Cancel else Icons.Default.Error,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = if (event.status == EventStatus.CANCELLED) {
                            Color(0xFFE53935)
                        } else {
                            Color(0xFFFF9800)
                        },
                    )
                }
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}
