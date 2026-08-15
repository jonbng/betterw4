package dk.betterlectio.android.ui.screens.more

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material.icons.filled.Grade
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import dk.betterlectio.android.R
import dk.betterlectio.android.core.i18n.asString
import dk.betterlectio.android.feature.absence.AbsenceChartSeries
import dk.betterlectio.android.feature.absence.AbsenceOverview
import dk.betterlectio.android.feature.absence.AbsencePresentation
import dk.betterlectio.android.feature.absence.AbsenceRegistration
import dk.betterlectio.android.feature.absence.AbsenceSummary
import dk.betterlectio.android.feature.directory.DirectoryEntity
import dk.betterlectio.android.feature.directory.DirectoryEntityKind
import dk.betterlectio.android.feature.grades.GradeAverage
import dk.betterlectio.android.feature.grades.GradeColumn
import dk.betterlectio.android.feature.grades.GradeNoteEntry
import dk.betterlectio.android.feature.referral.REFERRAL_UNLOCK_THRESHOLD
import dk.betterlectio.android.feature.referral.ReferralStats
import dk.betterlectio.android.feature.referral.referralUnlockProgress
import dk.betterlectio.android.feature.grades.GradeRow
import dk.betterlectio.android.feature.grades.GradeSubjectDetail
import dk.betterlectio.android.feature.messages.MessageRecipient
import dk.betterlectio.android.feature.schedule.timeLabelText
import dk.betterlectio.android.feature.settings.AppLanguage
import dk.betterlectio.android.feature.settings.AppearanceMode
import dk.betterlectio.android.feature.settings.CalendarStyle
import dk.betterlectio.android.feature.settings.SettingsStore
import dk.betterlectio.android.feature.studiekort.StudentCard
import dk.betterlectio.android.ui.components.AbsenceBarChart
import dk.betterlectio.android.ui.components.AbsenceRing
import dk.betterlectio.android.ui.components.AppListDivider
import dk.betterlectio.android.ui.components.AppListMeta
import dk.betterlectio.android.ui.components.AppListPrimary
import dk.betterlectio.android.ui.components.AppListRow
import dk.betterlectio.android.ui.components.AppListSecondary
import dk.betterlectio.android.ui.components.AvatarRepositoryEntryPoint
import dk.betterlectio.android.ui.components.DetailSheetHeader
import dk.betterlectio.android.ui.components.DetailSheetPadding
import dk.betterlectio.android.ui.components.EmptyBox
import dk.betterlectio.android.ui.components.InitialsAvatar
import dk.betterlectio.android.ui.components.LectioImagePreviewDialog
import dk.betterlectio.android.ui.components.PersonAvatar
import dk.betterlectio.android.ui.components.LoadingBox
import dk.betterlectio.android.ui.components.SectionHeader
import dk.betterlectio.android.ui.extension.ExtensionInviteSheet
import dagger.hilt.android.EntryPointAccessors
import java.time.format.TextStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MoreScreen(
    viewModel: MoreViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
    onComposeToPerson: ((MessageRecipient) -> Unit)? = null,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val appearance by viewModel.appearance.collectAsStateWithLifecycle()
    val language by viewModel.language.collectAsStateWithLifecycle()
    val calendarStyle by viewModel.calendarStyle.collectAsStateWithLifecycle()
    val useSubjectColors by viewModel.useSubjectColors.collectAsStateWithLifecycle()
    val notifEvents by viewModel.notifEvents.collectAsStateWithLifecycle()
    val notifMessages by viewModel.notifMessages.collectAsStateWithLifecycle()
    val notifAssignments by viewModel.notifAssignments.collectAsStateWithLifecycle()
    val disableSignature by viewModel.disableSignature.collectAsStateWithLifecycle()
    val lessonMappings by viewModel.lessonMappings.collectAsStateWithLifecycle()
    val notificationHistory by viewModel.notificationHistory.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    var showExtensionInvite by remember { mutableStateOf(false) }
    var showProfilePictureEditor by remember { mutableStateOf(false) }
    var directoryPhotoPreviewUrl by remember { mutableStateOf<String?>(null) }
    var directoryPhotoPreviewName by remember { mutableStateOf<String?>(null) }
    val avatarRepo = remember {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            AvatarRepositoryEntryPoint::class.java,
        ).avatarRepository()
    }
    fun previewDirectoryPersonPhoto(entity: DirectoryEntity) {
        if (entity.kind != DirectoryEntityKind.STUDENT &&
            entity.kind != DirectoryEntityKind.TEACHER
        ) {
            return
        }
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        scope.launch {
            val peeked = avatarRepo.peekUrl(
                entityId = entity.id,
                name = entity.name,
                knownUrl = entity.avatarUrl,
            ) ?: entity.avatarUrl
            val resolved = avatarRepo.resolveUrl(
                entityId = entity.id,
                name = entity.name,
                kind = entity.kind,
                knownUrl = peeked,
            ) ?: peeked
            if (!resolved.isNullOrBlank()) {
                directoryPhotoPreviewUrl = resolved
                directoryPhotoPreviewName = entity.name
            }
        }
    }
    val showBack = state.destination != MoreDestination.ROOT ||
        state.gradeDetail != null ||
        state.directoryParent != null ||
        state.personEntity != null ||
        state.planDetail != null ||
        state.roomEntity != null

    // System back / gesture: walk up More hierarchy instead of leaving the tab.
    BackHandler(enabled = showBack) {
        viewModel.back()
    }

    // Reselecting the More tab (or switching back to it after a sub-page visit)
    // always returns to the top-level menu and scrolls it into view.
    LaunchedEffect(scrollToTopToken) {
        if (scrollToTopToken > 0) {
            viewModel.popToRoot()
            listState.animateScrollToItem(0)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            state.gradeDetail != null -> state.gradeDetail!!.row.subject
                            state.planDetail != null -> state.planDetail!!.title
                            state.personEntity != null -> {
                                val displayName = state.studentProfile
                                    ?.displayName(state.personEntity!!.name)
                                    ?: state.personEntity!!.name
                                displayName
                            }
                            state.roomEntity != null -> state.roomEntity!!.name
                            state.directoryParent != null -> state.directoryParent!!.name
                            state.destination == MoreDestination.ROOT -> stringResource(R.string.tab_more)
                            state.destination == MoreDestination.GRADES -> stringResource(R.string.more_grades)
                            state.destination == MoreDestination.ABSENCE -> stringResource(R.string.more_absence)
                            state.destination == MoreDestination.DIRECTORY -> stringResource(R.string.more_directory)
                            state.destination == MoreDestination.ROOMS -> stringResource(R.string.more_rooms)
                            state.destination == MoreDestination.STUDIEKORT -> stringResource(R.string.more_studiekort)
                            state.destination == MoreDestination.PLANS -> stringResource(R.string.more_plans)
                            state.destination == MoreDestination.MODULE_STATS -> stringResource(R.string.more_module_stats)
                            state.destination == MoreDestination.TERM -> stringResource(R.string.more_term)
                            state.destination == MoreDestination.SETTINGS -> stringResource(R.string.more_settings)
                            state.destination == MoreDestination.REFERRAL -> stringResource(R.string.more_referral)
                            else -> stringResource(R.string.tab_more)
                        },
                    )
                },
                navigationIcon = {
                    if (showBack) {
                        IconButton(onClick = viewModel::back) {
                            Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                        }
                    }
                },
            )
        },
    ) { padding ->
        when (state.destination) {
            MoreDestination.ROOT -> MoreRoot(
                padding = padding,
                listState = listState,
                studentName = state.student?.name ?: state.student?.studentId.orEmpty(),
                classLabel = state.student?.classLabel,
                photoUrl = state.profilePhotoUrl,
                referralConversions = state.referralStats?.conversions,
                onNavigate = viewModel::navigate,
                onOpenCatalogKind = viewModel::openDirectoryKind,
                onOpenExtensionInvite = { showExtensionInvite = true },
                onEditProfilePicture = { showProfilePictureEditor = true },
                onOpenFeedback = viewModel::openFeedback,
                onLogout = viewModel::logout,
            )
            MoreDestination.GRADES -> {
                if (state.loading) LoadingBox(Modifier.padding(padding))
                else if (state.gradeDetail != null) {
                    GradesDetailContent(
                        detail = state.gradeDetail!!,
                        listState = listState,
                        modifier = Modifier.padding(padding),
                    )
                } else {
                    GradesOverviewContent(
                        report = state.gradesReport,
                        selectedColumnKey = state.selectedGradeColumnKey,
                        onSelectColumn = viewModel::setGradeColumnKey,
                        onOpenDetail = viewModel::openGradeDetail,
                        listState = listState,
                        modifier = Modifier.padding(padding),
                    )
                }
            }
            MoreDestination.ABSENCE -> {
                AbsenceScreenContent(
                    loading = state.loading,
                    overview = state.absence,
                    causes = viewModel.absenceCauses,
                    onSaveCause = viewModel::updateAbsenceCause,
                    modifier = Modifier.padding(padding),
                )
            }
            MoreDestination.DIRECTORY -> Column(Modifier.padding(padding).fillMaxSize()) {
                when {
                    state.personEntity != null -> {
                        val person = state.personEntity!!
                        if (person.kind == DirectoryEntityKind.STUDENT) {
                            StudentProfileScreen(
                                loading = state.loading,
                                entity = person,
                                profile = state.studentProfile,
                                week = state.personSchedule,
                                weekNumber = state.personWeek,
                                weekYear = state.personWeekYear,
                                pinned = state.pinnedIds.contains(person.id),
                                defaultCalendarStyle = calendarStyle,
                                displayTitle = viewModel::displayTitleForEvent,
                                accentFor = { Color(viewModel.accentArgbForEvent(it)) },
                                onWriteMessage = {
                                    viewModel.composeToPerson(person)
                                    onComposeToPerson?.invoke(
                                        MessageRecipient(
                                            id = person.id,
                                            name = state.studentProfile
                                                ?.displayName(person.name)
                                                ?: person.name,
                                            kind = person.kind.name,
                                        ),
                                    )
                                },
                                onTogglePin = { viewModel.togglePin(person) },
                                onViewClass = {
                                    val classEntity = person.copy(
                                        subtitle = state.studentProfile?.className
                                            ?.takeIf { it.isNotBlank() }
                                            ?: person.subtitle,
                                    )
                                    viewModel.openPersonClass(classEntity)
                                },
                                onPrevWeek = { viewModel.shiftPersonWeek(-1) },
                                onNextWeek = { viewModel.shiftPersonWeek(1) },
                                onGoToToday = viewModel::goToPersonToday,
                                onLoadWeekForDate = viewModel::loadPersonWeekForDate,
                            )
                        } else {
                            PersonSchedulePane(
                                loading = state.loading,
                                week = state.personSchedule,
                                weekNumber = state.personWeek,
                                weekYear = state.personWeekYear,
                                defaultCalendarStyle = calendarStyle,
                                displayTitle = viewModel::displayTitleForEvent,
                                accentFor = { Color(viewModel.accentArgbForEvent(it)) },
                                onPrevWeek = { viewModel.shiftPersonWeek(-1) },
                                onNextWeek = { viewModel.shiftPersonWeek(1) },
                                onGoToToday = viewModel::goToPersonToday,
                                onLoadWeekForDate = viewModel::loadPersonWeekForDate,
                                subtitle = person.subtitle,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                    state.roomEntity != null -> {
                        PersonSchedulePane(
                            loading = state.loading,
                            week = state.roomSchedule,
                            weekNumber = state.roomWeek,
                            weekYear = state.roomWeekYear,
                            defaultCalendarStyle = calendarStyle,
                            displayTitle = viewModel::displayTitleForEvent,
                            accentFor = { Color(viewModel.accentArgbForEvent(it)) },
                            onPrevWeek = { viewModel.shiftRoomWeek(-1) },
                            onNextWeek = { viewModel.shiftRoomWeek(1) },
                            onGoToToday = viewModel::goToRoomToday,
                            onLoadWeekForDate = viewModel::loadRoomWeekForDate,
                            subtitle = state.roomEntity!!.subtitle,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                    state.directoryParent != null -> {
                        if (state.loading) LoadingBox()
                        else LazyColumn(
                            state = listState,
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            item {
                                SectionHeader(
                                    stringResource(
                                        R.string.directory_members_of,
                                        state.directoryParent!!.name,
                                    ),
                                )
                            }
                            if (state.directoryMembers.isEmpty()) {
                                item {
                                    EmptyBox(
                                        text = stringResource(R.string.directory_no_members),
                                        description = stringResource(R.string.empty_directory_hint),
                                        icon = Icons.Default.People,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(280.dp),
                                    )
                                }
                            } else {
                                items(state.directoryMembers, key = { it.id }) { e ->
                                    val openPerson: () -> Unit = {
                                        when (e.kind) {
                                            DirectoryEntityKind.STUDENT -> {
                                                viewModel.openStudentProfile(e)
                                            }
                                            DirectoryEntityKind.TEACHER -> {
                                                viewModel.openPersonSheet(e)
                                            }
                                            else -> Unit
                                        }
                                    }
                                    AppListRow(
                                        onClick = openPerson,
                                        onLongClick = { previewDirectoryPersonPhoto(e) },
                                        leading = {
                                            PersonAvatar(entity = e)
                                        },
                                    ) {
                                        AppListPrimary(e.name, emphasized = true)
                                        val meta = listOfNotNull(
                                            e.kind.name.lowercase().replaceFirstChar { c -> c.uppercase() },
                                            e.subtitle,
                                        ).joinToString(" · ")
                                        if (meta.isNotBlank()) AppListSecondary(meta)
                                    }
                                    AppListDivider()
                                }
                            }
                        }
                    }
                    else -> {
                        Column(Modifier.fillMaxSize()) {
                            OutlinedTextField(
                                value = state.directoryQuery,
                                onValueChange = viewModel::onDirectoryQuery,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                                placeholder = { Text(stringResource(R.string.more_directory_search)) },
                                singleLine = true,
                                shape = RoundedCornerShape(28.dp),
                            )
                            FlowRow(
                                Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                FilterChip(
                                    selected = state.directoryKind == null,
                                    onClick = { viewModel.onDirectoryKind(null) },
                                    label = { Text(stringResource(R.string.filter_all)) },
                                )
                                DirectoryEntityKind.entries.take(6).forEach { kind ->
                                    FilterChip(
                                        selected = state.directoryKind == kind,
                                        onClick = { viewModel.onDirectoryKind(kind) },
                                        label = {
                                            Text(kind.name.lowercase().replaceFirstChar { it.uppercase() })
                                        },
                                    )
                                }
                            }
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                                thickness = 0.5.dp,
                            )
                            if (state.loading) LoadingBox()
                            else if (state.directory.isEmpty()) {
                                EmptyBox(
                                    text = stringResource(R.string.empty_directory),
                                    description = stringResource(R.string.empty_directory_hint),
                                    icon = Icons.Default.People,
                                    actionLabel = if (state.directoryQuery.isNotBlank()) {
                                        stringResource(R.string.cd_clear_search)
                                    } else {
                                        null
                                    },
                                    onAction = if (state.directoryQuery.isNotBlank()) {
                                        { viewModel.onDirectoryQuery("") }
                                    } else {
                                        null
                                    },
                                )
                            } else LazyColumn(
                                state = listState,
                                modifier = Modifier.fillMaxSize(),
                            ) {
                                val pinned = state.directory.filter { state.pinnedIds.contains(it.id) }
                                val rest = state.directory.filter { !state.pinnedIds.contains(it.id) }
                                fun onEntityClick(e: DirectoryEntity) {
                                    when (e.kind) {
                                        DirectoryEntityKind.CLASS, DirectoryEntityKind.HOLD ->
                                            viewModel.openDirectoryMembers(e)
                                        DirectoryEntityKind.ROOM ->
                                            viewModel.openRoomSchedule(e)
                                        DirectoryEntityKind.STUDENT ->
                                            viewModel.openStudentProfile(e)
                                        DirectoryEntityKind.TEACHER ->
                                            viewModel.openPersonSheet(e)
                                        else -> Unit
                                    }
                                }
                                fun onEntityLongClick(e: DirectoryEntity) {
                                    when (e.kind) {
                                        DirectoryEntityKind.STUDENT,
                                        DirectoryEntityKind.TEACHER,
                                        -> previewDirectoryPersonPhoto(e)
                                        else -> Unit
                                    }
                                }
                                if (pinned.isNotEmpty()) {
                                    item { SectionHeader(stringResource(R.string.directory_pinned)) }
                                    items(pinned, key = { "pin-${it.id}" }) { e ->
                                        DirectoryEntityRow(
                                            entity = e,
                                            pinned = true,
                                            onTogglePin = { viewModel.togglePin(e) },
                                            onClick = { onEntityClick(e) },
                                            onLongClick = { onEntityLongClick(e) },
                                        )
                                        AppListDivider()
                                    }
                                }
                                items(rest, key = { it.id }) { e ->
                                    DirectoryEntityRow(
                                        entity = e,
                                        pinned = false,
                                        onTogglePin = { viewModel.togglePin(e) },
                                        onClick = { onEntityClick(e) },
                                        onLongClick = { onEntityLongClick(e) },
                                    )
                                    AppListDivider()
                                }
                            }
                        }
                    }
                }
            }
            MoreDestination.ROOMS -> {
                if (state.roomEntity != null) {
                    if (state.loading) LoadingBox(Modifier.padding(padding))
                    else {
                        val week = state.roomSchedule
                        LazyColumn(
                            state = listState,
                            modifier = Modifier.padding(padding),
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            item {
                                Text(
                                    stringResource(R.string.room_schedule) +
                                        if (week != null) " · uge ${week.week}" else "",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                            if (week == null || week.days.all { it.events.isEmpty() }) {
                                item {
                                    Text(
                                        stringResource(R.string.room_schedule_empty),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            } else {
                                week.days.forEach { day ->
                                    if (day.events.isEmpty()) return@forEach
                                    item(key = "rday-${day.date}") {
                                        Text(
                                            day.date.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.getDefault()) +
                                                " ${day.date.dayOfMonth}/${day.date.monthValue}",
                                            style = MaterialTheme.typography.titleSmall,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.padding(top = 8.dp),
                                        )
                                    }
                                    items(day.events, key = { "re-${it.id}" }) { ev ->
                                        AppListRow {
                                            AppListPrimary(ev.title, emphasized = true)
                                            AppListSecondary(ev.timeLabelText())
                                            ev.teacher?.let { AppListMeta(it) }
                                        }
                                        AppListDivider()
                                    }
                                }
                            }
                        }
                    }
                } else if (state.loading) {
                    LoadingBox(Modifier.padding(padding))
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                    ) {
                        item { SectionHeader(stringResource(R.string.rooms_occupancy_header)) }
                        items(state.roomsOccupancy, key = { it.id }) { room ->
                            AppListRow(
                                onClick = { viewModel.openRoomFromOccupancy(room) },
                            ) {
                                AppListPrimary("${room.shortName} · ${room.name}", emphasized = true)
                                AppListSecondary(
                                    if (room.inUse) {
                                        stringResource(R.string.room_in_use)
                                    } else {
                                        stringResource(R.string.room_free)
                                    },
                                )
                            }
                            AppListDivider()
                        }
                    }
                }
            }
            MoreDestination.STUDIEKORT -> {
                val card = state.card
                if (card == null) {
                    LoadingBox(Modifier.padding(padding))
                } else {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(padding)
                            .padding(horizontal = 24.dp, vertical = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            FlipStudiekortCard(card = card)
                            androidx.compose.material3.OutlinedButton(
                                onClick = { showProfilePictureEditor = true },
                            ) {
                                Icon(Icons.Default.Edit, contentDescription = null)
                                Spacer(Modifier.size(8.dp))
                                Text(stringResource(R.string.profile_picture_edit))
                            }
                            state.message?.let {
                                Text(
                                    it.asString(),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }
                }
            }
            MoreDestination.PLANS -> {
                if (state.loading && state.planDetail == null) {
                    LoadingBox(Modifier.padding(padding))
                } else if (state.planDetail != null) {
                    val plan = state.planDetail!!
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                    ) {
                        item {
                            Column(Modifier.padding(horizontal = 16.dp, vertical = 16.dp)) {
                                Text(
                                    plan.title,
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                if (plan.team.isNotBlank()) {
                                    Text(
                                        plan.team,
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                                thickness = 0.5.dp,
                            )
                            val body = plan.detailHtml.orEmpty()
                                .replace(Regex("<br\\s*/?>", RegexOption.IGNORE_CASE), "\n")
                                .replace(Regex("</p>", RegexOption.IGNORE_CASE), "\n\n")
                                .replace(Regex("<[^>]+>"), "")
                                .replace("&nbsp;", " ")
                                .replace("&amp;", "&")
                                .trim()
                            Text(
                                body.ifBlank { plan.title },
                                style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.padding(16.dp),
                            )
                        }
                    }
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                    ) {
                        itemsIndexed(
                            state.plans,
                            key = { index, p -> "${p.id}#$index" },
                        ) { _, p ->
                            AppListRow(onClick = { viewModel.openPlanDetail(p) }) {
                                AppListPrimary(p.title, emphasized = true)
                                if (p.team.isNotBlank()) AppListSecondary(p.team)
                            }
                            AppListDivider()
                        }
                    }
                }
            }
            MoreDestination.MODULE_STATS -> LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                itemsIndexed(
                    state.moduleStats,
                    key = { index, s -> "module-${s.team}#$index" },
                ) { _, s ->
                    AppListRow {
                        AppListPrimary(s.team, emphasized = true)
                        AppListSecondary(
                            stringResource(R.string.module_stats_line, s.held, s.cancelled, s.changed),
                        )
                    }
                    AppListDivider()
                }
            }
            MoreDestination.TERM -> LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                items(state.terms, key = { it.id }) { t ->
                    AppListRow(
                        onClick = { viewModel.selectTerm(t.id) },
                        trailing = {
                            if (t.selected) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        },
                    ) {
                        AppListPrimary(t.name, emphasized = t.selected)
                        if (t.selected) AppListSecondary(stringResource(R.string.term_selected))
                    }
                    AppListDivider()
                }
            }
            MoreDestination.SETTINGS -> LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                item { SectionHeader(stringResource(R.string.settings_appearance)) }
                items(AppearanceMode.entries.toList(), key = { "appearance-${it.name}" }) { mode ->
                    val label = when (mode) {
                        AppearanceMode.SYSTEM -> stringResource(R.string.settings_appearance_system)
                        AppearanceMode.LIGHT -> stringResource(R.string.settings_appearance_light)
                        AppearanceMode.DARK -> stringResource(R.string.settings_appearance_dark)
                    }
                    AppListRow(
                        onClick = { viewModel.setAppearance(mode) },
                        trailing = {
                            if (appearance == mode) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        },
                    ) {
                        AppListPrimary(label, emphasized = appearance == mode)
                    }
                    AppListDivider()
                }

                item { SectionHeader(stringResource(R.string.settings_language)) }
                items(AppLanguage.entries.toList(), key = { "language-${it.name}" }) { lang ->
                    val label = when (lang) {
                        AppLanguage.SYSTEM -> stringResource(R.string.settings_language_system)
                        AppLanguage.DANISH -> stringResource(R.string.settings_language_danish)
                        AppLanguage.ENGLISH -> stringResource(R.string.settings_language_english)
                    }
                    AppListRow(
                        onClick = { viewModel.setLanguage(lang) },
                        trailing = {
                            if (language == lang) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        },
                    ) {
                        AppListPrimary(label, emphasized = language == lang)
                    }
                    AppListDivider()
                }

                item { SectionHeader(stringResource(R.string.settings_calendar)) }
                items(CalendarStyle.entries.toList(), key = { "calendar-${it.name}" }) { style ->
                    val title = if (style == CalendarStyle.PROFESSIONAL) {
                        stringResource(R.string.settings_calendar_timeline)
                    } else {
                        stringResource(R.string.settings_calendar_list)
                    }
                    val hint = if (style == CalendarStyle.PROFESSIONAL) {
                        stringResource(R.string.settings_calendar_timeline_hint)
                    } else {
                        stringResource(R.string.settings_calendar_list_hint)
                    }
                    AppListRow(
                        onClick = { viewModel.setCalendarStyle(style) },
                        trailing = {
                            if (calendarStyle == style) {
                                Icon(
                                    Icons.Default.Check,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                        },
                    ) {
                        AppListPrimary(title, emphasized = calendarStyle == style)
                        AppListSecondary(hint, maxLines = 2)
                    }
                    AppListDivider()
                }

                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_use_subject_colors)) },
                        supportingContent = {
                            Text(stringResource(R.string.settings_use_subject_colors_hint))
                        },
                        trailingContent = {
                            Switch(
                                checked = useSubjectColors,
                                onCheckedChange = viewModel::setUseSubjectColors,
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    AppListDivider()
                }

                item {
                    SectionHeader(stringResource(R.string.settings_subject_colors))
                    Text(
                        stringResource(R.string.settings_subject_colors_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }
                // lessonMappings subscription keeps rows live after sync
                @Suppress("UNUSED_EXPRESSION")
                lessonMappings
                val subjects = viewModel.availableSubjects()
                items(subjects, key = { it.code }) { subject ->
                    val accent = Color(viewModel.colorForSubject(subject.code))
                    val customized = viewModel.hasSubjectOverride(subject.code)
                    val canEdit = subject.mappingId != null ||
                        lessonMappings.containsKey(subject.code)
                    AppListRow(
                        onClick = if (canEdit) {
                            { viewModel.openSubjectEditor(subject.code) }
                        } else {
                            null
                        },
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Box(
                                Modifier
                                    .size(36.dp)
                                    .clip(RoundedCornerShape(8.dp))
                                    .background(accent.copy(alpha = 0.15f)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    Modifier
                                        .size(14.dp)
                                        .clip(CircleShape)
                                        .background(accent),
                                )
                            }
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                AppListPrimary(subject.name, emphasized = true)
                                if (customized) {
                                    AppListSecondary(stringResource(R.string.settings_subject_customized))
                                } else {
                                    AppListSecondary(subject.code.uppercase())
                                }
                            }
                            Box(
                                Modifier
                                    .size(22.dp)
                                    .clip(CircleShape)
                                    .background(accent)
                                    .border(
                                        1.dp,
                                        MaterialTheme.colorScheme.outlineVariant,
                                        CircleShape,
                                    ),
                            )
                        }
                    }
                    AppListDivider()
                }
                item {
                    val hasAnyCustom = subjects.any { viewModel.hasSubjectOverride(it.code) }
                    TextButton(
                        onClick = viewModel::resetAllSubjects,
                        enabled = hasAnyCustom,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    ) {
                        Text(stringResource(R.string.settings_subject_reset_all))
                    }
                    AppListDivider()
                }

                item { SectionHeader(stringResource(R.string.settings_notifications)) }
                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_notif_events)) },
                        trailingContent = {
                            Switch(checked = notifEvents, onCheckedChange = viewModel::setNotifEvents)
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_notif_messages)) },
                        trailingContent = {
                            Switch(checked = notifMessages, onCheckedChange = viewModel::setNotifMessages)
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_notif_assignments)) },
                        trailingContent = {
                            Switch(checked = notifAssignments, onCheckedChange = viewModel::setNotifAssignments)
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    AppListDivider()
                }

                item { SectionHeader(stringResource(R.string.settings_messages)) }
                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_disable_signature)) },
                        supportingContent = {
                            Text(stringResource(R.string.settings_disable_signature_hint))
                        },
                        trailingContent = {
                            Switch(
                                checked = disableSignature,
                                onCheckedChange = viewModel::setDisableSignature,
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    AppListDivider()
                }

                item { SectionHeader(stringResource(R.string.settings_notif_history)) }
                if (notificationHistory.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.settings_notif_history_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        )
                    }
                } else {
                    items(notificationHistory.take(10)) { entry ->
                        val text = entry.substringAfter('|', entry)
                        AppListRow { AppListSecondary(text, maxLines = 3) }
                        AppListDivider()
                    }
                    item {
                        TextButton(
                            onClick = viewModel::clearNotificationHistory,
                            modifier = Modifier.padding(horizontal = 8.dp),
                        ) {
                            Text(stringResource(R.string.settings_notif_history_clear))
                        }
                    }
                }

                item { SectionHeader(stringResource(R.string.settings_section_data)) }
                item {
                    AppListRow(
                        onClick = { showExtensionInvite = true },
                    ) {
                        AppListPrimary(stringResource(R.string.settings_browser_extension), emphasized = true)
                        AppListSecondary(SettingsStore.DOWNLOAD_URL_DISPLAY, maxLines = 1)
                    }
                    AppListDivider()
                    AppListRow(
                        onClick = {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(viewModel.privacyPolicyUrl)),
                            )
                        },
                    ) {
                        AppListPrimary(stringResource(R.string.settings_privacy), emphasized = true)
                        AppListSecondary(viewModel.privacyPolicyUrl, maxLines = 1)
                    }
                    AppListDivider()
                    AppListRow(onClick = viewModel::pullSubjectSync) {
                        AppListPrimary(stringResource(R.string.settings_sync_subjects), emphasized = true)
                        AppListSecondary(stringResource(R.string.settings_sync_subjects_hint))
                    }
                    AppListDivider()
                    AppListRow(
                        onClick = {
                            val act = context as? android.app.Activity
                            if (act != null) viewModel.checkForUpdatesWithActivity(act)
                            else viewModel.checkForUpdates()
                        },
                        leading = {
                            Icon(
                                Icons.Default.SystemUpdate,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                    ) {
                        AppListPrimary(stringResource(R.string.settings_check_updates), emphasized = true)
                        AppListSecondary(stringResource(R.string.settings_version, viewModel.appVersion()))
                    }
                    AppListDivider()
                    AppListRow(
                        onClick = viewModel::clearCache,
                        leading = {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                    ) {
                        AppListPrimary(stringResource(R.string.settings_clear_cache), emphasized = true)
                    }
                    state.message?.let {
                        Text(
                            it.asString(),
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
            MoreDestination.REFERRAL -> ReferralScreenContent(
                padding = padding,
                listState = listState,
                stats = state.referralStats,
                loading = state.referralStatsLoading,
                copied = state.referralCopied,
                shareUrl = viewModel.referralShareUrl(),
                onShare = { url ->
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(
                            Intent.EXTRA_TEXT,
                            context.getString(R.string.referral_share_text, url),
                        )
                    }
                    context.startActivity(
                        Intent.createChooser(send, context.getString(R.string.referral_share_chooser)),
                    )
                    viewModel.onReferralShared("share_sheet")
                },
                onCopy = { url ->
                    val clipboard = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE)
                        as android.content.ClipboardManager
                    clipboard.setPrimaryClip(
                        android.content.ClipData.newPlainText("BetterLectio", url),
                    )
                    viewModel.markReferralCopied()
                },
                onOpenProfilePicture = { showProfilePictureEditor = true },
            )
        }
    }

    if (showExtensionInvite) {
        ExtensionInviteSheet(
            onDismiss = {
                showExtensionInvite = false
                viewModel.dismissExtensionInvite()
            },
        )
    }

    if (showProfilePictureEditor) {
        ProfilePictureEditorSheet(
            state = state.profilePictureState,
            loading = state.profilePictureLoading,
            uploading = state.profilePictureUploading,
            errorText = state.profilePictureError?.asString(),
            onDismiss = { showProfilePictureEditor = false },
            onRefresh = viewModel::refreshProfilePictureState,
            onSubmit = viewModel::submitProfilePicture,
        )
    }

    state.editingSubjectCode?.let { code ->
        SubjectEditSheet(
            code = code,
            displayName = viewModel.displayNameForSubject(code),
            defaultName = viewModel.defaultNameFor(code),
            colorHue = viewModel.colorHueForSubject(code),
            curatedHues = viewModel.curatedHues(),
            hasOverride = viewModel.hasSubjectOverride(code),
            onDismiss = viewModel::dismissSubjectEditor,
            onSave = { name, hue -> viewModel.saveSubjectCustomization(code, name, hue) },
            onReset = { viewModel.resetSubject(code) },
        )
    }

    state.selectedPerson?.let { person ->
        PersonActionsSheet(
            entity = person,
            pinned = state.pinnedIds.contains(person.id),
            onDismiss = viewModel::dismissPersonSheet,
            onOpenSchedule = {
                if (person.kind == DirectoryEntityKind.STUDENT) {
                    viewModel.openStudentProfile(person)
                } else {
                    viewModel.openPersonSchedule(person)
                }
            },
            onWriteMessage = {
                viewModel.composeToPerson(person)
                onComposeToPerson?.invoke(
                    MessageRecipient(
                        id = person.id,
                        name = person.name,
                        kind = person.kind.name,
                    ),
                )
            },
            onViewClass = { viewModel.openPersonClass(person) },
            onTogglePin = { viewModel.togglePin(person) },
        )
    }

    directoryPhotoPreviewUrl?.let { url ->
        LectioImagePreviewDialog(
            url = url,
            contentDescription = directoryPhotoPreviewName
                ?: stringResource(R.string.student_profile_photo_preview_cd),
            onDismiss = {
                directoryPhotoPreviewUrl = null
                directoryPhotoPreviewName = null
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PersonActionsSheet(
    entity: DirectoryEntity,
    pinned: Boolean,
    onDismiss: () -> Unit,
    onOpenSchedule: () -> Unit,
    onWriteMessage: () -> Unit,
    onViewClass: () -> Unit,
    onTogglePin: () -> Unit,
) {
    val context = LocalContext.current
    val avatarRepo = remember {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            AvatarRepositoryEntryPoint::class.java,
        ).avatarRepository()
    }
    var previewUrl by remember(entity.id, entity.avatarUrl) {
        mutableStateOf(
            avatarRepo.peekUrl(
                entityId = entity.id,
                name = entity.name,
                knownUrl = entity.avatarUrl,
            ) ?: entity.avatarUrl,
        )
    }
    var showPhotoPreview by remember { mutableStateOf(false) }

    LaunchedEffect(entity.id, entity.avatarUrl, entity.kind) {
        val resolved = avatarRepo.resolveUrl(
            entityId = entity.id,
            name = entity.name,
            kind = entity.kind,
            knownUrl = entity.avatarUrl ?: previewUrl,
        )
        if (!resolved.isNullOrBlank()) previewUrl = resolved
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
        ) {
            DetailSheetPadding {
                Column(
                    Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        Modifier
                            .clip(CircleShape)
                            .clickable(enabled = !previewUrl.isNullOrBlank()) {
                                showPhotoPreview = true
                            },
                    ) {
                        PersonAvatar(entity = entity, size = 120.dp)
                    }
                    Spacer(Modifier.height(16.dp))
                    DetailSheetHeader(
                        title = entity.name,
                        subtitle = entity.subtitle,
                        meta = when (entity.kind) {
                            DirectoryEntityKind.STUDENT ->
                                stringResource(R.string.directory_person_kind_student)
                            DirectoryEntityKind.TEACHER ->
                                stringResource(R.string.directory_person_kind_teacher)
                            else -> entity.kind.name.lowercase().replaceFirstChar { it.uppercase() }
                        },
                    )
                }

                PersonSheetAction(
                    icon = Icons.Default.CalendarMonth,
                    label = stringResource(R.string.directory_open_schedule),
                    onClick = onOpenSchedule,
                )
                PersonSheetAction(
                    icon = Icons.AutoMirrored.Filled.Message,
                    label = stringResource(R.string.directory_write_message),
                    onClick = onWriteMessage,
                )
                if (entity.kind == DirectoryEntityKind.STUDENT &&
                    !entity.subtitle.isNullOrBlank()
                ) {
                    PersonSheetAction(
                        icon = Icons.Default.School,
                        label = stringResource(
                            R.string.directory_view_class_named,
                            entity.subtitle!!,
                        ),
                        onClick = onViewClass,
                    )
                }
                PersonSheetAction(
                    icon = if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    label = stringResource(
                        if (pinned) R.string.directory_unpin else R.string.directory_pin,
                    ),
                    onClick = onTogglePin,
                )
            }
        }
    }

    if (showPhotoPreview) {
        val url = previewUrl
        if (!url.isNullOrBlank()) {
            LectioImagePreviewDialog(
                url = url,
                contentDescription = entity.name,
                onDismiss = { showPhotoPreview = false },
            )
        }
    }
}

@Composable
private fun PersonSheetAction(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    AppListRow(
        onClick = onClick,
        leading = {
            Icon(
                icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
    ) {
        AppListPrimary(label, emphasized = true)
    }
    AppListDivider()
}

@Composable
private fun GradesOverviewContent(
    report: dk.betterlectio.android.feature.grades.GradesReport?,
    selectedColumnKey: String?,
    onSelectColumn: (String?) -> Unit,
    onOpenDetail: (GradeRow) -> Unit,
    listState: androidx.compose.foundation.lazy.LazyListState,
    modifier: Modifier = Modifier,
) {
    val columns = report?.columns.orEmpty()
    val grades = report?.grades.orEmpty()
    val notes = report?.notes.orEmpty()
    val alerts = report?.alerts.orEmpty()
    val visible = GradeAverage.filterRows(grades, selectedColumnKey)
    val isAll = selectedColumnKey == null
    val columnAverages = remember(grades, columns) {
        GradeAverage.columnAverages(grades, columns)
    }
    val singleAvg = selectedColumnKey?.let { GradeAverage.weightedAverageDisplay(grades, it) }
    val typeLabel = selectedColumnKey?.let { key ->
        columns.find { it.key == key }?.let { GradeAverage.shortLabel(it) }
            ?: GradeAverage.shortLabelForKey(key)
    } ?: stringResource(R.string.grades_type_all)

    LazyColumn(
        state = listState,
        modifier = modifier.fillMaxSize(),
    ) {
        item {
            FlowRow(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                FilterChip(
                    selected = isAll,
                    onClick = { onSelectColumn(null) },
                    label = { Text(stringResource(R.string.grades_type_all)) },
                )
                columns.forEach { col ->
                    FilterChip(
                        selected = selectedColumnKey == col.key,
                        onClick = { onSelectColumn(col.key) },
                        label = { Text(GradeAverage.shortLabel(col)) },
                    )
                }
            }
        }

        if (alerts.isNotEmpty()) {
            items(alerts) { alert ->
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.55f),
                ) {
                    Row(
                        Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            alert,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }
        }

        item {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 0.dp,
            ) {
                if (isAll) {
                    Column(Modifier.padding(20.dp)) {
                        Text(
                            stringResource(R.string.grades_averages_title) +
                                " · " + stringResource(R.string.grades_averages_weighted_note),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(Modifier.height(12.dp))
                        if (columnAverages.isEmpty()) {
                            Text(
                                stringResource(R.string.grades_no_average),
                                style = MaterialTheme.typography.displaySmall,
                                fontWeight = FontWeight.Bold,
                            )
                        } else {
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(20.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                columnAverages.forEach { (col, avg) ->
                                    Column {
                                        Text(
                                            avg,
                                            style = MaterialTheme.typography.headlineSmall,
                                            fontWeight = FontWeight.Bold,
                                        )
                                        Text(
                                            GradeAverage.shortLabel(col),
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Column(Modifier.padding(20.dp)) {
                        Text(
                            stringResource(R.string.grades_average_label, typeLabel),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            singleAvg ?: stringResource(R.string.grades_no_average),
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
        }

        if (visible.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.grades_empty),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    textAlign = TextAlign.Center,
                )
            }
        } else if (isAll) {
            item { GradeAllHeaderRow(columns) }
            itemsIndexed(
                visible,
                key = { index, g ->
                    listOf(g.teamId.orEmpty(), g.team, g.subject, "all", index.toString())
                        .joinToString("|")
                },
            ) { _, g ->
                GradeAllSubjectRow(
                    row = g,
                    columns = columns,
                    noteCount = GradeAverage.notesForHold(notes, g.team).size,
                    onClick = { onOpenDetail(g) },
                )
                AppListDivider()
            }
        } else {
            val colKey = selectedColumnKey!!
            itemsIndexed(
                visible,
                key = { index, g ->
                    listOf(g.teamId.orEmpty(), g.team, g.subject, colKey, index.toString())
                        .joinToString("|")
                },
            ) { _, g ->
                GradeSingleTypeRow(
                    row = g,
                    columnKey = colKey,
                    noteCount = GradeAverage.notesForHold(notes, g.team).size,
                    onClick = { onOpenDetail(g) },
                )
                AppListDivider()
            }
        }

        if (notes.isNotEmpty() && isAll) {
            item { SectionHeader(stringResource(R.string.grades_notes)) }
            items(
                notes,
                key = { "${it.hold}|${it.gradeType}|${it.insertedAt}|${it.grade}" },
            ) { note ->
                GradeNoteRow(note)
                AppListDivider()
            }
        }
    }
}

@Composable
private fun GradesDetailContent(
    detail: GradeSubjectDetail,
    listState: androidx.compose.foundation.lazy.LazyListState,
    modifier: Modifier = Modifier,
) {
    val columns = detail.columns
    LazyColumn(
        state = listState,
        modifier = modifier.fillMaxSize(),
    ) {
        item {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 16.dp)) {
                Text(
                    GradeAverage.displaySubject(detail.row.subject),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (detail.row.team.isNotBlank()) {
                    Text(
                        detail.row.team,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                thickness = 0.5.dp,
            )
        }

        val orderedKeys = if (columns.isNotEmpty()) {
            columns.map { it.key }
        } else {
            detail.row.grades.keys.toList()
        }
        items(orderedKeys) { key ->
            val cell = detail.row.cell(key) ?: return@items
            val label = columns.find { it.key == key }?.let { GradeAverage.shortLabel(it) }
                ?: GradeAverage.shortLabelForKey(key)
            AppListRow(
                trailing = {
                    Text(
                        cell.value,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = gradeSpectrumColor(cell.value),
                    )
                },
            ) {
                AppListPrimary(label, emphasized = true)
                val w = cell.weight
                if (w != null && w != 1.0) {
                    AppListMeta(
                        stringResource(
                            R.string.grades_weight_label,
                            w.toString().replace('.', ','),
                        ),
                    )
                }
            }
            AppListDivider()
        }

        item { SectionHeader(stringResource(R.string.grades_notes)) }
        if (detail.notes.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.grades_no_notes),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
            }
        } else {
            items(detail.notes) { note ->
                GradeNoteRow(note)
                AppListDivider()
            }
        }
    }
}

@Composable
private fun GradeAllHeaderRow(columns: List<GradeColumn>) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            stringResource(R.string.grades_subject_header),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        columns.forEach { col ->
            Text(
                GradeAverage.shortLabel(col),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Clip,
                modifier = Modifier.width(36.dp),
            )
        }
    }
}

@Composable
private fun GradeAllSubjectRow(
    row: GradeRow,
    columns: List<GradeColumn>,
    noteCount: Int,
    onClick: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(end = 8.dp)) {
                Text(
                    GradeAverage.displaySubject(row.subject),
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (row.team.isNotBlank()) {
                    Text(
                        row.team,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            columns.forEach { col ->
                val value = row.cell(col.key)?.value
                Text(
                    value ?: "–",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (value != null) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (value != null) {
                        gradeSpectrumColor(value)
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f)
                    },
                    textAlign = TextAlign.Center,
                    modifier = Modifier.width(36.dp),
                )
            }
        }
        if (noteCount > 0) {
            Text(
                stringResource(R.string.grades_notes_count, noteCount),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 2.dp),
            )
        }
    }
}

@Composable
private fun GradeSingleTypeRow(
    row: GradeRow,
    columnKey: String,
    noteCount: Int,
    onClick: () -> Unit,
) {
    val cell = row.cell(columnKey)
    val gradeValue = cell?.value ?: "—"
    val progress = GradeAverage.progressForGrade(cell?.value) ?: 0f
    val track = MaterialTheme.colorScheme.surfaceVariant
    val fill = MaterialTheme.colorScheme.primary

    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                GradeAverage.displaySubject(row.subject),
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.width(120.dp),
            )
            Box(
                Modifier
                    .weight(1f)
                    .height(6.dp)
                    .clip(RoundedCornerShape(3.dp))
                    .background(track),
            ) {
                Box(
                    Modifier
                        .fillMaxWidth(progress.coerceIn(0f, 1f))
                        .height(6.dp)
                        .clip(RoundedCornerShape(3.dp))
                        .background(fill),
                )
            }
            Text(
                gradeValue,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.End,
                modifier = Modifier.width(32.dp),
            )
        }
        if (row.team.isNotBlank() || noteCount > 0) {
            Row(
                Modifier.padding(top = 2.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (row.team.isNotBlank()) {
                    Text(
                        row.team,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (noteCount > 0) {
                    Text(
                        stringResource(R.string.grades_notes_count, noteCount),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun GradeNoteRow(note: GradeNoteEntry) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                note.hold,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (note.grade.isNotBlank()) {
                Text(
                    note.grade,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = gradeSpectrumColor(note.grade),
                )
            }
        }
        if (note.gradeType.isNotBlank()) {
            Text(
                note.gradeType,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (note.insertedAt.isNotBlank()) {
            Text(
                note.insertedAt,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (!note.note.isNullOrBlank()) {
            Text(
                note.note,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}

/** Discrete 7-step colors (extension-inspired). Non-scale → onSurfaceVariant. */
@Composable
private fun gradeSpectrumColor(value: String?): Color {
    val n = value?.let { GradeAverage.gradeToNumber(it) }
        ?: return MaterialTheme.colorScheme.onSurfaceVariant
    return when (n) {
        12.0 -> Color(0xFF0B7A3B)
        10.0 -> Color(0xFF0D8A6A)
        7.0 -> Color(0xFF2563EB)
        4.0 -> Color(0xFF6366F1)
        2.0 -> Color(0xFFD97706)
        0.0 -> Color(0xFFEA580C)
        -3.0 -> Color(0xFFDC2626)
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}

@Composable
private fun FlipStudiekortCard(card: StudentCard) {
    var flipped by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val rotation by animateFloatAsState(
        targetValue = if (flipped) 180f else 0f,
        animationSpec = tween(durationMillis = 380, easing = FastOutSlowInEasing),
        label = "studiekortFlip",
    )
    val showBack = rotation > 90f
    val density = LocalDensity.current.density
    val shape = RoundedCornerShape(24.dp)
    val displayName = card.student.name ?: stringResource(R.string.student_fallback)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(0.68f)
                .graphicsLayer {
                    rotationY = rotation
                    cameraDistance = 14f * density
                }
                .clip(shape)
                .clickable {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    flipped = !flipped
                },
        ) {
            if (!showBack) {
                StudiekortFront(
                    card = card,
                    displayName = displayName,
                    shape = shape,
                )
            } else {
                StudiekortBack(
                    card = card,
                    displayName = displayName,
                    shape = shape,
                )
            }
        }
        Spacer(Modifier.height(18.dp))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                if (flipped) Icons.Default.Badge else Icons.Default.QrCode2,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(18.dp),
            )
            Text(
                if (flipped) {
                    stringResource(R.string.studiekort_flip_back_hint)
                } else {
                    stringResource(R.string.studiekort_flip_hint)
                },
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun StudiekortFront(
    card: StudentCard,
    displayName: String,
    shape: RoundedCornerShape,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        modifier = Modifier.fillMaxSize(),
        shape = shape,
        color = scheme.primary,
        shadowElevation = 8.dp,
        tonalElevation = 0.dp,
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp, vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    stringResource(R.string.more_studiekort).uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.2.sp,
                    color = scheme.onPrimary.copy(alpha = 0.78f),
                )
                Icon(
                    Icons.Default.Badge,
                    contentDescription = null,
                    tint = scheme.onPrimary.copy(alpha = 0.55f),
                    modifier = Modifier.size(20.dp),
                )
            }

            Spacer(Modifier.height(12.dp))

            // Lectio school photos are portrait; use ~3:4 so faces aren't cropped square.
            val photoShape = RoundedCornerShape(20.dp)
            val photoInnerShape = RoundedCornerShape(17.dp)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .width(200.dp)
                    .height(266.dp)
                    .clip(photoShape)
                    .background(scheme.onPrimary.copy(alpha = 0.12f))
                    .border(
                        width = 2.dp,
                        color = scheme.onPrimary.copy(alpha = 0.28f),
                        shape = photoShape,
                    )
                    .padding(3.dp),
            ) {
                if (card.photoUrl != null) {
                    AsyncImage(
                        model = card.photoUrl,
                        contentDescription = displayName,
                        contentScale = ContentScale.Crop,
                        // Prefer the top of the portrait so faces aren't cropped out.
                        alignment = Alignment.TopCenter,
                        modifier = Modifier
                            .fillMaxSize()
                            .clip(photoInnerShape),
                    )
                } else {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .clip(photoInnerShape)
                            .background(scheme.onPrimary.copy(alpha = 0.14f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            displayName.take(1).uppercase(),
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.SemiBold,
                            color = scheme.onPrimary,
                        )
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            Text(
                displayName,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onPrimary,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            card.student.classLabel?.takeIf { it.isNotBlank() }?.let { label ->
                Spacer(Modifier.height(8.dp))
                Surface(
                    shape = RoundedCornerShape(999.dp),
                    color = scheme.onPrimary.copy(alpha = 0.16f),
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Medium,
                        color = scheme.onPrimary,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                card.student.schoolName?.takeIf { it.isNotBlank() }?.let { school ->
                    Text(
                        school,
                        style = MaterialTheme.typography.bodyMedium,
                        color = scheme.onPrimary.copy(alpha = 0.82f),
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                card.birthday?.let { bday ->
                    Text(
                        stringResource(R.string.studiekort_birthday, bday),
                        style = MaterialTheme.typography.bodySmall,
                        color = scheme.onPrimary.copy(alpha = 0.68f),
                        textAlign = TextAlign.Center,
                    )
                }
            }

            Spacer(Modifier.height(14.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    Icons.Default.QrCode2,
                    contentDescription = null,
                    tint = scheme.onPrimary.copy(alpha = 0.45f),
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    stringResource(R.string.more_studiekort_qr),
                    style = MaterialTheme.typography.labelMedium,
                    color = scheme.onPrimary.copy(alpha = 0.5f),
                )
            }
        }
    }
}

@Composable
private fun StudiekortBack(
    card: StudentCard,
    displayName: String,
    shape: RoundedCornerShape,
) {
    val scheme = MaterialTheme.colorScheme
    Surface(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer { rotationY = 180f },
        shape = shape,
        color = scheme.surface,
        shadowElevation = 8.dp,
        tonalElevation = 0.dp,
        border = BorderStroke(
            1.dp,
            scheme.outlineVariant.copy(alpha = 0.55f),
        ),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp, vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                stringResource(R.string.more_studiekort_qr).uppercase(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 1.2.sp,
                color = scheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                displayName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = scheme.onSurface,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Spacer(Modifier.weight(1f))

            Box(
                Modifier
                    .fillMaxWidth(0.78f)
                    .aspectRatio(1f)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color.White)
                    .border(
                        width = 1.dp,
                        color = scheme.outlineVariant.copy(alpha = 0.4f),
                        shape = RoundedCornerShape(16.dp),
                    )
                    .padding(14.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (card.qrUrl != null) {
                    AsyncImage(
                        model = card.qrUrl,
                        contentDescription = stringResource(R.string.cd_qr),
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Text(
                        stringResource(R.string.more_studiekort_qr),
                        style = MaterialTheme.typography.bodyMedium,
                        color = scheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            card.student.classLabel?.takeIf { it.isNotBlank() }?.let { label ->
                Text(
                    label,
                    style = MaterialTheme.typography.labelLarge,
                    color = scheme.onSurfaceVariant,
                )
            }
            card.student.schoolName?.takeIf { it.isNotBlank() }?.let { school ->
                Text(
                    school,
                    style = MaterialTheme.typography.bodySmall,
                    color = scheme.onSurfaceVariant.copy(alpha = 0.85f),
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun MoreRoot(
    padding: PaddingValues,
    listState: androidx.compose.foundation.lazy.LazyListState,
    studentName: String,
    classLabel: String?,
    photoUrl: String?,
    referralConversions: Int?,
    onNavigate: (MoreDestination) -> Unit,
    onOpenCatalogKind: (DirectoryEntityKind) -> Unit,
    onOpenExtensionInvite: () -> Unit,
    onEditProfilePicture: () -> Unit,
    onOpenFeedback: () -> Unit,
    onLogout: () -> Unit,
) {
    val unlock = referralUnlockProgress(referralConversions ?: 0)
    val referralSubtitle = when {
        referralConversions == null -> null
        unlock.unlocked -> stringResource(R.string.referral_subtitle_unlocked)
        else -> stringResource(
            R.string.referral_subtitle_progress,
            unlock.current,
            unlock.target,
        )
    }
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
    ) {
        item {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .clickable { onNavigate(MoreDestination.STUDIEKORT) },
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                tonalElevation = 0.dp,
            ) {
                Row(
                    Modifier.padding(horizontal = 16.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    PersonAvatar(
                        name = studentName,
                        size = 64.dp,
                        knownUrl = photoUrl,
                    )
                    Spacer(Modifier.size(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            studentName,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                        )
                        classLabel?.let {
                            Text(
                                it,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            stringResource(R.string.more_open_studiekort),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                    IconButton(onClick = onEditProfilePicture) {
                        Icon(
                            Icons.Default.Edit,
                            contentDescription = stringResource(R.string.profile_picture_edit),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
        item { SectionHeader(stringResource(R.string.more_section_school)) }
        item {
            MoreLink(
                icon = Icons.Default.Grade,
                title = stringResource(R.string.more_grades),
                onClick = { onNavigate(MoreDestination.GRADES) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Warning,
                title = stringResource(R.string.more_absence),
                onClick = { onNavigate(MoreDestination.ABSENCE) },
            )
        }
        // Study plan is temporarily hidden from the menu; implementation kept under MoreDestination.PLANS.
        item {
            MoreLink(
                icon = Icons.Default.BarChart,
                title = stringResource(R.string.more_module_stats),
                onClick = { onNavigate(MoreDestination.MODULE_STATS) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.CalendarMonth,
                title = stringResource(R.string.more_term),
                onClick = { onNavigate(MoreDestination.TERM) },
            )
        }
        item { SectionHeader(stringResource(R.string.more_catalog)) }
        item {
            CatalogGrid(onOpenCatalogKind = onOpenCatalogKind)
        }
        item { SectionHeader(stringResource(R.string.more_section_find)) }
        item {
            MoreLink(
                icon = Icons.Default.People,
                title = stringResource(R.string.more_directory),
                onClick = { onNavigate(MoreDestination.DIRECTORY) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.CalendarMonth,
                title = stringResource(R.string.more_rooms),
                onClick = { onNavigate(MoreDestination.ROOMS) },
            )
        }
        item { SectionHeader(stringResource(R.string.more_section_app)) }
        item {
            MoreLink(
                icon = Icons.Default.PersonAdd,
                title = stringResource(R.string.more_referral),
                subtitle = referralSubtitle,
                onClick = { onNavigate(MoreDestination.REFERRAL) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Extension,
                title = stringResource(R.string.more_browser_extension),
                onClick = onOpenExtensionInvite,
            )
        }
        item {
            MoreLink(
                icon = Icons.Outlined.Feedback,
                title = stringResource(R.string.more_feedback),
                onClick = onOpenFeedback,
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Settings,
                title = stringResource(R.string.more_settings),
                onClick = { onNavigate(MoreDestination.SETTINGS) },
            )
        }
        item {
            MoreLink(
                icon = Icons.AutoMirrored.Filled.ExitToApp,
                title = stringResource(R.string.action_logout),
                onClick = onLogout,
            )
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

// region Absence (Flutter-style: Oversigt | Registreringer + edit sheet)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AbsenceScreenContent(
    loading: Boolean,
    overview: AbsenceOverview?,
    causes: List<String>,
    onSaveCause: (id: String, cause: String, note: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (loading && overview == null) {
        LoadingBox(modifier)
        return
    }

    var tab by remember { mutableIntStateOf(0) }
    var editing by remember { mutableStateOf<AbsenceRegistration?>(null) }

    Column(modifier.fillMaxSize()) {
        PrimaryTabRow(selectedTabIndex = tab) {
            Tab(
                selected = tab == 0,
                onClick = { tab = 0 },
                text = { Text(stringResource(R.string.absence_tab_overview)) },
            )
            Tab(
                selected = tab == 1,
                onClick = { tab = 1 },
                text = {
                    val missingCount = overview?.missingReasons?.size ?: 0
                    if (missingCount > 0) {
                        Text(
                            "${stringResource(R.string.absence_tab_registrations)} ($missingCount)",
                        )
                    } else {
                        Text(stringResource(R.string.absence_tab_registrations))
                    }
                },
            )
        }
        when (tab) {
            0 -> AbsenceOverviewTab(overview = overview, modifier = Modifier.fillMaxSize())
            else -> AbsenceRegistrationsTab(
                overview = overview,
                onEdit = { editing = it },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }

    val sheetReg = editing
    if (sheetReg != null) {
        EditAbsenceSheet(
            reg = sheetReg,
            causes = causes,
            onDismiss = { editing = null },
            onSave = { cause, note ->
                onSaveCause(sheetReg.id, cause, note)
                editing = null
            },
        )
    }
}

@Composable
private fun AbsenceOverviewTab(
    overview: AbsenceOverview?,
    modifier: Modifier = Modifier,
) {
    val dual = overview?.let { AbsenceSummary.dual(it) }
    val warning = overview?.let { AbsencePresentation.warningFromOverview(it) }
    val bars = AbsenceChartSeries.fromTeams(overview?.teams.orEmpty())
    val teams = overview?.teams.orEmpty()
    val regs = overview?.registrations.orEmpty()

    // Flutter-style module totals from team rows
    val opgjortModules = teams.sumOf { it.regularCurrentModules.current }
    val yearModules = teams.sumOf { it.regularFinalModules.current }
    val yearTotal = teams.sumOf { it.regularFinalModules.total }.coerceAtLeast(0.0001)
    val opgjortTotal = teams.sumOf { it.regularCurrentModules.total }.coerceAtLeast(0.0001)
    val yearPct = if (teams.any { it.regularFinalModules.total > 0 }) {
        yearModules / yearTotal
    } else {
        dual?.regularFraction ?: 0.0
    }
    val opgjortPct = if (teams.any { it.regularCurrentModules.total > 0 }) {
        opgjortModules / opgjortTotal
    } else {
        dual?.regularFraction ?: 0.0
    }
    val writtenYearTotal = teams.sumOf { it.assignmentFinalTime.total }.coerceAtLeast(0.0001)
    val writtenOpgjortTotal = teams.sumOf { it.assignmentCurrentTime.total }.coerceAtLeast(0.0001)
    val writtenYearAbs = teams.sumOf { it.assignmentFinalTime.current }
    val writtenOpgjortAbs = teams.sumOf { it.assignmentCurrentTime.current }
    val writtenYearPct = if (teams.any { it.assignmentFinalTime.total > 0 }) {
        writtenYearAbs / writtenYearTotal
    } else {
        dual?.writtenFraction ?: 0.0
    }
    val writtenOpgjortPct = if (teams.any { it.assignmentCurrentTime.total > 0 }) {
        writtenOpgjortAbs / writtenOpgjortTotal
    } else {
        dual?.writtenFraction ?: 0.0
    }

    LazyColumn(modifier = modifier) {
        item {
            SectionHeader(stringResource(R.string.absence_overview))
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    AbsenceRing(
                        fraction = dual?.regularFraction ?: opgjortPct,
                        size = 80.dp,
                        useSummaryBands = true,
                        oneDecimal = true,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        stringResource(R.string.absence_regular),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    AbsenceRing(
                        fraction = dual?.writtenFraction ?: writtenOpgjortPct,
                        size = 80.dp,
                        useSummaryBands = true,
                        oneDecimal = true,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        stringResource(R.string.absence_written),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        if (warning != null) {
            item {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        Icons.Default.Warning,
                        contentDescription = null,
                        tint = Color(0xFFEF6C00),
                    )
                    Text(
                        warning,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        if (bars.isNotEmpty()) {
            item {
                SectionHeader(stringResource(R.string.absence_chart_modules))
                AbsenceBarChart(bars = bars)
            }
        }

        // Flutter Statistic cards: Normalt / Skriftligt
        item {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                AbsenceStatCard(
                    header = stringResource(R.string.absence_regular),
                    rows = listOf(
                        stringResource(R.string.absence_stat_year) to
                            "%.1f%%".format(yearPct * 100),
                        stringResource(R.string.absence_stat_current) to
                            "%.1f%%".format(opgjortPct * 100),
                        stringResource(R.string.absence_modules) to
                            stringResource(R.string.absence_modules_count, opgjortModules.roundToInt()),
                    ),
                    modifier = Modifier.weight(1f),
                )
                AbsenceStatCard(
                    header = stringResource(R.string.absence_written),
                    rows = listOf(
                        stringResource(R.string.absence_stat_year) to
                            "%.1f%%".format(writtenYearPct * 100),
                        stringResource(R.string.absence_stat_current) to
                            "%.1f%%".format(writtenOpgjortPct * 100),
                        stringResource(R.string.absence_modules) to
                            "${writtenOpgjortAbs.roundToInt()} t",
                    ),
                    modifier = Modifier.weight(1f),
                )
            }
        }

        if (teams.isNotEmpty()) {
            item { SectionHeader(stringResource(R.string.absence_per_subject)) }
            items(teams, key = { "team-${it.team}" }) { row ->
                AppListRow(
                    leading = {
                        AbsenceRing(
                            fraction = row.regularCurrentPercent,
                            size = 44.dp,
                            useSummaryBands = true,
                            oneDecimal = false,
                        )
                    },
                ) {
                    AppListPrimary(row.team, emphasized = true)
                    AppListSecondary(
                        stringResource(
                            R.string.absence_current_final,
                            "%.1f".format(row.regularCurrentPercent * 100),
                            "%.1f".format(row.regularFinalPercent * 100),
                        ),
                    )
                    if (row.assignmentCurrentPercent > 0) {
                        AppListMeta(
                            stringResource(
                                R.string.absence_assignments_pct,
                                "%.1f".format(row.assignmentCurrentPercent * 100),
                            ),
                        )
                    }
                }
                AppListDivider()
            }
        }

        if (regs.isNotEmpty()) {
            item {
                val suffix = if (regs.size == 1) {
                    ""
                } else {
                    stringResource(R.string.absence_total_count_suffix_plural)
                }
                Text(
                    stringResource(R.string.absence_total_count, regs.size, suffix),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                )
            }
        }

        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun AbsenceStatCard(
    header: String,
    rows: List<Pair<String, String>>,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.primaryContainer,
    ) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(
                header,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            rows.forEach { (title, value) ->
                HorizontalDivider(
                    Modifier.padding(vertical = 6.dp),
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.2f),
                )
                Text(
                    title,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f),
                )
                Text(
                    value,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun AbsenceRegistrationsTab(
    overview: AbsenceOverview?,
    onEdit: (AbsenceRegistration) -> Unit,
    modifier: Modifier = Modifier,
) {
    val missing = overview?.missingReasons.orEmpty()
        .let { AbsencePresentation.sortNewestFirst(it) }
    val filled = overview?.withCause.orEmpty()
        .let { AbsencePresentation.sortNewestFirst(it) }

    if (missing.isEmpty() && filled.isEmpty()) {
        Box(modifier, contentAlignment = Alignment.Center) {
            Text(
                stringResource(R.string.absence_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(24.dp),
            )
        }
        return
    }

    LazyColumn(modifier = modifier) {
        if (missing.isNotEmpty()) {
            item {
                SectionHeader(
                    "${stringResource(R.string.absence_missing_section)} (${missing.size})",
                )
            }
            items(missing, key = { "miss-${it.id}" }) { reg ->
                AbsenceRegistrationRow(reg = reg, onClick = { onEdit(reg) })
                AppListDivider()
            }
        }
        if (filled.isNotEmpty()) {
            item {
                SectionHeader(
                    "${stringResource(R.string.absence_filled_section)} (${filled.size})",
                )
            }
            items(filled, key = { "reg-${it.id}" }) { reg ->
                AbsenceRegistrationRow(reg = reg, onClick = { onEdit(reg) })
                AppListDivider()
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun AbsenceRegistrationRow(
    reg: AbsenceRegistration,
    onClick: () -> Unit,
) {
    val hold = reg.team.ifBlank { reg.activityTitle }
    val fraction = reg.percent ?: 0.0
    val missingLabel = stringResource(R.string.absence_missing_label)
    val causeLine = buildString {
        if (reg.missingCause || reg.cause.isBlank()) {
            append(missingLabel)
        } else {
            append(reg.cause)
        }
        if (reg.note.isNotBlank()) {
            append(" · ")
            append(reg.note)
        }
    }
    val dateLabel = reg.dateTimeLabel.ifBlank {
        reg.date?.toString().orEmpty()
    }

    AppListRow(
        onClick = onClick,
        leading = {
            AbsenceRing(
                fraction = fraction,
                size = 48.dp,
                useSummaryBands = false,
                approved = reg.isApproved,
                oneDecimal = false,
            )
        },
        trailing = {
            Icon(
                Icons.Default.Edit,
                contentDescription = stringResource(R.string.absence_edit_title),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        },
    ) {
        AppListPrimary(hold.ifBlank { "—" }, emphasized = true)
        if (dateLabel.isNotBlank() || reg.week.isNotBlank()) {
            val meta = listOfNotNull(
                dateLabel.takeIf { it.isNotBlank() },
                reg.week.takeIf { it.isNotBlank() }?.let {
                    stringResource(R.string.absence_week, it)
                },
            ).joinToString(" · ")
            AppListMeta(meta)
        }
        AppListSecondary(
            causeLine,
            maxLines = 2,
        )
        if (reg.lessonTitle.isNotBlank() && reg.lessonTitle != hold) {
            AppListMeta(reg.lessonTitle)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EditAbsenceSheet(
    reg: AbsenceRegistration,
    causes: List<String>,
    onDismiss: () -> Unit,
    onSave: (cause: String, note: String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var selectedCause by remember(reg.id) {
        mutableStateOf(
            causes.firstOrNull { it.equals(reg.cause, ignoreCase = true) }
                ?: reg.cause.takeIf { it.isNotBlank() },
        )
    }
    var note by remember(reg.id) { mutableStateOf(reg.note) }
    val scope = rememberCoroutineScope()
    val canSave = !selectedCause.isNullOrBlank() &&
        (
            !selectedCause.equals(reg.cause, ignoreCase = true) ||
                note != reg.note ||
                reg.missingCause
            )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.absence_edit_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )

            val hold = reg.team.ifBlank { reg.activityTitle }
            Text(
                hold,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
            )
            val detail = listOfNotNull(
                reg.lessonTitle.takeIf { it.isNotBlank() },
                reg.dateTimeLabel.takeIf { it.isNotBlank() },
                reg.teacher.takeIf { it.isNotBlank() },
                reg.room.takeIf { it.isNotBlank() },
            ).joinToString(" · ")
            if (detail.isNotBlank()) {
                Text(
                    detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Text(
                stringResource(R.string.absence_edit_cause),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                causes.forEach { cause ->
                    val selected = cause.equals(selectedCause, ignoreCase = true)
                    Surface(
                        onClick = { selectedCause = cause },
                        shape = RoundedCornerShape(12.dp),
                        color = if (selected) {
                            causeColor(cause).copy(alpha = 0.18f)
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHigh
                        },
                        border = if (selected) {
                            BorderStroke(1.5.dp, causeColor(cause))
                        } else {
                            null
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            cause,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            color = if (selected) {
                                causeColor(cause)
                            } else {
                                MaterialTheme.colorScheme.onSurface
                            },
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                        )
                    }
                }
            }

            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.absence_edit_note)) },
                placeholder = { Text(stringResource(R.string.absence_edit_note_hint)) },
                minLines = 2,
                maxLines = 4,
            )

            Button(
                onClick = {
                    val c = selectedCause ?: return@Button
                    scope.launch { sheetState.hide() }.invokeOnCompletion {
                        onSave(c, note.trim())
                    }
                },
                enabled = canSave,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
            ) {
                Text(stringResource(R.string.absence_edit_save))
            }
        }
    }
}

/** Flutter colorFromCause-ish mapping for selected cause accents. */
private fun causeColor(cause: String): Color = when {
    cause.contains("Syg", ignoreCase = true) -> Color(0xFFB71C1C)
    cause.contains("Privat", ignoreCase = true) -> Color(0xFF0D47A1)
    cause.contains("Skole", ignoreCase = true) -> Color(0xFF1B5E20)
    cause.contains("sent", ignoreCase = true) -> Color(0xFFF9A825)
    else -> Color(0xFF455A64)
}

// endregion

@Composable
private fun CatalogGrid(onOpenCatalogKind: (DirectoryEntityKind) -> Unit) {
    val tiles = listOf(
        Triple(DirectoryEntityKind.TEACHER, Icons.Default.Person, R.string.catalog_teachers),
        Triple(DirectoryEntityKind.CLASS, Icons.Default.School, R.string.catalog_classes),
        Triple(DirectoryEntityKind.HOLD, Icons.Default.Groups, R.string.catalog_holds),
        Triple(DirectoryEntityKind.ROOM, Icons.Default.MeetingRoom, R.string.catalog_rooms),
        Triple(DirectoryEntityKind.GROUP, Icons.Default.People, R.string.catalog_groups),
        Triple(DirectoryEntityKind.RESOURCE, Icons.Default.Widgets, R.string.catalog_resources),
    )
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        CatalogTile(
            icon = Icons.Default.People,
            title = stringResource(R.string.catalog_students),
            onClick = { onOpenCatalogKind(DirectoryEntityKind.STUDENT) },
            modifier = Modifier.fillMaxWidth(),
            featured = true,
        )
        for (row in tiles.chunked(2)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                row.forEach { (kind, icon, labelRes) ->
                    CatalogTile(
                        icon = icon,
                        title = stringResource(labelRes),
                        onClick = { onOpenCatalogKind(kind) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun CatalogTile(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    featured: Boolean = false,
) {
    Surface(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        if (featured) {
            Row(
                Modifier.padding(horizontal = 16.dp, vertical = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(28.dp),
                )
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        } else {
            Column(
                Modifier.padding(horizontal = 14.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun ReferralScreenContent(
    padding: PaddingValues,
    listState: androidx.compose.foundation.lazy.LazyListState,
    stats: ReferralStats?,
    loading: Boolean,
    copied: Boolean,
    shareUrl: String?,
    onShare: (String) -> Unit,
    onCopy: (String) -> Unit,
    onOpenProfilePicture: () -> Unit,
) {
    val conversions = stats?.conversions ?: 0
    val clicks = stats?.totalClicks ?: 0
    val unlock = referralUnlockProgress(conversions)
    val progress = if (loading) 0f else unlock.current.toFloat() / unlock.target.toFloat()

    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Surface(
                modifier = Modifier.clickable(enabled = unlock.unlocked, onClick = onOpenProfilePicture),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
            ) {
                Column(Modifier.padding(16.dp)) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Text(
                            if (unlock.unlocked) {
                                stringResource(R.string.referral_unlock_done_title)
                            } else {
                                stringResource(R.string.referral_unlock_title)
                            },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            if (loading) "…" else "${unlock.current}/${unlock.target}",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Spacer(Modifier.height(10.dp))
                    androidx.compose.material3.LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(8.dp)
                            .clip(RoundedCornerShape(999.dp)),
                    )
                    Spacer(Modifier.height(10.dp))
                    Text(
                        if (unlock.unlocked) {
                            stringResource(R.string.referral_unlock_done_body)
                        } else {
                            stringResource(R.string.referral_unlock_body, unlock.remaining)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item {
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.55f),
            ) {
                Row(
                    Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (unlock.unlocked) Icons.Default.Edit else Icons.Outlined.Lock,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.size(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(R.string.referral_teaser_title),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            stringResource(
                                R.string.referral_teaser_body,
                                REFERRAL_UNLOCK_THRESHOLD,
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (unlock.unlocked) {
                        Text(
                            stringResource(R.string.profile_picture_edit),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { shareUrl?.let(onShare) },
                    enabled = shareUrl != null,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Share, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text(stringResource(R.string.referral_share_cta))
                }
                androidx.compose.material3.OutlinedButton(
                    onClick = { shareUrl?.let(onCopy) },
                    enabled = shareUrl != null,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                        contentDescription = null,
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(
                        if (copied) {
                            stringResource(R.string.referral_copied)
                        } else {
                            stringResource(R.string.referral_copy_link)
                        },
                    )
                }
                if (shareUrl != null) {
                    Text(
                        shareUrl.removePrefix("https://"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Column {
                    Text(
                        if (loading) "…" else conversions.toString(),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        stringResource(R.string.referral_stat_invited),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Column {
                    Text(
                        if (loading) "…" else clicks.toString(),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        stringResource(R.string.referral_stat_clicks),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        val recents = stats?.recentReferrals.orEmpty()
        if (recents.isNotEmpty()) {
            item {
                Text(
                    stringResource(R.string.referral_recent_title),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            items(recents, key = { it.studentId }) { r ->
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    PersonAvatar(name = r.name ?: r.studentId, size = 32.dp)
                    Spacer(Modifier.size(10.dp))
                    Text(
                        r.name ?: stringResource(R.string.referral_anonymous),
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun MoreLink(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title, style = MaterialTheme.typography.bodyLarge) },
        supportingContent = subtitle?.let {
            {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        leadingContent = {
            Icon(
                icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        modifier = Modifier.clickable(onClick = onClick),
        colors = ListItemDefaults.colors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}

@Composable
private fun DirectoryEntityRow(
    entity: DirectoryEntity,
    pinned: Boolean,
    onTogglePin: () -> Unit,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
) {
    AppListRow(
        onClick = onClick,
        onLongClick = onLongClick,
        leading = {
            when (entity.kind) {
                DirectoryEntityKind.STUDENT, DirectoryEntityKind.TEACHER ->
                    PersonAvatar(entity = entity)
                else -> InitialsAvatar(entity.name)
            }
        },
        trailing = {
            IconButton(onClick = onTogglePin) {
                Icon(
                    if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    contentDescription = if (pinned) {
                        stringResource(R.string.directory_unpin)
                    } else {
                        stringResource(R.string.directory_pin)
                    },
                    tint = if (pinned) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        },
    ) {
        AppListPrimary(entity.name, emphasized = true)
        val meta = listOfNotNull(
            entity.kind.name.lowercase().replaceFirstChar { it.uppercase() },
            entity.subtitle,
        ).joinToString(" · ")
        if (meta.isNotBlank()) AppListSecondary(meta)
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun SubjectEditSheet(
    code: String,
    displayName: String,
    defaultName: String,
    colorHue: Int,
    curatedHues: List<Int>,
    hasOverride: Boolean,
    onDismiss: () -> Unit,
    onSave: (displayName: String?, colorHue: Int?) -> Unit,
    onReset: () -> Unit,
) {
    var name by remember(code) {
        mutableStateOf(if (displayName == defaultName) "" else displayName)
    }
    var selectedHue by remember(code, colorHue) { mutableStateOf(colorHue) }
    val previewName = name.trim().ifEmpty { defaultName }
    val previewColor = Color(
        dk.betterlectio.android.feature.supabase.SupabaseSubjectService.hueToArgb(selectedHue),
    )

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier
                    .size(88.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(previewColor.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(previewColor),
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                previewName,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                code.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.settings_subject_rename)) },
                placeholder = { Text(defaultName) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                stringResource(R.string.settings_subject_color),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp),
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                curatedHues.forEach { hue ->
                    val argb = dk.betterlectio.android.feature.supabase.SupabaseSubjectService.hueToArgb(hue)
                    val selected = selectedHue == hue
                    Box(
                        Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(Color(argb))
                            .then(
                                if (selected) {
                                    Modifier.border(
                                        2.dp,
                                        MaterialTheme.colorScheme.onSurface,
                                        CircleShape,
                                    )
                                } else {
                                    Modifier
                                },
                            )
                            .clickable { selectedHue = hue },
                    )
                }
            }
            Spacer(Modifier.height(20.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (hasOverride) {
                    TextButton(onClick = onReset) {
                        Text(stringResource(R.string.settings_subject_reset))
                    }
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.action_cancel))
                }
                TextButton(
                    onClick = {
                        onSave(
                            name.trim().ifEmpty { defaultName },
                            selectedHue,
                        )
                    },
                ) {
                    Text(stringResource(R.string.settings_subject_rename_save))
                }
            }
        }
    }
}
