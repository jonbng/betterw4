package dk.betterw4.android.ui.screens.homework

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import dk.betterw4.android.R
import dk.betterw4.android.feature.homework.AssessmentCalendarDay
import dk.betterw4.android.feature.homework.AssessmentDisplayMode
import dk.betterw4.android.feature.homework.HomeworkDetailLoader
import dk.betterw4.android.feature.homework.HomeworkItem
import java.time.LocalDate
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListMeta
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.AttachmentRow
import dk.betterw4.android.ui.components.DetailSection
import dk.betterw4.android.ui.components.ErrorBox
import dk.betterw4.android.ui.components.HtmlBody
import dk.betterw4.android.ui.components.ListSkeleton
import dk.betterw4.android.ui.components.SectionHeader
import dk.betterw4.android.ui.components.W4ChromeActions
import dk.betterw4.android.ui.components.isDueUrgent
import dk.betterw4.android.ui.components.relativeDaySectionLabel
import dk.betterw4.android.ui.components.relativeDueLabel

private object HwRoutes {
    const val LIST = "hw_list"
    const val DETAIL = "hw_detail/{id}"
    fun detail(id: String) = "hw_detail/$id"
}

@Composable
fun HomeworkScreen(
    viewModel: HomeworkViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
    onBackToMore: (() -> Unit)? = null,
) {
    val navController = rememberNavController()
    val state by viewModel.state.collectAsStateWithLifecycle()
    @Suppress("UNUSED_VARIABLE")
    val lessonMappings by viewModel.lessonMappings.collectAsStateWithLifecycle()

    LaunchedEffect(state.selected) {
        if (state.selected == null) {
            val route = navController.currentBackStackEntry?.destination?.route
            if (route?.startsWith("hw_detail") == true) {
                navController.popBackStack(HwRoutes.LIST, inclusive = false)
            }
        }
    }

    NavHost(navController = navController, startDestination = HwRoutes.LIST, modifier = Modifier.fillMaxSize()) {
        composable(HwRoutes.LIST) {
            if (onBackToMore != null) {
                BackHandler(onBack = onBackToMore)
            }
            HomeworkListPane(
                viewModel = viewModel,
                scrollToTopToken = scrollToTopToken,
                onBackToMore = onBackToMore,
                onOpen = { item ->
                    viewModel.select(item)
                    navController.navigate(HwRoutes.detail(item.id))
                },
            )
        }
        composable(
            HwRoutes.DETAIL,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) {
            BackHandler {
                viewModel.select(null)
                navController.popBackStack()
            }
            val item = state.selected
            if (item == null) {
                ListSkeleton()
            } else {
                HomeworkDetailPane(
                    item = item,
                    displayTeam = viewModel::displayTeam,
                    onBack = {
                        viewModel.select(null)
                        navController.popBackStack()
                    },
                    onToggleDone = {
                        viewModel.toggleDone(item.id)
                        viewModel.select(null)
                        navController.popBackStack()
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeworkListPane(
    viewModel: HomeworkViewModel,
    scrollToTopToken: Int,
    onBackToMore: (() -> Unit)? = null,
    onOpen: (HomeworkItem) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(scrollToTopToken) {
        if (scrollToTopToken > 0) listState.animateScrollToItem(0)
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_homework)) },
                navigationIcon = {
                    if (onBackToMore != null) {
                        IconButton(onClick = onBackToMore) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = stringResource(R.string.cd_back),
                            )
                        }
                    }
                },
                actions = {
                    if (!state.isShowingCurrentMonth) {
                        TextButton(onClick = viewModel::showCurrentMonth) {
                            Text(
                                stringResource(R.string.schedule_go_to_today),
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                    W4ChromeActions()
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            AssessmentsMonthHeader(
                title = state.monthTitle,
                displayMode = state.displayMode,
                onPrev = { viewModel.shiftMonth(-1) },
                onNext = { viewModel.shiftMonth(1) },
                onDisplayMode = viewModel::setDisplayMode,
            )
            PullToRefreshBox(
                isRefreshing = state.loading && state.items.isNotEmpty(),
                onRefresh = { viewModel.refresh(true) },
                modifier = Modifier.fillMaxSize(),
            ) {
                when {
                    state.loading && state.items.isEmpty() && state.error == null -> ListSkeleton()
                    state.error != null && state.items.isEmpty() ->
                        ErrorBox(state.error, onRetry = { viewModel.refresh(true) })
                    else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                        if (state.displayMode == AssessmentDisplayMode.MONTH) {
                            item(key = "calendar") {
                                AssessmentsCalendarGrid(
                                    days = state.calendarDays,
                                    selectedDay = state.selectedDay,
                                    onSelect = { day ->
                                        viewModel.selectDay(day)
                                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    },
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                )
                            }
                        }
                        state.selectedDay?.let { day ->
                            item(key = "day-filter-$day") {
                                FilterChip(
                                    selected = true,
                                    onClick = { viewModel.selectDay(null) },
                                    label = { Text(relativeDaySectionLabel(day)) },
                                    trailingIcon = {
                                        Icon(
                                            Icons.Default.Close,
                                            contentDescription = stringResource(R.string.assessments_clear_day_filter),
                                            modifier = Modifier.size(16.dp),
                                        )
                                    },
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                                )
                            }
                        }
                        if (state.groups.isEmpty()) {
                            item(key = "empty") {
                                Column(
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 32.dp, vertical = 36.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                ) {
                                    Text(
                                        if (state.selectedDay != null) {
                                            stringResource(R.string.assessments_empty_day)
                                        } else {
                                            stringResource(R.string.assessments_empty_month)
                                        },
                                        style = MaterialTheme.typography.titleMedium,
                                        textAlign = TextAlign.Center,
                                    )
                                    Spacer(Modifier.height(8.dp))
                                    Text(
                                        if (state.selectedDay != null) {
                                            stringResource(R.string.assessments_empty_day_hint)
                                        } else {
                                            stringResource(R.string.assessments_empty_month_hint, state.monthTitle)
                                        },
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        textAlign = TextAlign.Center,
                                    )
                                }
                            }
                        } else {
                            state.groups.forEach { group ->
                                item(key = "header-${group.date ?: "none"}-${group.label}") {
                                    SectionHeader(relativeDaySectionLabel(group.date))
                                }
                                items(group.items, key = { it.id }) { item ->
                                    SwipeableHomeworkRow(
                                        item = item,
                                        displayTeam = viewModel::displayTeam,
                                        onOpen = { onOpen(item) },
                                        onToggleDone = {
                                            viewModel.toggleDone(item.id)
                                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        },
                                    )
                                    AppListDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AssessmentsMonthHeader(
    title: String,
    displayMode: AssessmentDisplayMode,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onDisplayMode: (AssessmentDisplayMode) -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onPrev) {
                Icon(
                    Icons.Default.ChevronLeft,
                    contentDescription = stringResource(R.string.assessments_prev_month),
                )
            }
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
            )
            IconButton(onClick = onNext) {
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = stringResource(R.string.assessments_next_month),
                )
            }
        }
        val modes = AssessmentDisplayMode.entries
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            modes.forEachIndexed { index, mode ->
                SegmentedButton(
                    selected = displayMode == mode,
                    onClick = { onDisplayMode(mode) },
                    shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                    label = {
                        Text(
                            if (mode == AssessmentDisplayMode.MONTH) {
                                stringResource(R.string.assessments_view_month)
                            } else {
                                stringResource(R.string.assessments_view_list)
                            },
                        )
                    },
                )
            }
        }
    }
}

@Composable
private fun AssessmentsCalendarGrid(
    days: List<AssessmentCalendarDay>,
    selectedDay: LocalDate?,
    onSelect: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
) {
    val weekdays = listOf("M", "T", "W", "T", "F", "S", "S")
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth()) {
                weekdays.forEach { label ->
                    Text(
                        label,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            days.chunked(7).forEach { week ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    week.forEach { day ->
                        val selected = selectedDay == day.date
                        val bg = if (selected) MaterialTheme.colorScheme.primary else Color.Transparent
                        val fg = when {
                            selected -> MaterialTheme.colorScheme.onPrimary
                            day.isInMonth -> MaterialTheme.colorScheme.onSurface
                            else -> MaterialTheme.colorScheme.onSurfaceVariant
                        }
                        val dot = when {
                            !day.hasItems -> Color.Transparent
                            selected -> MaterialTheme.colorScheme.onPrimary
                            day.overdue > 0 -> MaterialTheme.colorScheme.error
                            day.pending > 0 -> MaterialTheme.colorScheme.primary
                            else -> Color(0xFF16A34A)
                        }
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .height(40.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .background(bg)
                                .then(
                                    if (day.isInMonth) {
                                        Modifier.clickable { onSelect(day.date) }
                                    } else {
                                        Modifier
                                    },
                                ),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Text(
                                day.dayNumber.toString(),
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = if (day.isToday) FontWeight.Bold else FontWeight.Normal,
                                color = fg.copy(alpha = if (day.isInMonth) 1f else 0.28f),
                            )
                            Box(
                                Modifier
                                    .padding(top = 2.dp)
                                    .size(5.dp)
                                    .clip(CircleShape)
                                    .background(dot),
                            )
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeableHomeworkRow(
    item: HomeworkItem,
    displayTeam: (String) -> String = { it },
    onOpen: () -> Unit,
    onToggleDone: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.EndToStart,
                SwipeToDismissBoxValue.StartToEnd,
                -> {
                    onToggleDone()
                    false
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val done = item.done
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        if (done) {
                            MaterialTheme.colorScheme.surfaceVariant
                        } else {
                            MaterialTheme.colorScheme.primaryContainer
                        },
                    )
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Default.Check,
                        contentDescription = null,
                        tint = if (done) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        },
                    )
                    Text(
                        if (done) {
                            stringResource(R.string.homework_swipe_undo)
                        } else {
                            stringResource(R.string.homework_swipe_done)
                        },
                        color = if (done) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            MaterialTheme.colorScheme.onPrimaryContainer
                        },
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        },
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = true,
    ) {
        val dueLabel = relativeDueLabel(item.date)
        val urgent = !item.done && isDueUrgent(item.date)
        AppListRow(
            onClick = onOpen,
            modifier = Modifier.background(MaterialTheme.colorScheme.surface),
            leading = {
                Checkbox(
                    checked = item.done,
                    onCheckedChange = { onToggleDone() },
                )
            },
            trailing = {
                if (dueLabel != null) {
                    AppListMeta(
                        text = dueLabel,
                        color = if (urgent) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                }
            },
        ) {
            Text(
                item.activityTitle,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (item.done) FontWeight.Normal else FontWeight.Medium,
                color = if (item.done) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                textDecoration = if (item.done) TextDecoration.LineThrough else null,
                maxLines = 2,
            )
            if (item.note.isNotBlank()) {
                AppListSecondary(item.note, maxLines = 2)
            }
            if (item.team.isNotBlank()) {
                AppListMeta(displayTeam(item.team))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeworkDetailPane(
    item: HomeworkItem,
    displayTeam: (String) -> String = { it },
    onBack: () -> Unit,
    onToggleDone: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val snackbarHostState = remember { SnackbarHostState() }
    val linkedTasks = item.tasks.filter { !it.url.isNullOrBlank() }
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(item.activityTitle, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        ColumnScroll(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
        ) {
            relativeDueLabel(item.date)?.let { due ->
                Text(
                    due,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (isDueUrgent(item.date) && !item.done) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                )
                Spacer(Modifier.height(8.dp))
            }
            if (item.team.isNotBlank()) {
                Text(displayTeam(item.team), style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(12.dp))
            }
            DetailSection(stringResource(R.string.label_homework)) {
                Text(
                    item.note.ifBlank { stringResource(R.string.homework_no_note) },
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
            item.detailHtml?.let { html ->
                DetailSection(stringResource(R.string.homework_lesson_content)) {
                    HomeworkDetailContent(
                        html = html,
                        itemId = item.id,
                        title = item.activityTitle,
                        snackbarHostState = snackbarHostState,
                    )
                }
            }
            if (linkedTasks.isNotEmpty()) {
                DetailSection(stringResource(R.string.homework_links)) {
                    linkedTasks.forEach { task ->
                        AttachmentRow(
                            name = task.text.ifBlank { task.url.orEmpty() },
                            url = task.url.orEmpty(),
                            isFileHint = false,
                            snackbarHostState = snackbarHostState,
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(
                    checked = item.done,
                    onCheckedChange = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        onToggleDone()
                    },
                )
                Text(
                    if (item.done) {
                        stringResource(R.string.homework_done)
                    } else {
                        stringResource(R.string.homework_mark_done)
                    },
                )
            }
        }
    }
}

@Composable
private fun ColumnScroll(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()),
        content = { content() },
    )
}

/**
 * Render homework HTML with the authenticated W4 session (inline images via Coil).
 */
@Composable
private fun HomeworkDetailContent(
    html: String,
    @Suppress("UNUSED_PARAMETER") itemId: String,
    @Suppress("UNUSED_PARAMETER") title: String,
    @Suppress("UNUSED_PARAMETER") snackbarHostState: SnackbarHostState,
) {
    val segmentsEmpty = remember(html) {
        dk.betterw4.android.feature.content.HtmlSegments.parse(html).isEmpty()
    }
    if (segmentsEmpty) {
        val plain = remember(html) { HomeworkDetailLoader.plainTextFromHtml(html) }
        if (plain.isNotBlank()) {
            Text(plain, style = MaterialTheme.typography.bodyMedium)
        }
    } else {
        HtmlBody(html = html)
    }
}
