package dk.betterlectio.android.ui.screens.schedule

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterlectio.android.R
import dk.betterlectio.android.core.i18n.asString
import dk.betterlectio.android.feature.live.LiveLessonBoundary
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.LessonParticipant
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.statusLabelText
import dk.betterlectio.android.feature.schedule.timeLabelText
import dk.betterlectio.android.feature.settings.CalendarStyle
import dk.betterlectio.android.ui.components.AppListPrimary
import dk.betterlectio.android.ui.components.AppListRow
import dk.betterlectio.android.ui.components.AttachmentRow
import dk.betterlectio.android.ui.components.DateStrip
import dk.betterlectio.android.ui.components.DateStripDay
import dk.betterlectio.android.ui.components.DetailSection
import dk.betterlectio.android.ui.components.DetailSheetHeader
import dk.betterlectio.android.ui.components.DetailSheetPadding
import dk.betterlectio.android.ui.components.ErrorBox
import dk.betterlectio.android.ui.components.LessonContentBlocks
import dk.betterlectio.android.ui.components.LoadingBox
import dk.betterlectio.android.ui.components.PersonAvatar
import dk.betterlectio.android.ui.components.StatusChip
import dk.betterlectio.android.ui.theme.BetterLectioThemeExtras
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.TextStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val calendarStyle by viewModel.calendarStyle.collectAsStateWithLifecycle()
    // Subscribe so bricks recompose when Supabase lesson mappings / color mode change.
    @Suppress("UNUSED_VARIABLE")
    val lessonMappings by viewModel.lessonMappings.collectAsStateWithLifecycle()
    @Suppress("UNUSED_VARIABLE")
    val useSubjectColors by viewModel.useSubjectColors.collectAsStateWithLifecycle()
    val extended = BetterLectioThemeExtras.extendedColors

    // Scroll-to-top: jump to today
    LaunchedEffect(scrollToTopToken) {
        if (scrollToTopToken > 0) {
            viewModel.selectDate(LocalDate.now())
        }
    }

    // Tick every minute for live header
    var nowEpochMinute by remember { mutableLongStateOf(System.currentTimeMillis() / 60_000) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            nowEpochMinute = System.currentTimeMillis() / 60_000
        }
    }
    val now = remember(nowEpochMinute) { LocalDateTime.now() }
    val liveHeader = remember(state.eventsByDate, nowEpochMinute) {
        computeLiveHeader(
            events = state.eventsByDate[LocalDate.now()].orEmpty()
                .ifEmpty {
                    state.week?.days?.find { it.date == LocalDate.now() }?.events.orEmpty()
                },
            now = now,
            displayTitle = viewModel::displayTitle,
        )
    }

    val locale = Locale.getDefault()
    val dayName = state.selectedDate.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
        .replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }
    val subtitle = stringResource(R.string.schedule_week_subtitle, dayName, state.weekNum)
    val today = remember { LocalDate.now() }
    val isAwayFromToday = state.selectedDate != today
    val nudgeVisible by viewModel.referralNudgeVisible.collectAsStateWithLifecycle()
    val celebrationName by viewModel.referralCelebrationName.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = androidx.compose.ui.platform.LocalContext.current

    LaunchedEffect(celebrationName) {
        val name = celebrationName ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(context.getString(R.string.referral_celebration, name))
        viewModel.consumeReferralCelebration()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(stringResource(R.string.tab_schedule))
                        Text(
                            subtitle,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                actions = {
                    // Week is already in the subtitle — keep "today" up here so the strip stays short.
                    AnimatedVisibility(
                        visible = isAwayFromToday,
                        enter = fadeIn(),
                        exit = fadeOut(),
                    ) {
                        TextButton(onClick = { viewModel.selectDate(today) }) {
                            Text(
                                stringResource(R.string.schedule_go_to_today),
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = viewModel::openPrivateEventSheet,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Icon(Icons.Default.Add, contentDescription = stringResource(R.string.private_event_add))
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.loading && state.week != null,
            onRefresh = { viewModel.refresh(true) },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.loading && state.week == null && state.eventsByDate.isEmpty() -> LoadingBox()
                state.error != null && state.week == null && state.eventsByDate.isEmpty() ->
                    ErrorBox(state.error, onRetry = { viewModel.refresh(true) })
                else -> {
                    Column(Modifier.fillMaxSize()) {
                        // Live lesson header (iOS ScheduleHeaderView)
                        LiveLessonHeader(liveHeader)

                        // Compact day strip — week lives in the app bar subtitle
                        val weekDays = state.week?.days.orEmpty()
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .shadow(
                                    elevation = 3.dp,
                                    shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
                                    clip = false,
                                )
                                .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                                .background(MaterialTheme.colorScheme.surface)
                                .padding(top = 8.dp),
                        ) {
                            // Capture maps from composition so strip tints recompose when week data lands.
                            val eventsByDate = state.eventsByDate
                            val knownEmptyDays = state.knownEmptyDays
                            DateStrip(
                                days = weekDays.map { day ->
                                    DateStripDay(
                                        date = day.date,
                                        hasEvents = day.events.isNotEmpty(),
                                    )
                                },
                                selected = state.selectedDate,
                                onSelect = viewModel::selectDate,
                                onWeekChanged = viewModel::selectDate,
                                hasEvents = { date ->
                                    when {
                                        date in knownEmptyDays -> false
                                        date in eventsByDate ->
                                            eventsByDate[date].orEmpty().isNotEmpty()
                                        else ->
                                            weekDays.find { it.date == date }
                                                ?.events
                                                ?.isNotEmpty() == true
                                    }
                                },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }

                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
                            thickness = 0.5.dp,
                        )

                        ScheduleDayPager(
                            selectedDate = state.selectedDate,
                            onSelectDate = viewModel::selectDate,
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f),
                        ) { date ->
                            val events = state.eventsByDate[date]
                                ?: state.week?.days?.find { it.date == date }?.events
                                ?: emptyList()

                            DayPageContent(
                                date = date,
                                events = events,
                                calendarStyle = calendarStyle,
                                viewModel = viewModel,
                            )
                        }
                    }
                }
            }
        }
    }

    // Lesson detail sheet
    state.selectedEvent?.let { event ->
        val accent = Color(viewModel.accentArgbFor(event))
        val statusColor = when (event.status) {
            EventStatus.CHANGED -> extended.statusChanged
            EventStatus.CANCELLED -> extended.statusCancelled
            EventStatus.NORMAL -> extended.statusNormal
        }
        val sheetSnackbar = remember { SnackbarHostState() }
        ModalBottomSheet(onDismissRequest = { viewModel.selectEvent(null) }) {
            Box(Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
            ) {
                DetailSheetPadding {
                    DetailSheetHeader(
                        title = viewModel.displayTitle(event),
                        subtitle = event.timeLabelText(),
                        meta = listOfNotNull(event.teacher, event.room).joinToString(" · ")
                            .ifBlank { null },
                        trailing = {
                            event.statusLabelText()?.takeIf { it.isNotBlank() }?.let { label ->
                                StatusChip(text = label, color = statusColor)
                            }
                        },
                    )

                    Spacer(Modifier.height(12.dp))
                    HorizontalDivider(
                        modifier = Modifier.fillMaxWidth(0.25f),
                        thickness = 3.dp,
                        color = accent,
                    )

                    if (state.detailLoading) {
                        Spacer(Modifier.height(24.dp))
                        CircularProgressIndicator()
                    }

                    state.lessonDetail?.let { detail ->
                        val homeworkBlocks = detail.contentBlocks.filter { it.isHomework }
                        val otherBlocks = detail.contentBlocks.filter { !it.isHomework }
                        val hasNote = !detail.note.isNullOrBlank()
                        val hasBody = homeworkBlocks.isNotEmpty() || otherBlocks.isNotEmpty()
                        val teachers = detail.participants.filter {
                            it.kind == DirectoryEntityKind.TEACHER ||
                                it.role.equals("Lærer", ignoreCase = true)
                        }
                        val students = detail.participants.filter {
                            it.kind == DirectoryEntityKind.STUDENT ||
                                it.role.equals("Elev", ignoreCase = true)
                        }
                        val otherParticipants = detail.participants.filter { p ->
                            teachers.none { it.id == p.id } && students.none { it.id == p.id }
                        }

                        if (!state.detailLoading && !hasNote && !hasBody &&
                            detail.participants.isEmpty() && detail.resources.isEmpty()
                        ) {
                            Spacer(Modifier.height(16.dp))
                            Text(
                                stringResource(R.string.lesson_empty),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        detail.note?.takeIf { it.isNotBlank() }?.let {
                            DetailSection(stringResource(R.string.label_notes)) {
                                Text(it, style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                        if (homeworkBlocks.isNotEmpty()) {
                            DetailSection(stringResource(R.string.label_homework)) {
                                LessonContentBlocks(homeworkBlocks)
                            }
                        }
                        if (otherBlocks.isNotEmpty()) {
                            DetailSection(stringResource(R.string.lesson_other_content)) {
                                LessonContentBlocks(otherBlocks)
                            }
                        }
                        if (detail.resources.isNotEmpty()) {
                            DetailSection(stringResource(R.string.lesson_resources)) {
                                detail.resources.forEach { r ->
                                    AttachmentRow(
                                        name = r.title,
                                        url = r.url,
                                        isFileHint = r.isFile,
                                        snackbarHostState = sheetSnackbar,
                                    )
                                }
                            }
                        }
                        if (detail.participants.isNotEmpty()) {
                            DetailSection(stringResource(R.string.lesson_participants)) {
                                if (teachers.isNotEmpty()) {
                                    Text(
                                        stringResource(R.string.lesson_participants_teachers),
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(bottom = 4.dp),
                                    )
                                    teachers.forEach { p -> LessonParticipantRow(p) }
                                }
                                if (students.isNotEmpty()) {
                                    if (teachers.isNotEmpty()) Spacer(Modifier.height(8.dp))
                                    Text(
                                        stringResource(R.string.lesson_participants_students),
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(bottom = 4.dp),
                                    )
                                    students.forEach { p -> LessonParticipantRow(p) }
                                }
                                otherParticipants.forEach { p -> LessonParticipantRow(p) }
                            }
                        }
                    }

                    if (viewModel.canEditPrivateEvent(event)) {
                        Spacer(Modifier.height(16.dp))
                        TextButton(
                            onClick = { viewModel.openEditPrivateEvent(event) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(stringResource(R.string.private_event_edit))
                        }
                    }
                    if (viewModel.canDeleteEvent(event)) {
                        Spacer(Modifier.height(8.dp))
                        TextButton(
                            onClick = { viewModel.deletePrivateEvent(event) },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(stringResource(R.string.private_event_delete))
                        }
                    }
                }
            }
            SnackbarHost(
                hostState = sheetSnackbar,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
            }
        }
    }

    if (state.showPrivateEvent) {
        ModalBottomSheet(onDismissRequest = viewModel::closePrivateEventSheet) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    if (state.editingPrivateEventId != null) {
                        stringResource(R.string.private_event_edit_title)
                    } else {
                        stringResource(R.string.private_event_title)
                    },
                    style = MaterialTheme.typography.headlineSmall,
                )
                OutlinedTextField(
                    value = state.privateTitle,
                    onValueChange = { viewModel.updatePrivateField(title = it) },
                    label = { Text(stringResource(R.string.private_event_name)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.privateStartDate,
                    onValueChange = { viewModel.updatePrivateField(startDate = it) },
                    label = { Text(stringResource(R.string.private_event_start_date)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.privateStartTime,
                    onValueChange = { viewModel.updatePrivateField(startTime = it) },
                    label = { Text(stringResource(R.string.private_event_start_time)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.privateEndDate,
                    onValueChange = { viewModel.updatePrivateField(endDate = it) },
                    label = { Text(stringResource(R.string.private_event_end_date)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.privateEndTime,
                    onValueChange = { viewModel.updatePrivateField(endTime = it) },
                    label = { Text(stringResource(R.string.private_event_end_time)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.privateNote,
                    onValueChange = { viewModel.updatePrivateField(note = it) },
                    label = { Text(stringResource(R.string.private_event_note)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                state.message?.let { Text(it.asString(), color = MaterialTheme.colorScheme.primary) }
                Button(onClick = viewModel::savePrivateEvent, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.private_event_save))
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    if (nudgeVisible) {
        ModalBottomSheet(onDismissRequest = viewModel::dismissReferralNudge) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    stringResource(R.string.referral_nudge_title),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    stringResource(
                        R.string.referral_nudge_body,
                        viewModel.referralNudgeRemaining().coerceAtLeast(1),
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = {
                        val url = viewModel.referralShareUrl() ?: return@Button
                        val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(
                                android.content.Intent.EXTRA_TEXT,
                                context.getString(R.string.referral_share_text, url),
                            )
                        }
                        context.startActivity(
                            android.content.Intent.createChooser(
                                send,
                                context.getString(R.string.referral_share_chooser),
                            ),
                        )
                        viewModel.onReferralNudgeShared()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.referral_nudge_share))
                }
                TextButton(
                    onClick = viewModel::dismissReferralNudge,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.referral_nudge_dismiss))
                }
            }
        }
    }
}

@Composable
private fun DayPageContent(
    date: LocalDate,
    events: List<ScheduleEvent>,
    calendarStyle: CalendarStyle,
    viewModel: ScheduleViewModel,
) {
    if (calendarStyle == CalendarStyle.PROFESSIONAL) {
        TimelineDayView(
            date = date,
            events = events,
            displayTitle = { viewModel.displayTitle(it) },
            accentFor = { Color(viewModel.accentArgbFor(it)) },
            onEventClick = { viewModel.selectEvent(it) },
            modifier = Modifier.fillMaxSize(),
        )
    } else {
        StandardDayList(
            events = events,
            displayTitle = { viewModel.displayTitle(it) },
            accentFor = { Color(viewModel.accentArgbFor(it)) },
            onEventClick = { viewModel.selectEvent(it) },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

// ── Live lesson header (iOS ScheduleHeaderView) ──────────────────────────────

private data class LiveHeaderUi(
    val subjectName: String,
    val room: String?,
    val minutes: Int,
    val progress: Float?,
    val isUpcoming: Boolean,
)

private fun computeLiveHeader(
    events: List<ScheduleEvent>,
    now: LocalDateTime,
    displayTitle: (ScheduleEvent) -> String,
): LiveHeaderUi? {
    val projection = LiveLessonBoundary.project(events, now) ?: return null
    return LiveHeaderUi(
        subjectName = displayTitle(projection.event),
        room = projection.event.room,
        minutes = projection.minutesRemaining,
        progress = projection.progress,
        isUpcoming = projection.phase == LiveLessonBoundary.Phase.UPCOMING,
    )
}

@Composable
private fun LiveLessonHeader(header: LiveHeaderUi?) {
    if (header == null) return

    Column(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 20.dp)
            .padding(top = 4.dp, bottom = 16.dp),
    ) {
        androidx.compose.foundation.layout.Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            androidx.compose.foundation.layout.Row(
                modifier = Modifier.weight(1f, fill = false),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    header.subjectName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                )
                header.room?.takeIf { it.isNotBlank() }?.let { room ->
                    Text(
                        "·",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Light,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        room,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                }
            }
            Text(
                if (header.isUpcoming) {
                    stringResource(R.string.schedule_in_minutes, header.minutes)
                } else {
                    stringResource(R.string.schedule_minutes_left, header.minutes)
                },
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }

        header.progress?.let { progress ->
            Spacer(Modifier.height(12.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(RoundedCornerShape(50))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(progress.coerceIn(0f, 1f))
                        .height(6.dp)
                        .clip(RoundedCornerShape(50))
                        .background(MaterialTheme.colorScheme.primary),
                )
            }
        }
    }
}

@Composable
private fun LessonParticipantRow(participant: LessonParticipant) {
    AppListRow(
        leading = {
            PersonAvatar(
                name = participant.name,
                size = 36.dp,
                entityId = participant.id,
                kind = participant.kind,
                knownUrl = participant.avatarUrl,
            )
        },
    ) {
        AppListPrimary(participant.name, emphasized = true)
        participant.role?.takeIf { it.isNotBlank() }?.let { role ->
            Text(
                role,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
