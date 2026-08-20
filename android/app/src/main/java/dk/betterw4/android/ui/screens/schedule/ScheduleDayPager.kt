package dk.betterw4.android.ui.screens.schedule

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import dk.betterw4.android.core.w4.W4Dates
import kotlinx.coroutines.flow.distinctUntilChanged
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Large day index space so users can swipe across many weeks. */
private const val DAY_CENTER_PAGE = 5000

/**
 * Horizontal day pager shared by own schedule and other-person / room schedules.
 * Keeps strip taps and swipe selection in sync without fighting each other.
 */
@Composable
fun ScheduleDayPager(
    selectedDate: LocalDate,
    onSelectDate: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable (date: LocalDate) -> Unit,
) {
    val dayAnchor = remember { W4Dates.today() }

    fun dateForPage(page: Int): LocalDate =
        dayAnchor.plusDays((page - DAY_CENTER_PAGE).toLong())

    fun pageForDate(date: LocalDate): Int =
        DAY_CENTER_PAGE + ChronoUnit.DAYS.between(dayAnchor, date).toInt()

    val dayPagerState = rememberPagerState(
        initialPage = pageForDate(selectedDate),
        pageCount = { DAY_CENTER_PAGE * 2 },
    )

    val selectDate by rememberUpdatedState(onSelectDate)
    val currentSelected by rememberUpdatedState(selectedDate)
    val ignoreDayPagerSync = remember { AtomicBoolean(false) }

    // User day-swipe → selection. Prefer targetPage while scrolling so flings
    // don't stampede through intermediate days.
    LaunchedEffect(dayPagerState) {
        snapshotFlow {
            val scrolling = dayPagerState.isScrollInProgress
            val page = if (scrolling) dayPagerState.targetPage else dayPagerState.settledPage
            page to scrolling
        }
            .distinctUntilChanged()
            .collect { (page, _) ->
                if (ignoreDayPagerSync.get()) return@collect
                val date = dateForPage(page)
                if (date != currentSelected) {
                    selectDate(date)
                }
            }
    }

    // Strip tap / today / week change → snap pager to match.
    LaunchedEffect(selectedDate) {
        val target = pageForDate(selectedDate)
        if (dayPagerState.settledPage == target && dayPagerState.currentPage == target) {
            return@LaunchedEffect
        }
        if (dayPagerState.isScrollInProgress && dayPagerState.targetPage == target) {
            return@LaunchedEffect
        }
        ignoreDayPagerSync.set(true)
        try {
            dayPagerState.scrollToPage(target)
        } finally {
            ignoreDayPagerSync.set(false)
        }
    }

    HorizontalPager(
        state = dayPagerState,
        modifier = modifier.fillMaxSize(),
        beyondViewportPageCount = 1,
        key = { page -> dateForPage(page).toString() },
    ) { page ->
        content(dateForPage(page))
    }
}
