package dk.betterlectio.android.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.distinctUntilChanged
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

data class DateStripDay(
    val date: LocalDate,
    val hasEvents: Boolean = false,
)

private const val TOTAL_WEEKS = 104
private const val CENTER_WEEK_INDEX = 52

/**
 * Compact calendar week strip:
 * - Full-width week, swipe between weeks
 * - Selected day: primary tab (top corners only — sits flush with content)
 * - Days with events: full-strength text + subtle neutral wash
 * - Empty days: muted text, no fill
 * - Today (unselected): primary text
 */
@Composable
fun DateStrip(
    days: List<DateStripDay>,
    selected: LocalDate,
    onSelect: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
    locale: Locale = Locale.getDefault(),
    onWeekChanged: ((LocalDate) -> Unit)? = null,
    hasEvents: ((LocalDate) -> Boolean)? = null,
) {
    val hasEventsLookup by rememberUpdatedState(
        hasEvents ?: { date -> days.find { it.date == date }?.hasEvents == true },
    )
    val onSelectState by rememberUpdatedState(onSelect)
    val onWeekChangedState by rememberUpdatedState(onWeekChanged)
    val selectedState by rememberUpdatedState(selected)

    val anchorMonday = remember {
        selected.with(DayOfWeek.MONDAY)
    }

    fun weekStartForIndex(index: Int): LocalDate =
        anchorMonday.plusWeeks((index - CENTER_WEEK_INDEX).toLong())

    fun indexForDate(date: LocalDate): Int {
        val monday = date.with(DayOfWeek.MONDAY)
        val weeks = ChronoUnit.WEEKS.between(anchorMonday, monday).toInt()
        return (CENTER_WEEK_INDEX + weeks).coerceIn(0, TOTAL_WEEKS - 1)
    }

    val pagerState = rememberPagerState(
        initialPage = indexForDate(selected),
        pageCount = { TOTAL_WEEKS },
    )

    // Programmatic snaps (day swipe / today) should not emit week-changed callbacks.
    val ignoreWeekCallback = remember { AtomicBoolean(false) }

    // External selection → snap week strip. Don't skip when a previous scroll is mid-flight
    // (rapid day taps used to leave the strip on the wrong week).
    LaunchedEffect(selected) {
        val target = indexForDate(selected)
        if (pagerState.settledPage == target && pagerState.currentPage == target) {
            return@LaunchedEffect
        }
        // User is week-swiping toward this week already — let them finish.
        if (pagerState.isScrollInProgress && pagerState.targetPage == target) {
            return@LaunchedEffect
        }
        // User is week-swiping elsewhere — don't fight the gesture.
        if (pagerState.isScrollInProgress && !ignoreWeekCallback.get()) {
            return@LaunchedEffect
        }
        ignoreWeekCallback.set(true)
        try {
            pagerState.scrollToPage(target)
        } finally {
            ignoreWeekCallback.set(false)
        }
    }

    // Only propagate week changes that come from the user swiping this strip.
    LaunchedEffect(pagerState) {
        var userInitiatedScroll = false
        snapshotFlow { pagerState.isScrollInProgress }
            .distinctUntilChanged()
            .collect { scrolling ->
                if (scrolling) {
                    if (!ignoreWeekCallback.get()) {
                        userInitiatedScroll = true
                    }
                    return@collect
                }
                if (!userInitiatedScroll) return@collect
                userInitiatedScroll = false

                val newWeekStart = weekStartForIndex(pagerState.settledPage)
                val currentWeekStart = selectedState.with(DayOfWeek.MONDAY)
                if (newWeekStart == currentWeekStart) return@collect
                val dayOffset =
                    (selectedState.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
                val targetDate = newWeekStart.plusDays(dayOffset.toLong())
                onWeekChangedState?.invoke(targetDate) ?: onSelectState(targetDate)
            }
    }

    val haptics = LocalHapticFeedback.current
    var lastHapticDate by remember { mutableStateOf(selected) }
    LaunchedEffect(selected) {
        if (selected != lastHapticDate) {
            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            lastHapticDate = selected
        }
    }

    HorizontalPager(
        state = pagerState,
        modifier = modifier
            .fillMaxWidth()
            .height(62.dp),
        beyondViewportPageCount = 1,
    ) { page ->
        WeekRow(
            weekStart = weekStartForIndex(page),
            selected = selected,
            locale = locale,
            hasEvents = hasEventsLookup,
            onSelect = onSelectState,
        )
    }
}

@Composable
private fun WeekRow(
    weekStart: LocalDate,
    selected: LocalDate,
    locale: Locale,
    hasEvents: (LocalDate) -> Boolean,
    onSelect: (LocalDate) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        for (i in 0 until 7) {
            val date = weekStart.plusDays(i.toLong())
            DayCell(
                date = date,
                selected = date == selected,
                isToday = date == LocalDate.now(),
                hasEvents = hasEvents(date),
                locale = locale,
                onClick = { onSelect(date) },
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
            )
        }
    }
}

@Composable
private fun DayCell(
    date: LocalDate,
    selected: Boolean,
    isToday: Boolean,
    hasEvents: Boolean,
    locale: Locale,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.94f else 1f,
        animationSpec = tween(140),
        label = "dayScale",
    )

    val dayNumber = date.dayOfMonth.toString()
    val dayName = date.dayOfWeek
        .getDisplayName(TextStyle.SHORT, locale)
        .replace(".", "")
        .take(2)
        .replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }

    val primary = MaterialTheme.colorScheme.primary
    val onPrimary = MaterialTheme.colorScheme.onPrimary
    val onSurface = MaterialTheme.colorScheme.onSurface
    val onSurfaceVariant = MaterialTheme.colorScheme.onSurfaceVariant
    val surfaceVariant = MaterialTheme.colorScheme.surfaceVariant

    // Tab shape: rounded top only so the selection reads as connected to content below.
    val shape = RoundedCornerShape(topStart = 10.dp, topEnd = 10.dp)

    val backgroundColor: Color = when {
        selected -> primary
        // Neutral wash — not primary — so busy days read clearly without looking “selected”
        hasEvents -> surfaceVariant.copy(alpha = 0.55f)
        else -> Color.Transparent
    }

    val numberColor: Color = when {
        selected -> onPrimary
        isToday -> primary
        hasEvents -> onSurface
        else -> onSurfaceVariant.copy(alpha = 0.40f)
    }

    val labelColor: Color = when {
        selected -> onPrimary.copy(alpha = 0.90f)
        isToday -> primary.copy(alpha = 0.85f)
        hasEvents -> onSurfaceVariant
        else -> onSurfaceVariant.copy(alpha = 0.35f)
    }

    Column(
        modifier = modifier
            .scale(scale)
            .clip(shape)
            .background(backgroundColor)
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick,
            )
            .padding(top = 9.dp, bottom = 7.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
    ) {
        Text(
            text = dayNumber,
            fontSize = 18.sp,
            fontWeight = if (selected || isToday || hasEvents) FontWeight.SemiBold else FontWeight.Medium,
            color = numberColor,
            maxLines = 1,
        )
        Text(
            text = dayName,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = labelColor,
            maxLines = 1,
        )
    }
}
