package dk.betterlectio.android.ui.screens.messages

import androidx.activity.compose.BackHandler
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Drafts
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.AddReaction
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import java.time.LocalDateTime
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import dk.betterlectio.android.R
import dk.betterlectio.android.core.i18n.UiText
import dk.betterlectio.android.core.i18n.asString
import dk.betterlectio.android.feature.attachments.AttachmentMime
import dk.betterlectio.android.feature.messages.ComposeAttachment
import dk.betterlectio.android.feature.messages.MessageSearch
import dk.betterlectio.android.feature.messages.MessageThread
import dk.betterlectio.android.feature.messages.MessageThreadDetail
import dk.betterlectio.android.feature.messages.MessageReactionEmoji
import dk.betterlectio.android.feature.messages.MessageReactionGroup
import dk.betterlectio.android.feature.messages.MessageEditedTimeFormatter
import dk.betterlectio.android.feature.messages.MessageEditedTimeValue
import dk.betterlectio.android.ui.components.AppListDivider
import dk.betterlectio.android.ui.components.AppListMeta
import dk.betterlectio.android.ui.components.AppListPrimary
import dk.betterlectio.android.ui.components.AppListRow
import dk.betterlectio.android.ui.components.AppListSecondary
import dk.betterlectio.android.ui.components.AttachmentChip
import dk.betterlectio.android.ui.components.EmptyBox
import dk.betterlectio.android.ui.components.ErrorBox
import dk.betterlectio.android.ui.components.LectioAsyncImage
import dk.betterlectio.android.ui.components.PersonAvatar
import dk.betterlectio.android.ui.components.LectioHtmlBody
import dk.betterlectio.android.ui.components.ListSkeleton
import dk.betterlectio.android.ui.components.SectionHeader
import dk.betterlectio.android.ui.components.UnreadDot
import dk.betterlectio.android.ui.components.bbcode.BbcodeEditor
import java.time.LocalDate
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

private object MsgRoutes {
    const val LIST = "messages_list"
    const val THREAD = "messages_thread/{threadId}"
    const val COMPOSE = "messages_compose"
    fun thread(id: String) = "messages_thread/$id"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesScreen(
    viewModel: MessagesViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
) {
    val navController = rememberNavController()
    val state by viewModel.state.collectAsStateWithLifecycle()

    // Keep nav in sync when detail is closed externally (e.g. delete)
    LaunchedEffect(state.detail) {
        if (state.detail == null) {
            val route = navController.currentBackStackEntry?.destination?.route
            if (route?.startsWith("messages_thread") == true) {
                navController.popBackStack(MsgRoutes.LIST, inclusive = false)
            }
        }
    }

    // When compose is opened without going through the FAB (e.g. external handoff),
    // push the compose route once showCompose becomes true.
    LaunchedEffect(state.showCompose) {
        if (state.showCompose) {
            val route = navController.currentBackStackEntry?.destination?.route
            if (route != MsgRoutes.COMPOSE) {
                navController.navigate(MsgRoutes.COMPOSE) {
                    launchSingleTop = true
                }
            }
        }
    }

    NavHost(
        navController = navController,
        startDestination = MsgRoutes.LIST,
        modifier = Modifier.fillMaxSize(),
    ) {
        composable(MsgRoutes.LIST) {
            MessageListPane(
                viewModel = viewModel,
                scrollToTopToken = scrollToTopToken,
                onOpenThread = { thread ->
                    viewModel.openThread(thread)
                    // Digits-only id — full `$LB2$_MC_$_…` tokens break Navigation paths.
                    navController.navigate(MsgRoutes.thread(thread.normalizedId.ifBlank { thread.id }))
                },
                onCompose = {
                    viewModel.openCompose()
                    navController.navigate(MsgRoutes.COMPOSE)
                },
            )
        }
        composable(
            route = MsgRoutes.THREAD,
            arguments = listOf(navArgument("threadId") { type = NavType.StringType }),
        ) {
            BackHandler { viewModel.closeDetail(); navController.popBackStack() }
            val detail = state.detail
            if (detail == null) {
                // Loading, or open failed — never leave the user on a blank skeleton forever.
                Scaffold(
                    topBar = {
                        TopAppBar(
                            title = { Text(stringResource(R.string.tab_messages)) },
                            navigationIcon = {
                                IconButton(onClick = {
                                    viewModel.closeDetail()
                                    navController.popBackStack()
                                }) {
                                    Icon(
                                        Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = stringResource(R.string.cd_back),
                                    )
                                }
                            },
                        )
                    },
                ) { p ->
                    when {
                        state.loading -> ListSkeleton(modifier = Modifier.padding(p))
                        state.error != null -> ErrorBox(
                            error = state.error,
                            onRetry = {
                                // Pop back so the user can re-open from the list
                                viewModel.closeDetail()
                                navController.popBackStack()
                            },
                            modifier = Modifier.padding(p),
                        )
                        else -> ListSkeleton(modifier = Modifier.padding(p))
                    }
                }
            } else {
                MessageThreadPane(
                    detail = detail,
                    replyText = state.replyText,
                    replyAttachments = state.replyAttachments,
                    replyError = state.replyError,
                    reactionPendingTarget = state.reactionPendingTarget,
                    reactionError = state.reactionError,
                    editDraft = state.editDraft,
                    editTitle = state.editTitle,
                    editBody = state.editBody,
                    editLoading = state.editLoading,
                    editSaving = state.editSaving,
                    editError = state.editError,
                    isSending = state.isSending,
                    onReplyChange = viewModel::onReplyChange,
                    onSendReply = viewModel::sendReply,
                    onAddReplyAttachments = viewModel::addReplyAttachments,
                    onRemoveReplyAttachment = viewModel::removeReplyAttachment,
                    onReact = viewModel::react,
                    onReactionErrorShown = viewModel::clearReactionError,
                    onBeginEdit = viewModel::beginEdit,
                    onEditChange = viewModel::updateEdit,
                    onSaveEdit = viewModel::saveEdit,
                    onCancelEdit = viewModel::cancelEdit,
                    onMarkRead = viewModel::markRead,
                    onMarkUnread = viewModel::markUnread,
                    onToggleFlag = viewModel::toggleFlag,
                    onDelete = {
                        viewModel.deleteCurrent()
                        navController.popBackStack()
                    },
                    onBack = {
                        viewModel.closeDetail()
                        navController.popBackStack()
                    },
                )
            }
        }
        composable(MsgRoutes.COMPOSE) {
            BackHandler { viewModel.closeCompose(); navController.popBackStack() }
            MessageComposePane(
                state = state,
                viewModel = viewModel,
                onBack = {
                    viewModel.closeCompose()
                    navController.popBackStack()
                },
                onSent = {
                    navController.popBackStack()
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MessageListPane(
    viewModel: MessagesViewModel,
    scrollToTopToken: Int,
    onOpenThread: (MessageThread) -> Unit,
    onCompose: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val timeFmt = DateTimeFormatter.ofPattern("d. MMM", Locale.getDefault())
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val markedReadLabel = stringResource(R.string.message_marked_read_snackbar)
    val markedUnreadLabel = stringResource(R.string.message_marked_unread_snackbar)
    val deletedLabel = stringResource(R.string.message_deleted_snackbar)
    var searchQuery by remember { mutableStateOf("") }
    val filteredThreads = remember(state.threads, searchQuery) {
        MessageSearch.filter(state.threads, searchQuery)
    }

    LaunchedEffect(scrollToTopToken) {
        if (scrollToTopToken > 0) listState.animateScrollToItem(0)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_messages)) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCompose,
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.message_compose))
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.loading && state.threads.isNotEmpty(),
            onRefresh = { viewModel.refresh(true) },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            Column(Modifier.fillMaxSize()) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    singleLine = true,
                    shape = RoundedCornerShape(28.dp),
                    placeholder = { Text(stringResource(R.string.message_search_hint)) },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = stringResource(R.string.cd_search),
                        )
                    },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { searchQuery = "" }) {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = stringResource(R.string.cd_clear_search),
                                )
                            }
                        }
                    },
                    colors = OutlinedTextFieldDefaults.colors(
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.45f),
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.55f),
                    ),
                )
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.folders) { folder ->
                        FilterChip(
                            selected = state.selectedFolder.id == folder.id,
                            onClick = { viewModel.selectFolder(folder) },
                            label = { Text(folder.displayName) },
                        )
                    }
                }
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                    thickness = 0.5.dp,
                )
                when {
                    state.loading && state.threads.isEmpty() -> ListSkeleton()
                    state.error != null && state.threads.isEmpty() ->
                        ErrorBox(state.error, onRetry = { viewModel.refresh(true) })
                    state.threads.isEmpty() -> EmptyBox(
                        text = stringResource(R.string.empty_messages),
                        description = stringResource(R.string.empty_messages_folder_hint),
                        icon = Icons.Outlined.MailOutline,
                        actionLabel = stringResource(R.string.message_compose),
                        onAction = onCompose,
                    )
                    filteredThreads.isEmpty() -> EmptyBox(
                        text = stringResource(R.string.empty_messages_search),
                        description = stringResource(R.string.empty_messages_search_hint),
                        icon = Icons.Default.Search,
                        actionLabel = stringResource(R.string.cd_clear_search),
                        onAction = { searchQuery = "" },
                    )
                    else -> {
                        val sections = remember(filteredThreads) {
                            groupThreadsByRecency(filteredThreads)
                        }
                        LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                            sections.forEach { section ->
                                item(key = "hdr-${section.key}") {
                                    SectionHeader(stringResource(section.titleRes))
                                }
                                items(section.threads, key = { it.id }) { thread ->
                                    SwipeableMessageRow(
                                        thread = thread,
                                        timeFmt = timeFmt,
                                        onOpen = { onOpenThread(thread) },
                                        onToggleRead = {
                                            if (thread.unread) {
                                                viewModel.markThreadRead(thread)
                                                scope.launch {
                                                    snackbarHostState.showSnackbar(markedReadLabel)
                                                }
                                            } else {
                                                viewModel.markThreadUnread(thread)
                                                scope.launch {
                                                    snackbarHostState.showSnackbar(markedUnreadLabel)
                                                }
                                            }
                                        },
                                        onDelete = {
                                            viewModel.deleteThread(thread)
                                            scope.launch {
                                                snackbarHostState.showSnackbar(deletedLabel)
                                            }
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

private data class MessageDateSection(
    val key: String,
    val titleRes: Int,
    val threads: List<MessageThread>,
)

private fun groupThreadsByRecency(threads: List<MessageThread>): List<MessageDateSection> {
    val today = LocalDate.now()
    val buckets = linkedMapOf(
        "today" to mutableListOf<MessageThread>(),
        "yesterday" to mutableListOf(),
        "week" to mutableListOf(),
        "earlier" to mutableListOf(),
    )
    threads.forEach { thread ->
        val date = thread.dateChanged?.toLocalDate()
        val key = when {
            date == null -> "earlier"
            date == today -> "today"
            date == today.minusDays(1) -> "yesterday"
            ChronoUnit.DAYS.between(date, today) in 2..6 -> "week"
            else -> "earlier"
        }
        buckets.getValue(key).add(thread)
    }
    return listOf(
        "today" to R.string.message_section_today,
        "yesterday" to R.string.message_section_yesterday,
        "week" to R.string.message_section_this_week,
        "earlier" to R.string.message_section_earlier,
    ).mapNotNull { (key, res) ->
        val list = buckets.getValue(key)
        if (list.isEmpty()) null
        else MessageDateSection(key = key, titleRes = res, threads = list)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeableMessageRow(
    thread: MessageThread,
    timeFmt: DateTimeFormatter,
    onOpen: () -> Unit,
    onToggleRead: () -> Unit,
    onDelete: () -> Unit,
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    // iOS leading swipe: mark read or unread depending on current state
                    onToggleRead()
                    false // keep row; unread state updates in place
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    onDelete()
                    true
                }
                SwipeToDismissBoxValue.Settled -> false
            }
        },
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            val isDelete = direction == SwipeToDismissBoxValue.EndToStart
            val color = when {
                isDelete -> MaterialTheme.colorScheme.errorContainer
                thread.unread -> MaterialTheme.colorScheme.primaryContainer
                else -> MaterialTheme.colorScheme.secondaryContainer
            }
            val icon = when {
                isDelete -> Icons.Default.Delete
                thread.unread -> Icons.Default.Drafts
                else -> Icons.Outlined.MailOutline
            }
            val alignment = if (isDelete) Alignment.CenterEnd else Alignment.CenterStart
            val contentDesc = when {
                isDelete -> stringResource(R.string.message_swipe_delete)
                thread.unread -> stringResource(R.string.message_swipe_read)
                else -> stringResource(R.string.message_swipe_unread)
            }
            val tint = when {
                isDelete -> MaterialTheme.colorScheme.onErrorContainer
                thread.unread -> MaterialTheme.colorScheme.onPrimaryContainer
                else -> MaterialTheme.colorScheme.onSecondaryContainer
            }
            Box(
                Modifier
                    .fillMaxSize()
                    .background(color)
                    .padding(horizontal = 20.dp),
                contentAlignment = alignment,
            ) {
                Icon(
                    icon,
                    contentDescription = contentDesc,
                    tint = tint,
                )
            }
        },
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = true,
    ) {
        AppListRow(
            onClick = onOpen,
            modifier = Modifier.background(MaterialTheme.colorScheme.surface),
            leading = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    UnreadDot(visible = thread.unread)
                    Spacer(Modifier.width(8.dp))
                    PersonAvatar(
                        name = thread.sender.ifBlank { thread.topic },
                        entityId = thread.senderEntityId,
                        kind = thread.senderKind?.let {
                            runCatching {
                                dk.betterlectio.android.feature.directory.DirectoryEntityKind.valueOf(it)
                            }.getOrNull()
                        },
                    )
                }
            },
            trailing = {
                Column(horizontalAlignment = Alignment.End) {
                    thread.dateChanged?.let {
                        AppListMeta(it.toLocalDate().format(timeFmt))
                    }
                    if (thread.flagged) {
                        Icon(
                            Icons.Default.Flag,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .size(16.dp),
                        )
                    }
                }
            },
        ) {
            AppListPrimary(thread.topic, emphasized = thread.unread)
            AppListSecondary(thread.sender)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun MessageThreadPane(
    detail: MessageThreadDetail,
    replyText: String,
    replyAttachments: List<ComposeAttachment>,
    replyError: UiText?,
    reactionPendingTarget: dk.betterlectio.android.feature.messages.MessageLocator?,
    reactionError: UiText?,
    editDraft: dk.betterlectio.android.feature.messages.MessageEditDraft?,
    editTitle: String,
    editBody: String,
    editLoading: Boolean,
    editSaving: Boolean,
    editError: UiText?,
    isSending: Boolean,
    onReplyChange: (String) -> Unit,
    onSendReply: () -> Unit,
    onAddReplyAttachments: (List<Uri>) -> Unit,
    onRemoveReplyAttachment: (Uri) -> Unit,
    onReact: (String, MessageReactionEmoji) -> Unit,
    onReactionErrorShown: () -> Unit,
    onBeginEdit: (String) -> Unit,
    onEditChange: (String?, String?) -> Unit,
    onSaveEdit: () -> Unit,
    onCancelEdit: () -> Unit,
    onMarkRead: () -> Unit,
    onMarkUnread: () -> Unit,
    onToggleFlag: () -> Unit,
    onDelete: () -> Unit,
    onBack: () -> Unit,
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val haptics = LocalHapticFeedback.current
    var pickerEntryId by remember { mutableStateOf<String?>(null) }
    var reactorGroup by remember { mutableStateOf<MessageReactionGroup?>(null) }
    var actionEntryId by remember { mutableStateOf<String?>(null) }
    var loadingEditEntryId by remember { mutableStateOf<String?>(null) }
    var previousPending by remember { mutableStateOf(reactionPendingTarget) }
    var relativeTimeNow by remember { mutableStateOf(Instant.now()) }
    val reactionErrorText = reactionError?.asString()
    LaunchedEffect(reactionErrorText) {
        if (reactionErrorText != null) {
            snackbarHostState.showSnackbar(reactionErrorText)
            onReactionErrorShown()
        }
    }
    LaunchedEffect(reactionPendingTarget, reactionErrorText) {
        if (previousPending != null && reactionPendingTarget == null && reactionErrorText == null) {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        }
        previousPending = reactionPendingTarget
    }
    LaunchedEffect(detail.entries.any { it.editedAt != null }) {
        if (detail.entries.none { it.editedAt != null }) return@LaunchedEffect
        relativeTimeNow = Instant.now()
        while (true) {
            delay(60_000)
            relativeTimeNow = Instant.now()
        }
    }
    LaunchedEffect(editLoading) {
        if (!editLoading) loadingEditEntryId = null
    }
    // adjustResize already shrinks the window for the keyboard. Do not also apply
    // IME content insets / imePadding or we get a large empty band above the keyboard.
    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(
            WindowInsetsSides.Horizontal + WindowInsetsSides.Top,
        ),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        detail.thread.topic,
                        maxLines = 1,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    if (detail.thread.unread) {
                        IconButton(onClick = onMarkRead) {
                            Icon(
                                Icons.Default.Drafts,
                                contentDescription = stringResource(R.string.message_mark_read),
                            )
                        }
                    } else {
                        IconButton(onClick = onMarkUnread) {
                            Icon(
                                Icons.Outlined.MailOutline,
                                contentDescription = stringResource(R.string.message_mark_unread),
                            )
                        }
                    }
                    IconButton(onClick = onToggleFlag) {
                        Icon(
                            Icons.Default.Flag,
                            contentDescription = if (detail.thread.flagged) {
                                stringResource(R.string.message_unflag)
                            } else {
                                stringResource(R.string.message_flag)
                            },
                            tint = if (detail.thread.flagged) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                    IconButton(onClick = onDelete) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = stringResource(R.string.message_delete),
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                },
            )
        },
    ) { padding ->
        val dateTimeFmt = remember {
            DateTimeFormatter.ofPattern("d. MMM yyyy · HH:mm", Locale.getDefault())
        }
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            Column(
                Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(top = 8.dp),
            ) {
                if (detail.receivers.isNotEmpty()) {
                    Text(
                        stringResource(R.string.message_receivers),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        detail.receivers.joinToString(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                }
                detail.entries.forEach { entry ->
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
                        thickness = 0.5.dp,
                    )
                    Spacer(Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.combinedClickable(
                            onClick = {},
                            onLongClick = {
                                if (entry.locator != null && reactionPendingTarget == null && !isSending) {
                                    pickerEntryId = entry.id
                                }
                            },
                        ),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        PersonAvatar(
                            name = entry.senderName.orEmpty().ifBlank { "?" },
                            entityId = entry.senderEntityId,
                            kind = entry.senderKind?.let {
                                runCatching {
                                    dk.betterlectio.android.feature.directory.DirectoryEntityKind.valueOf(it)
                                }.getOrNull()
                            },
                        )
                        Column(Modifier.weight(1f)) {
                            Text(
                                entry.senderName.orEmpty().ifBlank { "—" },
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            entry.sentAt?.let { sent ->
                                Text(
                                    formatMessageTimestamp(sent, dateTimeFmt),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            entry.editedAt?.let { editedAt ->
                                Text(
                                    editedMessageLabel(editedAt, relativeTimeNow),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        if (entry.locator != null) {
                            Box {
                                IconButton(
                                    onClick = { pickerEntryId = entry.id },
                                    enabled = reactionPendingTarget == null && !isSending,
                                ) {
                                    if (reactionPendingTarget == entry.locator) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(18.dp),
                                            strokeWidth = 2.dp,
                                        )
                                    } else {
                                        Icon(
                                            Icons.Outlined.AddReaction,
                                            contentDescription = stringResource(R.string.message_add_reaction),
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                                DropdownMenu(
                                    expanded = pickerEntryId == entry.id,
                                    onDismissRequest = { pickerEntryId = null },
                                ) {
                                    Row(
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                                    ) {
                                        MessageReactionEmoji.entries.forEach { emoji ->
                                            IconButton(
                                                onClick = {
                                                    pickerEntryId = null
                                                    onReact(entry.id, emoji)
                                                },
                                            ) {
                                                Text(
                                                    emoji.glyph,
                                                    style = MaterialTheme.typography.titleLarge,
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if (entry.editPostbackTarget.isNotBlank()) {
                            Box {
                                IconButton(
                                    onClick = { actionEntryId = entry.id },
                                    enabled = reactionPendingTarget == null && !isSending && !editLoading,
                                ) {
                                    if (editLoading && loadingEditEntryId == entry.id) {
                                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                                    } else {
                                        Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.message_more_actions))
                                    }
                                }
                                DropdownMenu(
                                    expanded = actionEntryId == entry.id,
                                    onDismissRequest = { actionEntryId = null },
                                ) {
                                    DropdownMenuItem(
                                        text = { Text(stringResource(R.string.message_edit)) },
                                        leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) },
                                        onClick = {
                                            loadingEditEntryId = entry.id
                                            actionEntryId = null
                                            onBeginEdit(entry.id)
                                        },
                                    )
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerLow)
                            .padding(12.dp),
                    ) {
                        LectioHtmlBody(html = entry.contentHtml)
                    }
                    if (entry.attachments.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        entry.attachments.forEach { att ->
                            val isImage = AttachmentMime.isImageExtension(
                                AttachmentMime.extensionOf(att.name)
                                    ?: AttachmentMime.extensionOf(att.url),
                            )
                            if (isImage) {
                                LectioAsyncImage(
                                    url = att.url,
                                    contentDescription = att.name,
                                    modifier = Modifier.padding(vertical = 4.dp),
                                )
                            } else {
                                AttachmentChip(
                                    name = att.name,
                                    url = att.url,
                                    isFileHint = true,
                                    snackbarHostState = snackbarHostState,
                                    modifier = Modifier.padding(vertical = 2.dp),
                                )
                            }
                        }
                    }
                    if (entry.reactions.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            entry.reactions.forEach { group ->
                                val selected = group.reactors.any { it.isOwn }
                                val background = if (selected) {
                                    MaterialTheme.colorScheme.primaryContainer
                                } else {
                                    MaterialTheme.colorScheme.surfaceContainerHigh
                                }
                                val foreground = if (selected) {
                                    MaterialTheme.colorScheme.onPrimaryContainer
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                }
                                Row(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(50))
                                        .background(background)
                                        .combinedClickable(
                                            enabled = reactionPendingTarget == null && !isSending,
                                            onClick = { onReact(entry.id, group.emoji) },
                                            onLongClick = { reactorGroup = group },
                                        )
                                        .padding(horizontal = 10.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                                ) {
                                    Text(group.emoji.glyph)
                                    Text(
                                        group.reactors.size.toString(),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = foreground,
                                    )
                                    if (reactionPendingTarget == entry.locator && selected) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(12.dp),
                                            strokeWidth = 1.5.dp,
                                            color = foreground,
                                        )
                                    }
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                thickness = 0.5.dp,
            )
            SurfaceReplyBar(
                replyText = replyText,
                replyAttachments = replyAttachments,
                replyError = replyError,
                isSending = isSending || reactionPendingTarget != null,
                onReplyChange = onReplyChange,
                onSendReply = onSendReply,
                onAddAttachments = onAddReplyAttachments,
                onRemoveAttachment = onRemoveReplyAttachment,
            )
        }
    }
    reactorGroup?.let { group ->
        AlertDialog(
            onDismissRequest = { reactorGroup = null },
            title = { Text(stringResource(R.string.message_reacted_with, group.emoji.glyph)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    group.reactors.forEach { reactor ->
                        Text(
                            if (reactor.isOwn) stringResource(R.string.message_reaction_you)
                            else reactor.name,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { reactorGroup = null }) {
                    Text(stringResource(R.string.action_close))
                }
            },
        )
    }
    editDraft?.let { draft ->
        ModalBottomSheet(onDismissRequest = { if (!editSaving) onCancelEdit() }) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(stringResource(R.string.message_edit), style = MaterialTheme.typography.headlineSmall)
                OutlinedTextField(
                    value = editTitle,
                    onValueChange = { if (it.length <= 100) onEditChange(it, null) },
                    label = { Text(stringResource(R.string.message_subject)) },
                    enabled = !editSaving,
                    modifier = Modifier.fillMaxWidth(),
                )
                BbcodeEditor(
                    value = editBody,
                    onValueChange = { onEditChange(null, it) },
                    label = stringResource(R.string.message_body),
                    enabled = !editSaving,
                    minLines = 8,
                    maxLines = 16,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "${editBody.length + draft.signatureSuffix.length} / 100000",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.End),
                )
                editError?.let { Text(it.asString(), color = MaterialTheme.colorScheme.error) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onCancelEdit, enabled = !editSaving) {
                        Text(stringResource(R.string.action_cancel))
                    }
                    Button(
                        onClick = onSaveEdit,
                        enabled = !editSaving && editTitle.length <= 100 &&
                            editBody.length + draft.signatureSuffix.length <= 100_000 &&
                            (editTitle != draft.title || editBody != draft.body),
                    ) {
                        if (editSaving) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                        }
                        Text(stringResource(R.string.action_save))
                    }
                }
            }
        }
    }
}

@Composable
private fun SurfaceReplyBar(
    replyText: String,
    replyAttachments: List<ComposeAttachment>,
    replyError: UiText?,
    isSending: Boolean,
    onReplyChange: (String) -> Unit,
    onSendReply: () -> Unit,
    onAddAttachments: (List<Uri>) -> Unit,
    onRemoveAttachment: (Uri) -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        BbcodeEditor(
            value = replyText,
            onValueChange = onReplyChange,
            placeholder = stringResource(R.string.message_reply_hint),
            minLines = 2,
            maxLines = 8,
            enabled = !isSending,
            modifier = Modifier.fillMaxWidth(),
        )
        PendingAttachmentsRow(
            attachments = replyAttachments,
            onRemove = onRemoveAttachment,
            enabled = !isSending,
        )
        replyError?.let {
            Text(
                it.asString(),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (isSending) {
            Text(
                stringResource(R.string.message_sending),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AttachMenuButton(
                enabled = !isSending && replyAttachments.size < MessagesViewModel.MAX_ATTACHMENTS,
                onPicked = onAddAttachments,
            )
            Spacer(Modifier.weight(1f))
            Button(
                onClick = onSendReply,
                enabled = replyText.isNotBlank() && !isSending,
            ) {
                if (isSending) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text(stringResource(R.string.message_send))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun MessageComposePane(
    state: MessagesUiState,
    viewModel: MessagesViewModel,
    onBack: () -> Unit,
    onSent: () -> Unit,
) {
    LaunchedEffect(state.showCompose, state.composeMessage) {
        if (!state.showCompose && state.composeMessage != null) onSent()
    }
    val canSend = state.composeSubject.isNotBlank() &&
        state.composeBody.isNotBlank() &&
        state.selectedRecipients.isNotEmpty() &&
        !state.isSending
    // See MessageThreadPane: no IME insets here — MainActivity uses adjustResize.
    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(
            WindowInsetsSides.Horizontal + WindowInsetsSides.Top,
        ),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.message_compose)) },
                navigationIcon = {
                    IconButton(onClick = onBack, enabled = !state.isSending) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    TextButton(
                        onClick = viewModel::sendCompose,
                        enabled = canSend,
                    ) {
                        if (state.isSending) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Text(stringResource(R.string.message_send))
                        }
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
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = state.recipientQuery,
                onValueChange = viewModel::onRecipientQuery,
                label = { Text(stringResource(R.string.message_recipients)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                enabled = !state.isSending,
            )
            if (state.selectedRecipients.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    state.selectedRecipients.forEach { r ->
                        InputChip(
                            selected = true,
                            onClick = { if (!state.isSending) viewModel.toggleRecipient(r) },
                            label = { Text(r.name) },
                            trailingIcon = {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = stringResource(R.string.cd_clear_search),
                                    modifier = Modifier.size(16.dp),
                                )
                            },
                        )
                    }
                }
            }
            state.recipientResults
                .filter { result -> state.selectedRecipients.none { it.id == result.id } }
                .take(8)
                .forEach { r ->
                    AppListRow(
                        onClick = { if (!state.isSending) viewModel.toggleRecipient(r) },
                        leading = {
                            PersonAvatar(
                                name = r.name,
                                entityId = r.id.takeIf {
                                    it.startsWith("S") || it.startsWith("T")
                                },
                            )
                        },
                    ) {
                        AppListPrimary(r.name, emphasized = true)
                        if (r.kind.isNotBlank()) {
                            AppListSecondary(r.kind)
                        }
                    }
                }

            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    stringResource(R.string.message_replies_not_allowed),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = state.repliesNotAllowed,
                    onCheckedChange = viewModel::setRepliesNotAllowed,
                    enabled = !state.isSending,
                )
            }

            OutlinedTextField(
                value = state.composeSubject,
                onValueChange = { viewModel.updateCompose(subject = it.take(100)) },
                label = { Text(stringResource(R.string.message_subject)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                enabled = !state.isSending,
            )

            BbcodeEditor(
                value = state.composeBody,
                onValueChange = { viewModel.updateCompose(body = it) },
                label = stringResource(R.string.message_body),
                minLines = 4,
                maxLines = 12,
                enabled = !state.isSending,
                modifier = Modifier.fillMaxWidth(),
            )

            PendingAttachmentsRow(
                attachments = state.composeAttachments,
                onRemove = viewModel::removeComposeAttachment,
                enabled = !state.isSending,
            )
            AttachMenuButton(
                enabled = !state.isSending &&
                    state.composeAttachments.size < MessagesViewModel.MAX_ATTACHMENTS,
                onPicked = viewModel::addComposeAttachments,
            )

            state.composeMessage?.let {
                Text(
                    it.asString(),
                    color = if (state.showCompose) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                )
            }
            if (state.isSending) {
                Text(
                    stringResource(R.string.message_sending),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else if (!canSend) {
                Text(
                    stringResource(R.string.message_compose_send_disabled_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PendingAttachmentsRow(
    attachments: List<ComposeAttachment>,
    onRemove: (Uri) -> Unit,
    enabled: Boolean,
) {
    if (attachments.isEmpty()) return
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        attachments.forEach { att ->
            InputChip(
                selected = false,
                onClick = { },
                enabled = enabled,
                label = { Text(att.displayName, maxLines = 1) },
                leadingIcon = {
                    Icon(
                        Icons.Default.AttachFile,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
                trailingIcon = {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = stringResource(R.string.message_attach_remove),
                        modifier = Modifier
                            .size(16.dp)
                            .clickable(enabled = enabled) { onRemove(att.uri) },
                    )
                },
            )
        }
    }
}

@Composable
private fun AttachMenuButton(
    enabled: Boolean,
    onPicked: (List<Uri>) -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val photoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(
            maxItems = MessagesViewModel.MAX_ATTACHMENTS,
        ),
    ) { uris -> if (uris.isNotEmpty()) onPicked(uris) }
    val docPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris -> if (uris.isNotEmpty()) onPicked(uris) }

    Box {
        TextButton(
            onClick = { menuOpen = true },
            enabled = enabled,
        ) {
            Icon(
                Icons.Default.AttachFile,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(6.dp))
            Text(stringResource(R.string.message_attach))
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.message_attach_photo)) },
                onClick = {
                    menuOpen = false
                    photoPicker.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo),
                    )
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.message_attach_file)) },
                onClick = {
                    menuOpen = false
                    docPicker.launch(arrayOf("*/*"))
                },
            )
        }
    }
}

private fun formatMessageTimestamp(value: LocalDateTime, fmt: DateTimeFormatter): String =
    value.format(fmt)

@Composable
private fun editedMessageLabel(editedAt: Instant, now: Instant): String =
    when (val value = MessageEditedTimeFormatter.value(editedAt, now)) {
        MessageEditedTimeValue.JustNow -> stringResource(R.string.message_edited_just_now)
        is MessageEditedTimeValue.Minutes -> pluralStringResource(
            R.plurals.message_edited_minutes,
            value.count,
            value.count,
        )
        is MessageEditedTimeValue.Hours -> pluralStringResource(
            R.plurals.message_edited_hours,
            value.count,
            value.count,
        )
        is MessageEditedTimeValue.Days -> pluralStringResource(
            R.plurals.message_edited_days,
            value.count,
            value.count,
        )
        is MessageEditedTimeValue.Absolute -> stringResource(R.string.message_edited_at, value.value)
    }
