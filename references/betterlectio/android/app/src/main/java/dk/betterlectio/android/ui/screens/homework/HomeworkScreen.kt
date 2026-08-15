package dk.betterlectio.android.ui.screens.homework

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.homework.HomeworkDetailLoader
import dk.betterlectio.android.feature.homework.HomeworkItem
import dk.betterlectio.android.feature.schedule.LessonDetailParser
import dk.betterlectio.android.ui.components.AppListDivider
import dk.betterlectio.android.ui.components.AppListMeta
import dk.betterlectio.android.ui.components.AppListRow
import dk.betterlectio.android.ui.components.AppListSecondary
import dk.betterlectio.android.ui.components.AttachmentRow
import dk.betterlectio.android.ui.components.DetailSection
import dk.betterlectio.android.ui.components.EmptyBox
import dk.betterlectio.android.ui.components.ErrorBox
import dk.betterlectio.android.ui.components.LectioHtmlBody
import dk.betterlectio.android.ui.components.LessonContentBlocks
import dk.betterlectio.android.ui.components.ListSkeleton
import dk.betterlectio.android.ui.components.SectionHeader
import dk.betterlectio.android.ui.components.isDueUrgent
import dk.betterlectio.android.ui.components.relativeDaySectionLabel
import dk.betterlectio.android.ui.components.relativeDueLabel

private object HwRoutes {
    const val LIST = "hw_list"
    const val DETAIL = "hw_detail/{id}"
    fun detail(id: String) = "hw_detail/$id"
}

@Composable
fun HomeworkScreen(
    viewModel: HomeworkViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
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
            HomeworkListPane(
                viewModel = viewModel,
                scrollToTopToken = scrollToTopToken,
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
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.loading && state.items.isNotEmpty(),
            onRefresh = { viewModel.refresh(true) },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.loading && state.items.isEmpty() -> ListSkeleton()
                state.error != null && state.items.isEmpty() ->
                    ErrorBox(state.error, onRetry = { viewModel.refresh(true) })
                state.items.isEmpty() -> EmptyBox(
                    text = stringResource(R.string.empty_homework_all_clear),
                    description = stringResource(R.string.empty_homework_all_clear_hint),
                    icon = Icons.Default.CheckCircle,
                )
                else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
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
 * Prefer structured lesson parsing (activity pages with images/blocks); fall back to
 * fragment HTML rendering so inline images still load with the Lectio session.
 */
@Composable
private fun HomeworkDetailContent(
    html: String,
    itemId: String,
    title: String,
    snackbarHostState: SnackbarHostState,
) {
    val looksLikeActivityPage = remember(html) {
        html.contains("inlineHomework", ignoreCase = true) ||
            html.contains("homeworkContentContainer", ignoreCase = true) ||
            html.contains("ls-paper", ignoreCase = true) ||
            html.contains("tocAndToolbar", ignoreCase = true)
    }
    val lessonDetail = remember(html, itemId, title, looksLikeActivityPage) {
        if (!looksLikeActivityPage) null
        else LessonDetailParser.parse(html, itemId, title).takeIf { it.contentBlocks.isNotEmpty() }
    }
    when {
        lessonDetail != null -> {
            lessonDetail.note?.takeIf { it.isNotBlank() }?.let { note ->
                Text(note, style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(8.dp))
            }
            LessonContentBlocks(lessonDetail.contentBlocks)
            if (lessonDetail.resources.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                lessonDetail.resources.forEach { r ->
                    AttachmentRow(
                        name = r.title,
                        url = r.url,
                        isFileHint = r.isFile,
                        snackbarHostState = snackbarHostState,
                    )
                }
            }
        }
        else -> {
            val segmentsEmpty = remember(html) {
                dk.betterlectio.android.feature.content.LectioHtmlSegments.parse(html).isEmpty()
            }
            if (segmentsEmpty) {
                val plain = remember(html) { HomeworkDetailLoader.plainTextFromHtml(html) }
                if (plain.isNotBlank()) {
                    Text(plain, style = MaterialTheme.typography.bodyMedium)
                }
            } else {
                LectioHtmlBody(html = html)
            }
        }
    }
}
