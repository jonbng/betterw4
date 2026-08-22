package dk.betterw4.android.ui.screens.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
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
import dk.betterw4.android.R
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.CustomEvents
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleMultiDay
import dk.betterw4.android.feature.schedule.SchoolCalendar
import dk.betterw4.android.feature.schedule.timeLabelText
import dk.betterw4.android.ui.components.LeadingAccentBar
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.theme.scheduleWash
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.math.max

// iOS professional timeline: ~1dp per minute, day starts 08:00
private const val REFERENCE_HOUR = 8
/** Isolated shorts may grow this many minutes; adjacent blocks keep their real duration. */
private const val MIN_VISUAL_MINUTES = 30
private val TimeGutter = 52.dp

internal data class EventLayout(
    val event: ScheduleEvent,
    val column: Int,
    val totalColumns: Int,
    val startMin: Int,
    val endMin: Int,
)

internal data class CardPlacement(
    val xFraction: Float,
    val widthFraction: Float,
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
    onAddAt: ((LocalDateTime) -> Unit)? = null,
    modifier: Modifier = Modifier,
    dayStartHour: Int = REFERENCE_HOUR,
    dayEndHour: Int = 16,
    minuteHeight: Dp = 1.dp,
    now: LocalDateTime? = null,
) {
    val allDay = events.filter { it.isAllDay }
    val timed = events.filter { !it.isAllDay }

    val layouts = remember(timed, date, dayStartHour) {
        calculateOverlapLayouts(timed, date, dayStartHour)
    }
    val latestEnd = layouts.maxOfOrNull { visualEndMin(it, layouts) }
        ?: ((dayEndHour - dayStartHour) * 60)
    val spanMinutes = max((dayEndHour - dayStartHour) * 60, latestEnd + 40)
    val totalHeight = minuteHeight * spanMinutes
    val scroll = rememberScrollState()
    val clock = now ?: rememberW4Now()
    val nowMinutes = ScheduleNowLine.minutesFromOrigin(
        now = clock,
        date = date,
        originHour = dayStartHour,
        spanMinutes = spanMinutes,
    )

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
            EmptyDayState(
                Modifier.fillMaxSize(),
                onAdd = onAddAt?.let { add -> { add(CustomEvents.defaultStart(date, clock)) } },
            )
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
                val density = LocalDensity.current
                val addAt = onAddAt
                if (addAt != null) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .pointerInput(date, dayStartHour, minuteHeight) {
                                detectTapGestures { offset ->
                                    val pxPerMinute = with(density) { minuteHeight.toPx() }
                                    if (pxPerMinute <= 0f) return@detectTapGestures
                                    val raw = (offset.y / pxPerMinute).toInt()
                                    val snapped = ((raw + 7) / 15) * 15
                                    val minutes = snapped.coerceIn(0, spanMinutes)
                                    addAt(date.atTime(dayStartHour, 0).plusMinutes(minutes.toLong()))
                                }
                            },
                    )
                }
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    val laneWidth = maxWidth - TimeGutter
                    val maxHour = dayStartHour + (spanMinutes / 60) + 1
                    for (hour in dayStartHour..maxHour) {
                        val yMin = (hour - dayStartHour) * 60
                        if (yMin < 0 || yMin > spanMinutes + 60) continue
                        Row(
                            Modifier
                                .zIndex(0f)
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
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
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

                    // Cancelled leftovers paint first so live/changed cards stay opaque,
                    // rounded, and above the hour grid.
                    val painted = layouts.sortedBy { layout ->
                        if (layout.event.status == EventStatus.CANCELLED) 0 else 1
                    }
                    painted.forEach { layout ->
                        val event = layout.event
                        val top = minuteHeight * layout.startMin
                        val visualMinutes = (visualEndMin(layout, layouts) - layout.startMin)
                            .coerceAtLeast(1)
                        val h = minuteHeight * visualMinutes
                        val placement = overlapPlacement(layout, layouts)
                        val cancelled = event.status == EventStatus.CANCELLED
                        ModernScheduleCard(
                            title = displayTitle(event),
                            room = event.room,
                            teacher = event.teacher,
                            teacherId = event.teacherId,
                            status = event.status,
                            accent = accentFor(event),
                            compact = h < 28.dp,
                            showTeacherAvatar = h >= 28.dp,
                            isSchoolCalendar = SchoolCalendar.isSchoolCalendarEvent(event),
                            onClick = { onEventClick(event) },
                            modifier = Modifier
                                .zIndex(if (cancelled) 1f else 2f)
                                .offset(
                                    x = TimeGutter + laneWidth * placement.xFraction + 2.dp,
                                    y = top,
                                )
                                .width(
                                    (laneWidth * placement.widthFraction - 4.dp)
                                        .coerceAtLeast(24.dp),
                                )
                                .height(h),
                        )
                    }

                    if (nowMinutes != null) {
                        val y = minuteHeight * nowMinutes
                        Row(
                            Modifier
                                .zIndex(3f)
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
    val scheme = MaterialTheme.colorScheme
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
                        .background(
                            if (cancelled) {
                                scheme.surfaceVariant
                            } else {
                                scheme.surfaceContainerLow.scheduleWash(accent)
                            },
                        )
                        .clickable { onEventClick(ev) }
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        Modifier
                            .width(3.dp)
                            .height(16.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(if (cancelled) Color.Transparent else accent),
                    )
                    Text(
                        displayTitle(ev),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
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
    onClick: () -> Unit,
    compact: Boolean = false,
    showTeacherAvatar: Boolean = false,
    teacherId: String? = null,
    isSchoolCalendar: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val cancelled = status == EventStatus.CANCELLED
    val scheme = MaterialTheme.colorScheme
    val bg = if (cancelled) {
        scheme.surfaceVariant
    } else {
        scheme.surfaceContainerLow.scheduleWash(accent)
    }
    val titleColor = scheme.onSurface.copy(alpha = if (cancelled) 0.55f else 1f)
    val metaColor = scheme.onSurfaceVariant
    val shape = RoundedCornerShape(if (compact) 10.dp else 15.dp)

    Box(
        modifier
            .clip(shape)
            .background(bg)
            .clickable(onClick = onClick),
    ) {
        Row(Modifier.fillMaxSize()) {
            Box(
                Modifier
                    .padding(
                        start = 6.dp,
                        top = if (compact) 4.dp else 10.dp,
                        bottom = if (compact) 4.dp else 10.dp,
                    )
                    .width(3.dp)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(2.dp))
                    .background(if (cancelled) Color.Transparent else accent),
            )
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .padding(
                        start = 10.dp,
                        end = if (compact) 8.dp else 12.dp,
                        top = if (compact) 2.dp else 12.dp,
                        bottom = if (compact) 2.dp else 4.dp,
                    ),
                verticalArrangement = Arrangement.spacedBy(if (compact) 0.dp else 4.dp),
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        title,
                        modifier = Modifier.weight(1f),
                        style = if (compact) {
                            MaterialTheme.typography.labelMedium.copy(fontSize = 12.sp)
                        } else {
                            MaterialTheme.typography.bodyMedium
                        },
                        fontWeight = FontWeight.SemiBold,
                        color = titleColor,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (cancelled) TextDecoration.LineThrough else null,
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
                    if (!compact) {
                        Icon(
                            if (isSchoolCalendar) {
                                Icons.Outlined.CalendarMonth
                            } else {
                                subjectIcon(title)
                            },
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = if (cancelled) metaColor else accent.copy(alpha = 0.8f),
                        )
                    }
                }
                val meta = buildList {
                    room?.takeIf { it.isNotBlank() }?.let(::add)
                    teacher?.takeIf { it.isNotBlank() }?.let { add("· $it") }
                }.joinToString(" ")
                if (!compact && meta.isNotBlank()) {
                    Text(
                        meta,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium,
                        color = metaColor,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (cancelled) TextDecoration.LineThrough else null,
                    )
                }
                if (!compact) {
                    Spacer(Modifier.weight(1f, fill = true))
                }
            }
        }

        if (!compact && status != EventStatus.NORMAL) {
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
fun EmptyDayState(
    modifier: Modifier = Modifier,
    message: String? = null,
    onAdd: (() -> Unit)? = null,
) {
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
            message ?: stringResource(R.string.empty_schedule_day),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (onAdd != null) {
            Text(
                stringResource(R.string.private_event_tap_gap),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
            )
            Spacer(Modifier.height(4.dp))
            TextButton(onClick = onAdd) {
                Text(stringResource(R.string.private_event_add_short))
            }
        }
    }
}

internal fun calculateOverlapLayouts(
    timed: List<ScheduleEvent>,
    date: LocalDate,
    dayStartHour: Int,
): List<EventLayout> {
    // Clamp multi-day ranges to this day's segment so overnight / multi-day
    // events get correct height (not clock-only math across dates).
    //
    // Use the real clock range for columns. A 15-minute break that only
    // *touches* the next lesson is not an overlap — stretching it to a
    // min-height here is what used to shove it into a side lane.
    val ranges = timed.mapNotNull { event ->
        val segment = ScheduleMultiDay.segmentMinutesOnDay(
            event = event,
            date = date,
            dayStartHour = dayStartHour,
            minDurationMinutes = 0,
        )
        if (segment != null) {
            val end = max(segment.first + 1, segment.second)
            Triple(event, segment.first, end)
        } else {
            // Timed event missing start/end — fall back to a one-minute stub at day start.
            val start = event.start
            val end = event.end
            if (start == null || end == null) {
                Triple(event, 0, 1)
            } else {
                null
            }
        }
    }.sortedWith(compareBy({ it.second }, { it.first.id }))

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

/**
 * Minutes from the day origin at which this card should stop painting.
 *
 * Isolated shorts grow to [MIN_VISUAL_MINUTES] so a lone 10-minute block is
 * still tappable. If another event starts at or after this one's real end,
 * the card is clipped there — otherwise a 15-minute break between two
 * lessons would paint over the next module.
 */
internal fun visualEndMin(
    layout: EventLayout,
    layouts: List<EventLayout>,
    minVisualMinutes: Int = MIN_VISUAL_MINUTES,
): Int {
    val grown = max(layout.endMin, layout.startMin + minVisualMinutes)
    val nextStart = layouts
        .asSequence()
        .filter { it.event.id != layout.event.id && it.startMin >= layout.endMin }
        .minOfOrNull { it.startMin }
    val capped = if (nextStart != null) minOf(grown, nextStart) else grown
    return max(layout.startMin + 1, capped)
}

/**
 * Place overlapping cards. When a cancelled leftover shares a slot with a
 * live/changed lesson, keep the leftover visible as a narrow trailing strip
 * instead of a 50/50 split that mutes the real module.
 */
internal fun overlapPlacement(
    layout: EventLayout,
    layouts: List<EventLayout>,
): CardPlacement {
    val cluster = layouts.filter { other ->
        other.startMin < layout.endMin && layout.startMin < other.endMin
    }
    val live = cluster
        .filter {
            it.event.status != EventStatus.CANCELLED &&
                !SchoolCalendar.isSchoolCalendarEvent(it.event)
        }
        .sortedWith(compareBy<EventLayout> { it.column }.thenBy { it.event.id })
    val leftover = cluster
        .filter {
            it.event.status == EventStatus.CANCELLED ||
                SchoolCalendar.isSchoolCalendarEvent(it.event)
        }
        .sortedWith(
            compareBy<EventLayout> { SchoolCalendar.isSchoolCalendarEvent(it.event) }
                .thenBy { it.column }
                .thenBy { it.event.id },
        )

    if (live.isNotEmpty() && leftover.isNotEmpty()) {
        val liveShare = 0.70f
        val leftoverShare = 0.30f
        if (layout.event.status == EventStatus.CANCELLED ||
            SchoolCalendar.isSchoolCalendarEvent(layout.event)
        ) {
            val index = leftover.indexOfFirst { it.event.id == layout.event.id }.coerceAtLeast(0)
            val count = leftover.size
            return CardPlacement(
                xFraction = liveShare + leftoverShare * index / count,
                widthFraction = leftoverShare / count,
            )
        }
        val index = live.indexOfFirst { it.event.id == layout.event.id }.coerceAtLeast(0)
        val count = live.size
        return CardPlacement(
            xFraction = liveShare * index / count,
            widthFraction = liveShare / count,
        )
    }

    val columns = layout.totalColumns.coerceAtLeast(1)
    return CardPlacement(
        xFraction = layout.column.toFloat() / columns,
        widthFraction = 1f / columns,
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
    onAdd: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val allDay = events.filter { it.isAllDay }
    val timed = events.filter { !it.isAllDay }
    val scheme = MaterialTheme.colorScheme
    val scroll = rememberScrollState()

    if (events.isEmpty()) {
        EmptyDayState(modifier.fillMaxSize(), onAdd = onAdd)
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
            val bg = if (cancelled) {
                scheme.surfaceVariant
            } else {
                scheme.surfaceContainerLow.scheduleWash(accent)
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
                LeadingAccentBar(if (cancelled) Color.Transparent else accent)
                Spacer(Modifier.width(10.dp))
                Icon(
                    subjectIcon(event, displayTitle(event)),
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
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textDecoration = if (cancelled) TextDecoration.LineThrough else null,
                    )
                    Text(
                        event.timeLabelText(),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    val meta = listOfNotNull(event.room, event.teacher).joinToString(" · ")
                    if (meta.isNotBlank()) {
                        Text(
                            meta,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
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
