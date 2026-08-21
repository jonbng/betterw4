package dk.betterw4.android.ui.screens.absence

import android.app.DatePickerDialog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterw4.android.R
import dk.betterw4.android.core.FeatureFlags
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.feature.absence.AbsenceRegistration
import dk.betterw4.android.feature.absence.AbsenceSource
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListMeta
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.ErrorBox
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.SectionHeader
import dk.betterw4.android.ui.components.W4ChromeActions
import dk.betterw4.android.ui.components.W4WebSheet
import dk.betterw4.android.ui.components.W4WebTarget
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AbsenceScreen(
    viewModel: AbsenceViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var selectedLesson by remember { mutableStateOf<ScheduleEvent?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tab_absence)) },
                actions = {
                    if (!state.isDemo) {
                        IconButton(onClick = viewModel::openRegister) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = stringResource(R.string.absence_register),
                            )
                        }
                    }
                    W4ChromeActions()
                },
            )
        },
    ) { padding ->
        when {
            state.error != null && state.overview == null -> {
                ErrorBox(
                    state.error,
                    onRetry = { viewModel.refresh(true) },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                )
            }
            else -> {
                PullToRefreshBox(
                    isRefreshing = state.loading && state.overview != null,
                    onRefresh = { viewModel.refresh(true) },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    if (state.loading && state.overview == null) {
                        LoadingBox(Modifier.fillMaxSize())
                    } else {
                        AbsenceBody(
                            viewModel = viewModel,
                            state = state,
                            onOpenLesson = { selectedLesson = it },
                        )
                    }
                }
            }
        }
    }

    if (state.showRegister) {
        RegisterAbsenceSheet(viewModel = viewModel, state = state)
    }
    selectedLesson?.let { lesson ->
        LessonDetailSheet(lesson = lesson, onDismiss = { selectedLesson = null })
    }
    W4WebSheet(
        target = if (state.showWebFallback) {
            W4WebTarget(
                title = stringResource(R.string.absence_register),
                url = W4Urls.resolve(
                    W4Urls.Routes.ABSENCES_REGISTER,
                    state.registerForm?.dateRaw?.let { mapOf("date" to it) }.orEmpty(),
                ).toString(),
            )
        } else {
            null
        },
        onDismiss = viewModel::closeWebFallback,
    )
}

@Composable
private fun AbsenceBody(
    viewModel: AbsenceViewModel,
    state: AbsenceUiState,
    onOpenLesson: (ScheduleEvent) -> Unit,
) {
    val overview = state.overview
    Column(Modifier.fillMaxSize()) {
        SectionHeader(stringResource(R.string.absence_overview))
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            MeterCard(
                header = stringResource(R.string.absence_meter_academics),
                absences = overview?.academicMeter?.absences ?: 0,
                latenesses = overview?.academicMeter?.latenesses ?: 0,
                modifier = Modifier.weight(1f),
            )
            MeterCard(
                header = stringResource(R.string.absence_meter_ea),
                absences = overview?.eaMeter?.absences ?: 0,
                latenesses = overview?.eaMeter?.latenesses ?: 0,
                modifier = Modifier.weight(1f),
            )
        }
        PrimaryTabRow(selectedTabIndex = if (state.source == AbsenceSource.ACADEMICS) 0 else 1) {
            Tab(
                selected = state.source == AbsenceSource.ACADEMICS,
                onClick = { viewModel.setSource(AbsenceSource.ACADEMICS) },
                text = { Text(stringResource(R.string.absence_meter_academics)) },
            )
            Tab(
                selected = state.source == AbsenceSource.EA,
                onClick = { viewModel.setSource(AbsenceSource.EA) },
                text = { Text(stringResource(R.string.absence_meter_ea)) },
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(
                selected = state.mode == AbsenceViewMode.WEEK,
                onClick = { viewModel.setMode(AbsenceViewMode.WEEK) },
                label = { Text(stringResource(R.string.absence_view_week)) },
            )
            FilterChip(
                selected = state.mode == AbsenceViewMode.LIST,
                onClick = { viewModel.setMode(AbsenceViewMode.LIST) },
                label = { Text(stringResource(R.string.absence_view_list)) },
            )
        }
        when (state.mode) {
            AbsenceViewMode.WEEK -> WeekPane(
                viewModel = viewModel,
                state = state,
                onOpenLesson = onOpenLesson,
            )
            AbsenceViewMode.LIST -> ListPane(rows = viewModel.listForSource())
        }
    }
}

@Composable
private fun MeterCard(
    header: String,
    absences: Int,
    latenesses: Int,
    modifier: Modifier = Modifier,
) {
    Column(modifier) {
        Text(header, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
        Text("${stringResource(R.string.absence_meter_absences)}  $absences")
        Text("${stringResource(R.string.absence_meter_lateness)}  $latenesses")
    }
}

@Composable
private fun WeekPane(
    viewModel: AbsenceViewModel,
    state: AbsenceUiState,
    onOpenLesson: (ScheduleEvent) -> Unit,
) {
    val week = viewModel.weekForSource()
    val dateFmt = DateTimeFormatter.ofPattern("EEE d MMM", Locale.getDefault())
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { viewModel.shiftWeek(-1) }) {
                Icon(Icons.Default.ChevronLeft, contentDescription = null)
            }
            Text(
                text = week?.let { "Week ${it.week}" } ?: stringResource(R.string.absence_week, IsoWeekLabel(state.selectedDate)),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.titleMedium,
            )
            IconButton(onClick = { viewModel.shiftWeek(1) }) {
                Icon(Icons.Default.ChevronRight, contentDescription = null)
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            val days = week?.days.orEmpty()
            if (days.isEmpty()) {
                Text(
                    state.selectedDate.format(dateFmt),
                    modifier = Modifier.padding(8.dp),
                )
            } else {
                days.forEach { day ->
                    val selected = day.date == state.selectedDate
                    Text(
                        text = day.date.dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()),
                        modifier = Modifier
                            .clickable { viewModel.selectDate(day.date) }
                            .padding(8.dp),
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                        color = if (selected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                    )
                }
            }
        }
        val lessons = viewModel.lessonsOnSelectedDay()
        if (lessons.isEmpty()) {
            Text(
                stringResource(R.string.absence_empty_week),
                modifier = Modifier.padding(24.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            LazyColumn(Modifier.fillMaxSize()) {
                items(lessons, key = { it.id }) { event ->
                    LessonRow(
                        event = event,
                        status = viewModel.attendanceLabel(event.attendance),
                        onClick = { onOpenLesson(event) },
                    )
                    AppListDivider()
                }
            }
        }
    }
}

@Composable
private fun IsoWeekLabel(date: java.time.LocalDate): String =
    dk.betterw4.android.core.util.IsoDateUtils.isoWeek(date).toString()

@Composable
private fun LessonRow(event: ScheduleEvent, status: String, onClick: () -> Unit) {
    AppListRow(onClick = onClick) {
        AppListPrimary(event.title, emphasized = true)
        val time = listOfNotNull(
            event.start?.let { "%02d:%02d".format(it.hour, it.minute) },
            event.end?.let { "%02d:%02d".format(it.hour, it.minute) },
        ).joinToString(" – ")
        if (time.isNotBlank()) AppListMeta(time)
        Surface(
            shape = RoundedCornerShape(999.dp),
            color = MaterialTheme.colorScheme.secondaryContainer,
        ) {
            Text(
                status,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                style = MaterialTheme.typography.labelMedium,
            )
        }
        event.room?.takeIf { it.isNotBlank() }?.let { AppListMeta(it) }
    }
}

@Composable
private fun ListPane(rows: List<AbsenceRegistration>) {
    if (rows.isEmpty()) {
        Text(
            stringResource(R.string.absence_empty_list),
            modifier = Modifier.padding(24.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        return
    }
    val groups = rows.groupBy { it.dateTimeLabel.substringBefore(' ').ifBlank { "Unknown date" } }
    LazyColumn(Modifier.fillMaxSize()) {
        groups.forEach { (date, datedRows) ->
            item(key = "header-$date") { SectionHeader(date) }
            items(datedRows, key = { it.id }) { row ->
            AppListRow(onClick = null) {
                AppListPrimary(row.team.ifBlank { row.cause }, emphasized = true)
                if (row.dateTimeLabel.isNotBlank()) AppListMeta(row.dateTimeLabel)
                row.studentWas.takeIf { it.isNotBlank() }?.let {
                    AppListSecondary("Student was: $it")
                }
                row.cause.takeIf { it.isNotBlank() && it != row.studentWas }?.let {
                    AppListSecondary("Type: $it")
                }
                row.note.takeIf { it.isNotBlank() }?.let {
                    AppListSecondary("Reason: $it")
                }
                if (row.addedBy.isNotBlank()) AppListMeta("Added by: ${row.addedBy}")
            }
            AppListDivider()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LessonDetailSheet(lesson: ScheduleEvent, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(lesson.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            lesson.teacher?.takeIf { it.isNotBlank() }?.let { Text(it) }
            lesson.room?.takeIf { it.isNotBlank() }?.let { Text(it) }
            lesson.attendanceLabel?.takeIf { it.isNotBlank() }?.let { Text(it) }
            lesson.attendanceTooltip?.takeIf { it.isNotBlank() }?.let { Text(it) }
            lesson.notes?.takeIf { it.isNotBlank() }?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RegisterAbsenceSheet(
    viewModel: AbsenceViewModel,
    state: AbsenceUiState,
) {
    val context = LocalContext.current
    ModalBottomSheet(onDismissRequest = viewModel::closeRegister) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.absence_register),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            if (state.registerLoading && state.registerForm == null) {
                LoadingBox(Modifier.height(120.dp))
                return@Column
            }
            val form = state.registerForm
            if (form == null) {
                Text(
                    state.registerError ?: stringResource(R.string.absence_register_hint),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                return@Column
            }
            val parsedDate = W4Dates.parse(form.dateRaw) ?: W4Dates.today()
            TextButton(
                onClick = {
                    DatePickerDialog(
                        context,
                        { _, year, month, day ->
                            viewModel.setRegisterDate(W4Dates.format(LocalDate.of(year, month + 1, day)))
                        },
                        parsedDate.year,
                        parsedDate.monthValue - 1,
                        parsedDate.dayOfMonth,
                    ).show()
                },
            ) { Text(form.dateRaw) }
            if (form.isEmptyDay) {
                Text(
                    form.emptyDayMessage
                        ?: stringResource(R.string.absence_register_empty_day),
                )
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = state.wholeDay,
                        onCheckedChange = viewModel::setWholeDay,
                    )
                    Text(stringResource(R.string.absence_register_whole_day))
                }
                form.slots.forEach { slot ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Checkbox(
                            checked = state.wholeDay || slot.value in state.selectedSlots,
                            onCheckedChange = { viewModel.toggleSlot(slot.value) },
                            enabled = !slot.disabled && !state.wholeDay,
                        )
                        Text(slot.label, modifier = Modifier.weight(1f))
                    }
                }
                OutlinedTextField(
                    value = state.reason,
                    onValueChange = viewModel::setReason,
                    label = { Text(stringResource(R.string.absence_register_reason)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                state.registerError?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
                if (FeatureFlags.ABSENCE_WRITES_ENABLED) {
                    TextButton(
                        onClick = viewModel::submitRegister,
                        enabled = !state.registerLoading &&
                            state.reason.isNotBlank() &&
                            (state.wholeDay || state.selectedSlots.isNotEmpty()),
                    ) {
                        Text(stringResource(R.string.absence_register_submit))
                    }
                }
            }
            if (state.registerError != null) {
                TextButton(onClick = viewModel::openWebFallback) {
                    Text(stringResource(R.string.absence_open_w4))
                }
            }
        }
    }
}
