package dk.betterw4.android.ui.screens.schedule

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterw4.android.R
import dk.betterw4.android.core.FeatureFlags
import dk.betterw4.android.core.i18n.asString
import dk.betterw4.android.core.i18n.resolve
import dk.betterw4.android.feature.live.LiveLessonBoundary
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.LessonParticipant
import dk.betterw4.android.ui.screens.more.StudentProfileScreen
import dk.betterw4.android.feature.schedule.CustomEvents
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.SchoolCalendar
import dk.betterw4.android.feature.schedule.statusLabelText
import dk.betterw4.android.feature.schedule.timeLabelText
import dk.betterw4.android.feature.settings.CalendarStyle
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AttachmentRow
import dk.betterw4.android.ui.components.DateStrip
import dk.betterw4.android.ui.components.DateStripDay
import dk.betterw4.android.ui.components.DetailSection
import dk.betterw4.android.ui.components.DetailSheetHeader
import dk.betterw4.android.ui.components.DetailSheetPadding
import dk.betterw4.android.ui.components.ErrorBox
import dk.betterw4.android.ui.components.LessonContentBlocks
import dk.betterw4.android.ui.components.ScheduleDaySkeleton
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.StatusChip
import dk.betterw4.android.ui.components.W4ChromeActions
import dk.betterw4.android.ui.theme.BetterW4ThemeExtras
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
    onOpenMail: () -> Unit = {},
    onOpenAssessments: () -> Unit = {},
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val calendarStyle by viewModel.calendarStyle.collectAsStateWithLifecycle()
    val showSchoolCalendar by viewModel.showSchoolCalendar.collectAsStateWithLifecycle()
    // Subscribe so bricks recompose when lesson mappings / color mode change.
    @Suppress("UNUSED_VARIABLE")
    val lessonMappings by viewModel.lessonMappings.collectAsStateWithLifecycle()
    @Suppress("UNUSED_VARIABLE")
    val useSubjectColors by viewModel.useSubjectColors.collectAsStateWithLifecycle()
    val extended = BetterW4ThemeExtras.extendedColors

    val now = rememberW4Now()
    val today = now.toLocalDate()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var confirmDelete by remember { mutableStateOf<ScheduleEvent?>(null) }

    LaunchedEffect(state.message) {
        val message = state.message ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message.resolve(context))
        viewModel.consumeMessage()
    }

    // Opening the tab (and re-tapping it) always shows today, not the last
    // day the student browsed. `today` is also a key so a midnight rollover
    // while the tab is open follows the new Oslo day.
    LaunchedEffect(scrollToTopToken, today) {
        viewModel.selectDate(today)
    }
    LaunchedEffect(state.pendingNotificationHref) {
        val href = state.pendingNotificationHref ?: return@LaunchedEffect
        viewModel.consumeNotificationHref()
        when {
            FeatureFlags.MAIL_ENABLED && href.contains("mailer", ignoreCase = true) -> onOpenMail()
            href.contains("deadline", ignoreCase = true) ||
                href.contains("assessment", ignoreCase = true) -> onOpenAssessments()
        }
    }
    val liveHeader = remember(state.eventsByDate, now, showSchoolCalendar) {
        computeLiveHeader(
            events = viewModel.visibleEvents(
                state.eventsByDate[today].orEmpty()
                    .ifEmpty {
                        state.week?.days?.find { it.date == today }?.events.orEmpty()
                    },
            ),
            now = now,
            displayTitle = viewModel::displayTitle,
        )
    }

    val locale = Locale.getDefault()
    val dayName = state.selectedDate.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
        .replaceFirstChar { if (it.isLowerCase()) it.titlecase(locale) else it.toString() }
    val subtitle = stringResource(R.string.schedule_week_subtitle, dayName, state.weekNum)
    val isAwayFromToday = state.selectedDate != today

    Scaffold(
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
                    IconButton(onClick = viewModel::openPrivateEventSheet) {
                        Icon(
                            Icons.Default.Add,
                            contentDescription = stringResource(R.string.cd_add_custom_event),
                        )
                    }
                    IconButton(
                        onClick = { viewModel.setShowSchoolCalendar(!showSchoolCalendar) },
                    ) {
                        Icon(
                            if (showSchoolCalendar) {
                                Icons.Filled.CalendarMonth
                            } else {
                                Icons.Outlined.CalendarMonth
                            },
                            contentDescription = stringResource(
                                if (showSchoolCalendar) {
                                    R.string.cd_hide_school_calendar
                                } else {
                                    R.string.cd_show_school_calendar
                                },
                            ),
                            tint = if (showSchoolCalendar) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                    W4ChromeActions(
                        onNotificationHref = { href ->
                            when {
                                href.isNullOrBlank() -> Unit
                                FeatureFlags.MAIL_ENABLED &&
                                    href.contains("mailer", ignoreCase = true) -> onOpenMail()
                                href.contains("deadline", ignoreCase = true) ||
                                    href.contains("assessment", ignoreCase = true) -> onOpenAssessments()
                            }
                        },
                    )
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
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.loading && state.week != null,
            onRefresh = { viewModel.refresh(true) },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
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
                                        hasEvents = viewModel.visibleEvents(day.events).isNotEmpty(),
                                    )
                                },
                                selected = state.selectedDate,
                                onSelect = viewModel::selectDate,
                                onWeekChanged = viewModel::selectDate,
                                hasEvents = { date ->
                                    val events = when {
                                        date in eventsByDate -> eventsByDate[date].orEmpty()
                                        else -> weekDays.find { it.date == date }?.events.orEmpty()
                                    }
                                    if (events.isEmpty() && date in knownEmptyDays) {
                                        false
                                    } else {
                                        viewModel.visibleEvents(events).isNotEmpty()
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
                            when {
                                viewModel.isDayLoaded(date) -> {
                                    val events = state.eventsByDate[date]
                                        ?: state.week?.days?.find { it.date == date }?.events
                                        ?: emptyList()
                                    DayPageContent(
                                        date = date,
                                        events = viewModel.visibleEvents(events),
                                        calendarStyle = calendarStyle,
                                        viewModel = viewModel,
                                        now = now,
                                    )
                                }
                                viewModel.isDayLoading(date) || state.loading -> ScheduleDaySkeleton()
                                else -> EmptyDayState(
                                    message = stringResource(R.string.schedule_pull_to_load),
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Lesson detail sheet
    state.selectedEvent?.let { event ->
        if (CustomEvents.isCustomEvent(event) && state.selectedPerson == null) {
            ModalBottomSheet(onDismissRequest = { viewModel.selectEvent(null) }) {
                CustomEventDetail(
                    event = event,
                    title = viewModel.displayTitle(event),
                    onEdit = { viewModel.openEditPrivateEvent(event) },
                    onDelete = { confirmDelete = event },
                )
            }
            return@let
        }
        val accent = Color(viewModel.accentArgbFor(event))
        val statusColor = when (event.status) {
            EventStatus.CHANGED -> extended.statusChanged
            EventStatus.CANCELLED -> extended.statusCancelled
            EventStatus.NORMAL -> extended.statusNormal
        }
        val sheetSnackbar = remember { SnackbarHostState() }
        ModalBottomSheet(onDismissRequest = {
            if (state.selectedPerson != null) viewModel.closePerson()
            else viewModel.selectEvent(null)
        }) {
            val person = state.selectedPerson
            if (person != null) {
                BackHandler { viewModel.closePerson() }
                Column(Modifier.fillMaxWidth().fillMaxHeight(0.92f)) {
                    TextButton(onClick = { viewModel.closePerson() }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                        Text(stringResource(R.string.cd_back))
                    }
                    StudentProfileScreen(
                        loading = state.personLoading,
                        entity = person,
                        profile = state.studentProfile,
                        week = state.personSchedule,
                        weekNumber = state.personWeek,
                        weekYear = state.personWeekYear,
                        pinned = state.pinnedIds.contains(person.id),
                        defaultCalendarStyle = calendarStyle,
                        displayTitle = viewModel::displayTitle,
                        accentFor = { Color(viewModel.accentArgbFor(it)) },
                        onWriteMessage = {},
                        onTogglePin = viewModel::togglePersonPin,
                        onOpenAdvisor = viewModel::openPerson,
                        onPrevWeek = { viewModel.shiftPersonWeek(-1) },
                        onNextWeek = { viewModel.shiftPersonWeek(1) },
                        onGoToToday = viewModel::goToPersonToday,
                        onLoadWeekForDate = viewModel::loadPersonWeekForDate,
                    )
                }
            } else Box(Modifier.fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
            ) {
                DetailSheetPadding {
                    DetailSheetHeader(
                        title = viewModel.displayTitle(event),
                        subtitle = event.timeLabelText(),
                        meta = listOfNotNull(
                            if (SchoolCalendar.isSchoolCalendarEvent(event)) {
                                stringResource(R.string.school_calendar_team)
                            } else {
                                event.teacher
                            },
                            event.room,
                        ).joinToString(" · ").ifBlank { null },
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
                            it.kind == DirectoryEntityKind.TEACHER
                        }
                        val students = detail.participants.filter {
                            it.kind == DirectoryEntityKind.STUDENT
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
                                    teachers.forEach { p ->
                                        LessonParticipantRow(p) { viewModel.openPerson(p.toEntity()) }
                                    }
                                }
                                if (students.isNotEmpty()) {
                                    if (teachers.isNotEmpty()) Spacer(Modifier.height(8.dp))
                                    Text(
                                        stringResource(R.string.lesson_participants_students),
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(bottom = 4.dp),
                                    )
                                    students.forEach { p ->
                                        LessonParticipantRow(p) { viewModel.openPerson(p.toEntity()) }
                                    }
                                }
                                otherParticipants.forEach { p ->
                                    LessonParticipantRow(p) { viewModel.openPerson(p.toEntity()) }
                                }
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
                            onClick = { confirmDelete = event },
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

    confirmDelete?.let { event ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text(stringResource(R.string.private_event_delete)) },
            text = { Text(stringResource(R.string.private_event_delete_confirm)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmDelete = null
                        viewModel.deletePrivateEvent(event)
                    },
                ) {
                    Text(stringResource(R.string.private_event_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }

    if (state.showPrivateEvent) {
        ModalBottomSheet(onDismissRequest = viewModel::closePrivateEventSheet) {
            val titleFocus = remember { FocusRequester() }
            val keyboard = LocalSoftwareKeyboardController.current
            LaunchedEffect(Unit) { titleFocus.requestFocus() }
            Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = viewModel::closePrivateEventSheet) {
                        Text(stringResource(R.string.action_cancel))
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        if (state.editingPrivateEventId != null) {
                            stringResource(R.string.private_event_edit_title)
                        } else {
                            stringResource(R.string.private_event_title)
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = viewModel::savePrivateEvent,
                        enabled = state.privateTitle.isNotBlank(),
                    ) {
                        Text(stringResource(R.string.private_event_save), fontWeight = FontWeight.SemiBold)
                    }
                }
                Text(
                    stringResource(R.string.private_event_device_note),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                )
                OutlinedTextField(
                    value = state.privateTitle,
                    onValueChange = { viewModel.updatePrivateField(title = it) },
                    placeholder = { Text(stringResource(R.string.private_event_name_hint)) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(titleFocus),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = {
                            keyboard?.hide()
                            viewModel.savePrivateEvent()
                        },
                    ),
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(R.string.private_event_all_day),
                        modifier = Modifier.weight(1f),
                    )
                    Switch(
                        checked = state.privateAllDay,
                        onCheckedChange = { viewModel.updatePrivateField(allDay = it) },
                    )
                }
                DateTimeField(
                    label = stringResource(R.string.private_event_start),
                    value = state.privateStart,
                    allDay = state.privateAllDay,
                    onValueChange = { viewModel.updatePrivateField(start = it) },
                )
                DateTimeField(
                    label = stringResource(R.string.private_event_end),
                    value = state.privateEnd,
                    allDay = state.privateAllDay,
                    onValueChange = { viewModel.updatePrivateField(end = it) },
                )
                OutlinedTextField(
                    value = state.privateNote,
                    onValueChange = { viewModel.updatePrivateField(note = it) },
                    placeholder = { Text(stringResource(R.string.private_event_note)) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                )
                state.message?.let { Text(it.asString(), color = MaterialTheme.colorScheme.error) }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun CustomEventDetail(
    event: ScheduleEvent,
    title: String,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(
            event.timeLabelText(),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            stringResource(R.string.private_event_on_device),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        val notes = event.notes?.trim().orEmpty()
        if (notes.isNotEmpty()) {
            Text(notes, style = MaterialTheme.typography.bodyMedium)
        }
        Spacer(Modifier.height(8.dp))
        Button(onClick = onEdit, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.private_event_edit))
        }
        TextButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.private_event_delete))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateTimeField(
    label: String,
    value: LocalDateTime,
    allDay: Boolean,
    onValueChange: (LocalDateTime) -> Unit,
) {
    var pickingDate by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf(false) }
    val locale = Locale.getDefault()
    val dateFmt = remember(locale) { DateTimeFormatter.ofPattern("EEE d MMM yyyy", locale) }
    val timeFmt = remember { DateTimeFormatter.ofPattern("HH:mm") }

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                value.toLocalDate().format(dateFmt),
                modifier = Modifier
                    .weight(1f)
                    .clickable { pickingDate = true }
                    .padding(vertical = 8.dp),
                style = MaterialTheme.typography.bodyLarge,
            )
            if (!allDay) {
                Text(
                    value.toLocalTime().format(timeFmt),
                    modifier = Modifier
                        .clickable { pickingTime = true }
                        .padding(vertical = 8.dp),
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        }
    }

    if (pickingDate) {
        val dateState = rememberDatePickerState(
            initialSelectedDateMillis = value.toLocalDate().toUtcMillis(),
        )
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        val millis = dateState.selectedDateMillis
                        if (millis != null) {
                            onValueChange(
                                LocalDateTime.of(millis.toUtcLocalDate(), value.toLocalTime()),
                            )
                        }
                        pickingDate = false
                    },
                ) { Text(stringResource(R.string.action_ok)) }
            },
            dismissButton = {
                TextButton(onClick = { pickingDate = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        ) {
            DatePicker(state = dateState)
        }
    }

    if (pickingTime) {
        val timeState = rememberTimePickerState(
            initialHour = value.hour,
            initialMinute = value.minute,
            is24Hour = true,
        )
        AlertDialog(
            onDismissRequest = { pickingTime = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        onValueChange(
                            LocalDateTime.of(
                                value.toLocalDate(),
                                LocalTime.of(timeState.hour, timeState.minute),
                            ),
                        )
                        pickingTime = false
                    },
                ) { Text(stringResource(R.string.action_ok)) }
            },
            dismissButton = {
                TextButton(onClick = { pickingTime = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
            text = { TimePicker(state = timeState) },
        )
    }
}

private fun LocalDate.toUtcMillis(): Long =
    atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

private fun Long.toUtcLocalDate(): LocalDate =
    Instant.ofEpochMilli(this).atZone(ZoneOffset.UTC).toLocalDate()

@Composable
private fun DayPageContent(
    date: LocalDate,
    events: List<ScheduleEvent>,
    calendarStyle: CalendarStyle,
    viewModel: ScheduleViewModel,
    now: LocalDateTime,
) {
    if (calendarStyle == CalendarStyle.PROFESSIONAL) {
        TimelineDayView(
            date = date,
            events = events,
            displayTitle = { viewModel.displayTitle(it) },
            accentFor = { Color(viewModel.accentArgbFor(it)) },
            onEventClick = { viewModel.selectEvent(it) },
            onAddAt = { viewModel.openPrivateEventSheet(at = it) },
            modifier = Modifier.fillMaxSize(),
            now = now,
        )
    } else {
        StandardDayList(
            events = events,
            displayTitle = { viewModel.displayTitle(it) },
            accentFor = { Color(viewModel.accentArgbFor(it)) },
            onEventClick = { viewModel.selectEvent(it) },
            onAdd = { viewModel.openPrivateEventSheet() },
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
private fun LessonParticipantRow(
    participant: LessonParticipant,
    onClick: () -> Unit,
) {
    AppListRow(
        onClick = onClick,
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
