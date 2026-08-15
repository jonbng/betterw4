package dk.betterlectio.android.ui.screens.assignments

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Assignment
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.assignments.AssignmentDetail
import dk.betterlectio.android.feature.assignments.AssignmentFilter
import dk.betterlectio.android.feature.assignments.AssignmentItem
import dk.betterlectio.android.ui.components.AppListDivider
import dk.betterlectio.android.ui.components.AppListMeta
import dk.betterlectio.android.ui.components.AttachmentRow
import dk.betterlectio.android.ui.components.AppListPrimary
import dk.betterlectio.android.ui.components.AppListRow
import dk.betterlectio.android.ui.components.AppListSecondary
import dk.betterlectio.android.ui.components.DetailMetaLine
import dk.betterlectio.android.ui.components.DetailSection
import dk.betterlectio.android.ui.components.EmptyBox
import dk.betterlectio.android.ui.components.ErrorBox
import dk.betterlectio.android.ui.components.ListSkeleton
import dk.betterlectio.android.ui.components.StatusChip
import dk.betterlectio.android.ui.components.isDueUrgent
import dk.betterlectio.android.ui.components.relativeDueLabel

private object AsgRoutes {
    const val LIST = "asg_list"
    const val DETAIL = "asg_detail"
}

@Composable
fun AssignmentsScreen(
    viewModel: AssignmentsViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
) {
    val navController = rememberNavController()
    val state by viewModel.state.collectAsStateWithLifecycle()

    LaunchedEffect(state.detail) {
        if (state.detail == null) {
            val route = navController.currentBackStackEntry?.destination?.route
            if (route == AsgRoutes.DETAIL) {
                navController.popBackStack(AsgRoutes.LIST, inclusive = false)
            }
        }
    }

    NavHost(navController = navController, startDestination = AsgRoutes.LIST, modifier = Modifier.fillMaxSize()) {
        composable(AsgRoutes.LIST) {
            AssignmentsListPane(
                viewModel = viewModel,
                scrollToTopToken = scrollToTopToken,
                onOpen = { item ->
                    viewModel.openDetail(item)
                    navController.navigate(AsgRoutes.DETAIL)
                },
            )
        }
        composable(AsgRoutes.DETAIL) {
            BackHandler {
                viewModel.closeDetail()
                navController.popBackStack()
            }
            val detail = state.detail
            if (detail == null) {
                ListSkeleton()
            } else {
                AssignmentDetailPane(
                    detail = detail,
                    onBack = {
                        viewModel.closeDetail()
                        navController.popBackStack()
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AssignmentsListPane(
    viewModel: AssignmentsViewModel,
    scrollToTopToken: Int,
    onOpen: (AssignmentItem) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    LaunchedEffect(scrollToTopToken) {
        if (scrollToTopToken > 0) listState.animateScrollToItem(0)
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_assignments)) },
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
            Column(Modifier.fillMaxSize()) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(AssignmentFilter.entries) { filter ->
                        FilterChip(
                            selected = state.filter == filter,
                            onClick = { viewModel.setFilter(filter) },
                            label = {
                                Text(
                                    when (filter) {
                                        AssignmentFilter.ALL -> stringResource(R.string.filter_all)
                                        AssignmentFilter.AWAITING_ME -> stringResource(R.string.filter_awaiting)
                                        AssignmentFilter.DELIVERED -> stringResource(R.string.filter_delivered)
                                        AssignmentFilter.MISSING -> stringResource(R.string.filter_missing)
                                    },
                                )
                            },
                        )
                    }
                }
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                    thickness = 0.5.dp,
                )
                when {
                    state.loading && state.items.isEmpty() -> ListSkeleton()
                    state.error != null && state.items.isEmpty() ->
                        ErrorBox(state.error, onRetry = { viewModel.refresh(true) })
                    state.filtered.isEmpty() -> EmptyBox(
                        text = stringResource(R.string.empty_assignments),
                        description = stringResource(
                            if (state.filter == AssignmentFilter.ALL) {
                                R.string.empty_assignments_all_hint
                            } else {
                                R.string.empty_assignments_hint
                            },
                        ),
                        icon = Icons.AutoMirrored.Outlined.Assignment,
                        actionLabel = stringResource(R.string.action_retry),
                        onAction = { viewModel.refresh(true) },
                    )
                    else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                        items(state.filtered, key = { it.id }) { item ->
                            val statusColor = when {
                                item.status.contains("mangler", ignoreCase = true) ||
                                    item.status.contains("afventer", ignoreCase = true) ->
                                    MaterialTheme.colorScheme.error
                                item.status.contains("afleveret", ignoreCase = true) ||
                                    item.status.contains("godkendt", ignoreCase = true) ->
                                    MaterialTheme.colorScheme.primary
                                else -> MaterialTheme.colorScheme.onSurfaceVariant
                            }
                            val dueLabel = relativeDueLabel(item.deadline)
                            val urgent = isDueUrgent(item.deadline) &&
                                !item.status.contains("aflever", ignoreCase = true)
                            AppListRow(
                                onClick = { onOpen(item) },
                                trailing = {
                                    if (item.status.isNotBlank()) {
                                        StatusChip(text = item.status, color = statusColor)
                                    }
                                },
                            ) {
                                AppListPrimary(item.title, emphasized = true, maxLines = 2)
                                if (item.team.isNotBlank()) {
                                    AppListSecondary(item.team)
                                }
                                val meta = buildList {
                                    add("${stringResource(R.string.label_week)} ${item.week}")
                                    dueLabel?.let { add(it) }
                                }.joinToString(" · ")
                                if (meta.isNotBlank()) {
                                    AppListMeta(
                                        text = meta,
                                        color = if (urgent) {
                                            MaterialTheme.colorScheme.error
                                        } else {
                                            MaterialTheme.colorScheme.onSurfaceVariant
                                        },
                                    )
                                }
                            }
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
private fun AssignmentDetailPane(
    detail: AssignmentDetail,
    onBack: () -> Unit,
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val statusColor = when {
        detail.item.status.contains("mangler", ignoreCase = true) ||
            detail.item.status.contains("afventer", ignoreCase = true) ||
            detail.item.status.contains("venter", ignoreCase = true) ->
            MaterialTheme.colorScheme.error
        detail.item.status.contains("afleveret", ignoreCase = true) ||
            detail.item.status.contains("godkendt", ignoreCase = true) ||
            detail.item.status.contains("afsluttet", ignoreCase = true) ->
            MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val dueLabel = relativeDueLabel(detail.item.deadline)
    val urgent = isDueUrgent(detail.item.deadline) &&
        !detail.item.status.contains("aflever", ignoreCase = true)
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(detail.item.title, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    if (detail.item.status.isNotBlank()) {
                        StatusChip(
                            text = detail.item.status,
                            color = statusColor,
                            modifier = Modifier.padding(end = 12.dp),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            if (detail.item.team.isNotBlank()) {
                Text(detail.item.team, style = MaterialTheme.typography.titleMedium)
            }
            dueLabel?.let { due ->
                Text(
                    "${stringResource(R.string.label_deadline)}: $due",
                    style = MaterialTheme.typography.labelLarge,
                    color = if (urgent) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            DetailSection(stringResource(R.string.label_status)) {
                DetailMetaLine(stringResource(R.string.label_status), detail.item.status)
                DetailMetaLine(stringResource(R.string.label_awaits), detail.item.awaits)
                DetailMetaLine(
                    stringResource(R.string.label_hours),
                    detail.item.studentTime.toString(),
                )
                if (detail.grading.isNotBlank()) {
                    DetailMetaLine(stringResource(R.string.label_grading), detail.grading)
                }
                if (detail.responsible.isNotBlank()) {
                    DetailMetaLine(stringResource(R.string.label_teacher), detail.responsible)
                }
            }
            if (detail.description.isNotBlank()) {
                DetailSection(stringResource(R.string.assignment_description)) {
                    Text(detail.description, style = MaterialTheme.typography.bodyLarge)
                }
            }
            val allFiles = buildList {
                addAll(detail.files)
                detail.submissions.forEach { sub ->
                    val url = sub.documentUrl ?: return@forEach
                    val name = sub.documentName?.takeIf { it.isNotBlank() }
                        ?: sub.user.takeIf { it.isNotBlank() }
                        ?: "Dokument"
                    add(name to url)
                }
            }.distinctBy { it.second }
            if (allFiles.isNotEmpty()) {
                DetailSection(stringResource(R.string.assignment_files)) {
                    allFiles.forEach { (name, url) ->
                        AttachmentRow(
                            name = name,
                            url = url,
                            isFileHint = true,
                            snackbarHostState = snackbarHostState,
                        )
                    }
                }
            }
        }
    }
}
