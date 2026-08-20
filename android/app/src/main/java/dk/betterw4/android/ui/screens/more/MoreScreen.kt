package dk.betterw4.android.ui.screens.more

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
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
import androidx.compose.material.icons.filled.Class
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.FlightTakeoff
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Grade
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import dk.betterw4.android.R
import dk.betterw4.android.core.i18n.asString
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.feature.absence.AbsenceChartSeries
import dk.betterw4.android.feature.absence.AbsenceOverview
import dk.betterw4.android.feature.absence.AbsencePresentation
import dk.betterw4.android.feature.absence.AbsenceRegistration
import dk.betterw4.android.feature.absence.AbsenceSummary
import dk.betterw4.android.feature.absence.W4AbsenceMeter
import dk.betterw4.android.feature.absence.W4AbsenceParser
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.grades.GradeAverage
import dk.betterw4.android.feature.grades.GradeColumn
import dk.betterw4.android.feature.grades.GradeNoteEntry
import dk.betterw4.android.feature.grades.GradeRow
import dk.betterw4.android.feature.grades.GradeSubjectDetail
import dk.betterw4.android.feature.messages.MessageRecipient
import dk.betterw4.android.feature.schedule.timeLabelText
import dk.betterw4.android.feature.settings.AppearanceMode
import dk.betterw4.android.feature.settings.CalendarStyle
import dk.betterw4.android.feature.studiekort.StudentCard
import dk.betterw4.android.ui.components.AbsenceBarChart
import dk.betterw4.android.ui.components.AbsenceRing
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListMeta
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.AvatarRepositoryEntryPoint
import dk.betterw4.android.ui.components.DetailSheetHeader
import dk.betterw4.android.ui.components.DetailSheetPadding
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.HtmlBody
import dk.betterw4.android.ui.components.RemoteImagePreviewDialog
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.SectionHeader
import dk.betterw4.android.ui.components.W4ChromeActions
import dk.betterw4.android.ui.components.W4WebSheet
import dk.betterw4.android.ui.components.W4WebTarget
import dk.betterw4.android.core.FeatureFlags
import dk.betterw4.android.ui.screens.messages.MessagesScreen
import dk.betterw4.android.feature.notifications.BackgroundPermission
import dk.betterw4.android.feature.documents.W4DocumentKind
import dk.betterw4.android.feature.documents.W4DocumentListing
import dk.betterw4.android.feature.documents.W4DocumentNode
import dk.betterw4.android.feature.extraacademics.ExtraAcademicsPage
import dk.betterw4.android.feature.trips.W4Trip
import dagger.hilt.android.EntryPointAccessors
import java.time.format.TextStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun MoreScreen(
    viewModel: MoreViewModel = hiltViewModel(),
    scrollToTopToken: Int = 0,
    onComposeToPerson: ((MessageRecipient) -> Unit)? = null,
    isStudentsTab: Boolean = false,
    openMailToken: Int = 0,
    onOpenMail: (() -> Unit)? = null,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val appearance by viewModel.appearance.collectAsStateWithLifecycle()
    val calendarStyle by viewModel.calendarStyle.collectAsStateWithLifecycle()
    val useSubjectColors by viewModel.useSubjectColors.collectAsStateWithLifecycle()
    val showSchoolCalendar by viewModel.showSchoolCalendar.collectAsStateWithLifecycle()
    val notifEvents by viewModel.notifEvents.collectAsStateWithLifecycle()
    val notifAssignments by viewModel.notifAssignments.collectAsStateWithLifecycle()
    val notifTrips by viewModel.notifTrips.collectAsStateWithLifecycle()
    val disableSignature by viewModel.disableSignature.collectAsStateWithLifecycle()
    val lessonMappings by viewModel.lessonMappings.collectAsStateWithLifecycle()
    val notificationHistory by viewModel.notificationHistory.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
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
    val atStudentsRoot = isStudentsTab &&
        state.destination == MoreDestination.DIRECTORY &&
        state.personEntity == null &&
        state.roomTarget == null
    val showBack = !atStudentsRoot && (
        state.destination != MoreDestination.ROOT ||
            state.gradeDetail != null ||
            state.personEntity != null ||
            state.personOpenedHouseId != null ||
            state.personOpenedClass != null ||
            state.planDetail != null ||
            state.roomTarget != null ||
            state.selectedHouseId != null
        )

    // System back / gesture: walk up More hierarchy instead of leaving the tab.
    BackHandler(enabled = showBack) {
        if (isStudentsTab) viewModel.backTo(MoreDestination.DIRECTORY) else viewModel.back()
    }

    LaunchedEffect(isStudentsTab) {
        if (isStudentsTab && state.destination == MoreDestination.ROOT) {
            viewModel.openDirectoryKind(DirectoryEntityKind.STUDENT)
        }
    }
    LaunchedEffect(openMailToken) {
        if (FeatureFlags.MAIL_ENABLED && !isStudentsTab && openMailToken > 0) {
            viewModel.navigate(MoreDestination.MAIL)
        }
    }
    LaunchedEffect(state.destination) {
        if (!FeatureFlags.MAIL_ENABLED && state.destination == MoreDestination.MAIL) {
            viewModel.popToRoot()
        }
    }

    // Reselecting the More tab (or switching back to it after a sub-page visit)
    // always returns to the top-level menu and scrolls it into view.
    // The Students tab pops back to the directory list instead.
    LaunchedEffect(scrollToTopToken) {
        if (scrollToTopToken > 0) {
            if (isStudentsTab) viewModel.popToDirectory() else viewModel.popToRoot()
            listState.animateScrollToItem(0)
        }
    }
    LaunchedEffect(state.letterUri) {
        val uri = state.letterUri ?: return@LaunchedEffect
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runCatching { context.startActivity(intent) }
        viewModel.consumeLetterUri()
    }

    fun openCompose(person: DirectoryEntity) {
        if (!FeatureFlags.MAIL_ENABLED) return
        viewModel.composeToPerson(person)
        if (isStudentsTab) {
            onComposeToPerson?.invoke(
                MessageRecipient(
                    id = person.id,
                    name = state.studentProfile?.displayName(person.name) ?: person.name,
                    kind = person.kind.name,
                ),
            )
        } else {
            viewModel.navigate(MoreDestination.MAIL)
        }
    }

    if (FeatureFlags.MAIL_ENABLED && state.destination == MoreDestination.MAIL) {
        BackHandler { viewModel.back() }
        MessagesScreen(onBackToMore = viewModel::back)
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            state.gradeDetail != null -> state.gradeDetail!!.row.subject
                            state.planDetail != null -> state.planDetail!!.title
                            state.personOpenedClass != null ->
                                state.personOpenedClass!!.subject
                            state.personOpenedHouseId != null -> {
                                val house = state.houses.firstOrNull { it.id == state.personOpenedHouseId }
                                house?.let { dk.betterw4.android.feature.directory.houseFlagLabel(it.name, it.id) }
                                    ?: stringResource(R.string.more_houses)
                            }
                            state.personEntity != null -> {
                                val displayName = state.studentProfile
                                    ?.displayName(state.personEntity!!.name)
                                    ?: state.personEntity!!.name
                                displayName
                            }
                            state.roomTarget != null -> state.roomTarget!!.name
                            state.selectedHouseId != null -> {
                                val house = state.houses.firstOrNull { it.id == state.selectedHouseId }
                                house?.let { dk.betterw4.android.feature.directory.houseFlagLabel(it.name, it.id) }
                                    ?: stringResource(R.string.more_houses)
                            }
                            state.selectedClassId != null ->
                                state.myClasses.firstOrNull {
                                    it.id.equals(state.selectedClassId, ignoreCase = true)
                                }?.subject ?: stringResource(R.string.more_my_classes)
                            state.destination == MoreDestination.ROOT && isStudentsTab ->
                                stringResource(R.string.more_students)
                            state.destination == MoreDestination.ROOT -> stringResource(R.string.tab_more)
                            state.destination == MoreDestination.GRADES -> stringResource(R.string.more_grades)
                            state.destination == MoreDestination.ABSENCE -> stringResource(R.string.more_absence)
                            state.destination == MoreDestination.DIRECTORY ->
                                stringResource(
                                    when {
                                        state.directoryKind == DirectoryEntityKind.TEACHER ->
                                            R.string.more_teachers
                                        state.directoryYear == "1" -> R.string.directory_year_first_title
                                        state.directoryYear == "2" -> R.string.directory_year_second_title
                                        else -> R.string.more_students
                                    },
                                )
                            state.destination == MoreDestination.MAIL -> stringResource(R.string.tab_messages)
                            state.destination == MoreDestination.ROOMS -> stringResource(R.string.more_rooms)
                            state.destination == MoreDestination.HOUSES -> stringResource(R.string.more_houses)
                            state.destination == MoreDestination.STUDIEKORT -> stringResource(R.string.more_id_card)
                            state.destination == MoreDestination.PLANS -> stringResource(R.string.more_plans)
                            state.destination == MoreDestination.MODULE_STATS -> stringResource(R.string.more_module_stats)
                            state.destination == MoreDestination.TERM -> stringResource(R.string.more_term)
                            state.destination == MoreDestination.SETTINGS -> stringResource(R.string.more_settings)
                            state.destination == MoreDestination.SETTINGS_PRIVACY ->
                                stringResource(R.string.settings_privacy_stores)
                            state.destination == MoreDestination.DOCUMENTS ->
                                state.documents?.title?.takeIf { it.isNotBlank() }
                                    ?: if (state.documentsExtraAcademics) {
                                        stringResource(R.string.ea_documents)
                                    } else {
                                        stringResource(R.string.more_documents)
                                    }
                            state.destination == MoreDestination.TRIPS ->
                                stringResource(R.string.more_trips_and_travel)
                            state.destination == MoreDestination.ON_DUTY ->
                                stringResource(R.string.more_on_duty)
                            state.destination == MoreDestination.MY_CLASSES ->
                                stringResource(R.string.more_my_classes)
                            state.destination == MoreDestination.HOME -> stringResource(R.string.more_home)
                            state.destination == MoreDestination.NOTIFICATIONS ->
                                stringResource(R.string.more_notifications)
                            state.destination == MoreDestination.EXTRA_ACADEMICS ->
                                stringResource(R.string.more_extra_academics)
                            state.destination == MoreDestination.EA_PAGE ->
                                state.eaPage?.displayName ?: stringResource(R.string.more_extra_academics)
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
                actions = {
                    W4ChromeActions(
                        onNotificationHref = { href ->
                            when {
                                href.isNullOrBlank() -> Unit
                                FeatureFlags.MAIL_ENABLED &&
                                    href.contains("mailer", ignoreCase = true) -> {
                                    if (isStudentsTab) onOpenMail?.invoke()
                                    else viewModel.navigate(MoreDestination.MAIL)
                                }
                            }
                        },
                    )
                },
            )
        },
    ) { padding ->
        when (state.destination) {
            MoreDestination.ROOT -> if (isStudentsTab) {
                LoadingBox(Modifier.padding(padding))
            } else {
                MoreRoot(
                    padding = padding,
                    listState = listState,
                    studentName = state.student?.name ?: state.student?.studentId.orEmpty(),
                    classLabel = state.student?.classLabel,
                    photoUrl = state.profilePhotoUrl,
                    onNavigate = viewModel::navigate,
                    onOpenTeachers = { viewModel.openDirectoryKind(DirectoryEntityKind.TEACHER) },
                    onLogout = viewModel::logout,
                )
            }
            MoreDestination.MAIL -> Unit
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
                    isDemo = state.student?.isDemo == true,
                    modifier = Modifier.padding(padding),
                )
            }
            MoreDestination.DIRECTORY -> Column(Modifier.padding(padding).fillMaxSize()) {
                when {
                    state.personEntity != null -> {
                        val person = state.personEntity!!
                        if (person.kind == DirectoryEntityKind.STUDENT ||
                            person.kind == DirectoryEntityKind.TEACHER
                        ) {
                            when {
                                state.personOpenedClass != null -> MyClassesContent(
                                    padding = PaddingValues(0.dp),
                                    listState = listState,
                                    loading = state.loading,
                                    classes = emptyList(),
                                    selectedClass = state.personOpenedClass,
                                    onOpenClass = {},
                                    onOpenPerson = { entity ->
                                        when (entity.kind) {
                                            DirectoryEntityKind.STUDENT ->
                                                viewModel.openStudentProfile(entity)
                                            DirectoryEntityKind.TEACHER ->
                                                viewModel.openStudentProfile(entity)
                                        }
                                    },
                                    onLongPressPerson = { previewDirectoryPersonPhoto(it) },
                                    onOpenRoom = viewModel::openClassRoom,
                                )
                                state.personOpenedHouseId != null -> HousesContent(
                                    padding = PaddingValues(0.dp),
                                    listState = listState,
                                    loading = state.loading,
                                    houses = state.houses,
                                    selectedHouse = state.houses.firstOrNull {
                                        it.id == state.personOpenedHouseId
                                    },
                                    onOpenHouse = viewModel::openHouse,
                                    onOpenResident = { entity ->
                                        when (entity.kind) {
                                            DirectoryEntityKind.STUDENT ->
                                                viewModel.openStudentProfile(entity)
                                            DirectoryEntityKind.TEACHER ->
                                                viewModel.openStudentProfile(entity)
                                        }
                                    },
                                    onLongPressResident = { previewDirectoryPersonPhoto(it) },
                                )
                                else -> StudentProfileScreen(
                                loading = state.loading,
                                entity = person,
                                profile = state.studentProfile,
                                week = state.personSchedule,
                                weekNumber = state.personWeek,
                                weekYear = state.personWeekYear,
                                pinned = state.pinnedIds.contains(person.id),
                                tab = state.personTab,
                                defaultCalendarStyle = calendarStyle,
                                displayTitle = viewModel::displayTitleForEvent,
                                accentFor = { Color(viewModel.accentArgbForEvent(it)) },
                                onWriteMessage = { openCompose(person) },
                                onTogglePin = { viewModel.togglePin(person) },
                                onSelectTab = viewModel::setPersonTab,
                                onOpenHouse = viewModel::openPersonHouse,
                                onOpenRoom = viewModel::openPersonRoom,
                                onOpenClass = viewModel::openPersonClass,
                                onPrevWeek = { viewModel.shiftPersonWeek(-1) },
                                onNextWeek = { viewModel.shiftPersonWeek(1) },
                                onGoToToday = viewModel::goToPersonToday,
                                onLoadWeekForDate = viewModel::loadPersonWeekForDate,
                            )
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
                                placeholder = {
                                    Text(
                                        stringResource(
                                            if (state.directoryKind == DirectoryEntityKind.TEACHER) {
                                                R.string.more_directory_search_teachers
                                            } else {
                                                R.string.more_directory_search_students
                                            },
                                        ),
                                    )
                                },
                                singleLine = true,
                                shape = RoundedCornerShape(28.dp),
                            )
                            DirectoryRoleSwitcher(
                                selected = state.directoryKind,
                                onSelect = { kind ->
                                    if (kind == state.directoryKind) return@DirectoryRoleSwitcher
                                    haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                                    viewModel.onDirectoryKind(kind)
                                    scope.launch { listState.scrollToItem(0) }
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 4.dp),
                            )
                            AnimatedVisibility(
                                visible = state.directoryKind == DirectoryEntityKind.STUDENT,
                                enter = fadeIn() + expandVertically(),
                                exit = fadeOut() + shrinkVertically(),
                            ) {
                                DirectoryYearSwitcher(
                                    selected = state.directoryYear,
                                    onSelect = { year ->
                                        if (year == state.directoryYear) return@DirectoryYearSwitcher
                                        haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                                        viewModel.onDirectoryYear(year)
                                        scope.launch { listState.scrollToItem(0) }
                                    },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp)
                                        .padding(bottom = 8.dp),
                                )
                            }
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                                thickness = 0.5.dp,
                            )
                            if (state.loading && state.directory.isEmpty()) LoadingBox()
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
                                        DirectoryEntityKind.STUDENT ->
                                            viewModel.openStudentProfile(e)
                                        DirectoryEntityKind.TEACHER ->
                                            viewModel.openPersonSheet(e)
                                    }
                                }
                                fun onEntityLongClick(e: DirectoryEntity) {
                                    previewDirectoryPersonPhoto(e)
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
            MoreDestination.HOUSES -> {
                if (state.personEntity != null) {
                    val person = state.personEntity!!
                    Column(Modifier.padding(padding).fillMaxSize()) {
                        if (person.kind == DirectoryEntityKind.STUDENT ||
                            person.kind == DirectoryEntityKind.TEACHER
                        ) {
                            when {
                                state.personOpenedClass != null -> MyClassesContent(
                                    padding = PaddingValues(0.dp),
                                    listState = listState,
                                    loading = state.loading,
                                    classes = emptyList(),
                                    selectedClass = state.personOpenedClass,
                                    onOpenClass = {},
                                    onOpenPerson = { entity ->
                                        when (entity.kind) {
                                            DirectoryEntityKind.STUDENT ->
                                                viewModel.openStudentProfile(entity)
                                            DirectoryEntityKind.TEACHER ->
                                                viewModel.openStudentProfile(entity)
                                        }
                                    },
                                    onLongPressPerson = { previewDirectoryPersonPhoto(it) },
                                    onOpenRoom = viewModel::openClassRoom,
                                )
                                state.personOpenedHouseId != null -> HousesContent(
                                    padding = PaddingValues(0.dp),
                                    listState = listState,
                                    loading = state.loading,
                                    houses = state.houses,
                                    selectedHouse = state.houses.firstOrNull {
                                        it.id == state.personOpenedHouseId
                                    },
                                    onOpenHouse = viewModel::openHouse,
                                    onOpenResident = { entity ->
                                        when (entity.kind) {
                                            DirectoryEntityKind.STUDENT ->
                                                viewModel.openStudentProfile(entity)
                                            DirectoryEntityKind.TEACHER ->
                                                viewModel.openStudentProfile(entity)
                                        }
                                    },
                                    onLongPressResident = { previewDirectoryPersonPhoto(it) },
                                )
                                else -> StudentProfileScreen(
                                loading = state.loading,
                                entity = person,
                                profile = state.studentProfile,
                                week = state.personSchedule,
                                weekNumber = state.personWeek,
                                weekYear = state.personWeekYear,
                                pinned = state.pinnedIds.contains(person.id),
                                tab = state.personTab,
                                defaultCalendarStyle = calendarStyle,
                                displayTitle = viewModel::displayTitleForEvent,
                                accentFor = { Color(viewModel.accentArgbForEvent(it)) },
                                onWriteMessage = { openCompose(person) },
                                onTogglePin = { viewModel.togglePin(person) },
                                onSelectTab = viewModel::setPersonTab,
                                onOpenHouse = viewModel::openPersonHouse,
                                onOpenRoom = viewModel::openPersonRoom,
                                onOpenClass = viewModel::openPersonClass,
                                onPrevWeek = { viewModel.shiftPersonWeek(-1) },
                                onNextWeek = { viewModel.shiftPersonWeek(1) },
                                onGoToToday = viewModel::goToPersonToday,
                                onLoadWeekForDate = viewModel::loadPersonWeekForDate,
                            )
                            }
                        }
                    }
                } else {
                    HousesContent(
                        padding = padding,
                        listState = listState,
                        loading = state.loading,
                        houses = state.houses,
                        selectedHouse = state.houses.firstOrNull { it.id == state.selectedHouseId },
                        onOpenHouse = viewModel::openHouse,
                        onOpenResident = { entity ->
                            when (entity.kind) {
                                DirectoryEntityKind.STUDENT -> viewModel.openStudentProfile(entity)
                                DirectoryEntityKind.TEACHER -> viewModel.openStudentProfile(entity)
                            }
                        },
                        onLongPressResident = { previewDirectoryPersonPhoto(it) },
                    )
                }
            }
            MoreDestination.ROOMS -> {
                if (state.roomTarget != null) {
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
                    IdCardSurface(card = card, padding = padding)
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
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_show_school_calendar)) },
                        supportingContent = {
                            Text(stringResource(R.string.settings_show_school_calendar_hint))
                        },
                        trailingContent = {
                            Switch(
                                checked = showSchoolCalendar,
                                onCheckedChange = viewModel::setShowSchoolCalendar,
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
                    val canEdit = true
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
                    val activity = context as? Activity
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_notif_events)) },
                        supportingContent = { Text(stringResource(R.string.settings_notif_events_hint)) },
                        trailingContent = {
                            Switch(checked = notifEvents, onCheckedChange = viewModel::setNotifEvents)
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_notif_assignments)) },
                        supportingContent = { Text(stringResource(R.string.settings_notif_assignments_hint)) },
                        trailingContent = {
                            Switch(checked = notifAssignments, onCheckedChange = viewModel::setNotifAssignments)
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.settings_notif_trips)) },
                        supportingContent = { Text(stringResource(R.string.settings_notif_trips_hint)) },
                        trailingContent = {
                            Switch(checked = notifTrips, onCheckedChange = viewModel::setNotifTrips)
                        },
                        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                    )
                    if (activity != null && BackgroundPermission.needsBatteryPrompt(activity)) {
                        ListItem(
                            headlineContent = { Text(stringResource(R.string.settings_notif_background)) },
                            supportingContent = {
                                Text(stringResource(R.string.settings_notif_background_hint))
                            },
                            modifier = Modifier.clickable {
                                BackgroundPermission.requestBatteryExemption(activity)
                            },
                            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
                        )
                    }
                    AppListDivider()
                }

                if (FeatureFlags.MAIL_ENABLED) {
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
                        onClick = { viewModel.navigate(MoreDestination.SETTINGS_PRIVACY) },
                    ) {
                        AppListPrimary(stringResource(R.string.settings_privacy_stores), emphasized = true)
                        AppListSecondary(stringResource(R.string.settings_privacy_stores_hint), maxLines = 2)
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
            MoreDestination.DOCUMENTS -> DocumentsContent(
                padding = padding,
                listing = state.documents,
                loading = state.loading,
                onOpen = viewModel::openDocument,
            )
            MoreDestination.TRIPS -> TripsTravelSurface(padding = padding)
            MoreDestination.ON_DUTY -> OnDutySurface(padding = padding)
            MoreDestination.MY_CLASSES -> {
                if (state.personEntity != null) {
                    val person = state.personEntity!!
                    Column(Modifier.padding(padding).fillMaxSize()) {
                        if (person.kind == DirectoryEntityKind.STUDENT ||
                            person.kind == DirectoryEntityKind.TEACHER
                        ) {
                            when {
                                state.personOpenedClass != null -> MyClassesContent(
                                    padding = PaddingValues(0.dp),
                                    listState = listState,
                                    loading = state.loading,
                                    classes = emptyList(),
                                    selectedClass = state.personOpenedClass,
                                    onOpenClass = {},
                                    onOpenPerson = { entity ->
                                        when (entity.kind) {
                                            DirectoryEntityKind.STUDENT ->
                                                viewModel.openStudentProfile(entity)
                                            DirectoryEntityKind.TEACHER ->
                                                viewModel.openStudentProfile(entity)
                                        }
                                    },
                                    onLongPressPerson = { previewDirectoryPersonPhoto(it) },
                                    onOpenRoom = viewModel::openClassRoom,
                                )
                                state.personOpenedHouseId != null -> HousesContent(
                                    padding = PaddingValues(0.dp),
                                    listState = listState,
                                    loading = state.loading,
                                    houses = state.houses,
                                    selectedHouse = state.houses.firstOrNull {
                                        it.id == state.personOpenedHouseId
                                    },
                                    onOpenHouse = viewModel::openHouse,
                                    onOpenResident = { entity ->
                                        when (entity.kind) {
                                            DirectoryEntityKind.STUDENT ->
                                                viewModel.openStudentProfile(entity)
                                            DirectoryEntityKind.TEACHER ->
                                                viewModel.openStudentProfile(entity)
                                        }
                                    },
                                    onLongPressResident = { previewDirectoryPersonPhoto(it) },
                                )
                                else -> StudentProfileScreen(
                                loading = state.loading,
                                entity = person,
                                profile = state.studentProfile,
                                week = state.personSchedule,
                                weekNumber = state.personWeek,
                                weekYear = state.personWeekYear,
                                pinned = state.pinnedIds.contains(person.id),
                                tab = state.personTab,
                                defaultCalendarStyle = calendarStyle,
                                displayTitle = viewModel::displayTitleForEvent,
                                accentFor = { Color(viewModel.accentArgbForEvent(it)) },
                                onWriteMessage = { openCompose(person) },
                                onTogglePin = { viewModel.togglePin(person) },
                                onSelectTab = viewModel::setPersonTab,
                                onOpenHouse = viewModel::openPersonHouse,
                                onOpenRoom = viewModel::openPersonRoom,
                                onOpenClass = viewModel::openPersonClass,
                                onPrevWeek = { viewModel.shiftPersonWeek(-1) },
                                onNextWeek = { viewModel.shiftPersonWeek(1) },
                                onGoToToday = viewModel::goToPersonToday,
                                onLoadWeekForDate = viewModel::loadPersonWeekForDate,
                            )
                            }
                        }
                    }
                } else if (state.roomTarget != null) {
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
                                    item(key = "cday-${day.date}") {
                                        Text(
                                            day.date.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.getDefault()) +
                                                " ${day.date.dayOfMonth}/${day.date.monthValue}",
                                            style = MaterialTheme.typography.titleSmall,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MaterialTheme.colorScheme.primary,
                                            modifier = Modifier.padding(top = 8.dp),
                                        )
                                    }
                                    items(day.events, key = { "ce-${it.id}" }) { ev ->
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
                } else {
                    MyClassesContent(
                        padding = padding,
                        listState = listState,
                        loading = state.loading,
                        classes = state.myClasses,
                        selectedClass = state.myClasses.firstOrNull {
                            it.id.equals(state.selectedClassId, ignoreCase = true)
                        },
                        onOpenClass = viewModel::openMyClass,
                        onOpenPerson = { entity ->
                            when (entity.kind) {
                                DirectoryEntityKind.STUDENT -> viewModel.openStudentProfile(entity)
                                DirectoryEntityKind.TEACHER -> viewModel.openStudentProfile(entity)
                            }
                        },
                        onLongPressPerson = { previewDirectoryPersonPhoto(it) },
                        onOpenRoom = viewModel::openClassRoom,
                    )
                }
            }
            MoreDestination.HOME -> HomeSurface(padding = padding)
            MoreDestination.NOTIFICATIONS -> NotificationsSurface(padding = padding)
            MoreDestination.EXTRA_ACADEMICS -> ExtraAcademicsMenu(
                padding = padding,
                onOpenPage = viewModel::openEaPage,
                onOpenDocuments = viewModel::openEaDocuments,
            )
            MoreDestination.EA_PAGE -> ExtraAcademicsPageSurface(
                page = state.eaPage ?: ExtraAcademicsPage.MY_ACTIVITIES,
                padding = padding,
            )
            MoreDestination.SETTINGS_PRIVACY -> PrivacyStoresSurface(padding = padding)
        }
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
            onOpenSchedule = { viewModel.openStudentProfile(person) },
            onWriteMessage = { openCompose(person) },
            onTogglePin = { viewModel.togglePin(person) },
        )
    }

    directoryPhotoPreviewUrl?.let { url ->
        RemoteImagePreviewDialog(
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
                        },
                    )
                }

                PersonSheetAction(
                    icon = Icons.Default.CalendarMonth,
                    label = stringResource(R.string.directory_open_profile),
                    onClick = onOpenSchedule,
                )
                if (FeatureFlags.MAIL_ENABLED) {
                    PersonSheetAction(
                        icon = Icons.AutoMirrored.Filled.Message,
                        label = stringResource(R.string.directory_write_message),
                        onClick = onWriteMessage,
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
            RemoteImagePreviewDialog(
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
    report: dk.betterw4.android.feature.grades.GradesReport?,
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
    val ibScale = remember(columns, grades) { GradeAverage.looksLikeIb(columns, grades) }
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
                    ibScale = ibScale,
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
                    ibScale = ibScale,
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
    val ibScale = GradeAverage.looksLikeIb(columns, listOf(detail.row))
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
                        color = gradeSpectrumColor(cell.value, ibScale),
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
    ibScale: Boolean,
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
                        gradeSpectrumColor(value, ibScale)
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
    ibScale: Boolean,
    onClick: () -> Unit,
) {
    val cell = row.cell(columnKey)
    val gradeValue = cell?.value ?: "—"
    val progress = GradeAverage.progressForGrade(cell?.value, ibScale) ?: 0f
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
                color = gradeSpectrumColor(cell?.value, ibScale),
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

/** Discrete 7-step / IB 1–7 colors. Non-scale → onSurfaceVariant. */
@Composable
private fun gradeSpectrumColor(value: String?, ibScale: Boolean = false): Color {
    val n = value?.let { GradeAverage.gradeToNumber(it) }
        ?: return MaterialTheme.colorScheme.onSurfaceVariant
    if (ibScale) {
        return when (n.toInt()) {
            7 -> Color(0xFF0B7A3B)
            6 -> Color(0xFF0D8A6A)
            5 -> Color(0xFF2563EB)
            4 -> Color(0xFF6366F1)
            3 -> Color(0xFFD97706)
            2 -> Color(0xFFEA580C)
            1 -> Color(0xFFDC2626)
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        }
    }
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
                } else if (card.qrUrl == null) {
                    stringResource(R.string.studiekort_flip_details_hint)
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
                        alignment = Alignment.Center,
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
                    if (card.qrUrl == null) Icons.Default.Badge else Icons.Default.QrCode2,
                    contentDescription = null,
                    tint = scheme.onPrimary.copy(alpha = 0.45f),
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    if (card.qrUrl == null) {
                        stringResource(R.string.more_letter_attendance)
                    } else {
                        stringResource(R.string.more_studiekort_qr)
                    },
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
                if (card.qrUrl == null) {
                    stringResource(R.string.more_studiekort).uppercase()
                } else {
                    stringResource(R.string.more_studiekort_qr).uppercase()
                },
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
                    .background(if (card.qrUrl != null) Color.White else scheme.surfaceContainerLow)
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
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        card.email?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                        }
                        card.house?.let {
                            Text(
                                dk.betterw4.android.feature.directory.houseFlagLabel(it),
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                            )
                        }
                        card.country?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
                        }
                        card.pronouns?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
                        }
                        Text(
                            stringResource(R.string.more_letter_attendance),
                            style = MaterialTheme.typography.labelLarge,
                            color = scheme.primary,
                            textAlign = TextAlign.Center,
                        )
                    }
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
    onNavigate: (MoreDestination) -> Unit,
    onOpenTeachers: () -> Unit,
    onLogout: () -> Unit,
) {
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
                    }
                }
            }
        }
        item { SectionHeader(stringResource(R.string.more_section_school)) }
        item {
            MoreLink(
                icon = Icons.Default.Home,
                title = stringResource(R.string.more_home),
                onClick = { onNavigate(MoreDestination.HOME) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Notifications,
                title = stringResource(R.string.more_notifications),
                onClick = { onNavigate(MoreDestination.NOTIFICATIONS) },
            )
        }
        if (FeatureFlags.MAIL_ENABLED) {
            item {
                MoreLink(
                    icon = Icons.Default.Mail,
                    title = stringResource(R.string.tab_messages),
                    onClick = { onNavigate(MoreDestination.MAIL) },
                )
            }
        }
        item {
            MoreLink(
                icon = Icons.Default.Apartment,
                title = stringResource(R.string.more_houses),
                onClick = { onNavigate(MoreDestination.HOUSES) },
            )
        }
        item { SectionHeader(stringResource(R.string.more_section_academics)) }
        item {
            MoreLink(
                icon = Icons.Default.Class,
                title = stringResource(R.string.more_my_classes),
                onClick = { onNavigate(MoreDestination.MY_CLASSES) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Grade,
                title = stringResource(R.string.more_grades),
                onClick = { onNavigate(MoreDestination.GRADES) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.EventBusy,
                title = stringResource(R.string.more_absence),
                onClick = { onNavigate(MoreDestination.ABSENCE) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.DirectionsBike,
                title = stringResource(R.string.more_extra_academics),
                onClick = { onNavigate(MoreDestination.EXTRA_ACADEMICS) },
            )
        }
        item { SectionHeader(stringResource(R.string.more_section_people)) }
        item {
            MoreLink(
                icon = Icons.Default.Badge,
                title = stringResource(R.string.more_teachers),
                onClick = onOpenTeachers,
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Phone,
                title = stringResource(R.string.more_on_duty),
                onClick = { onNavigate(MoreDestination.ON_DUTY) },
            )
        }
        item { SectionHeader(stringResource(R.string.more_section_boarding)) }
        item {
            MoreLink(
                icon = Icons.Default.FlightTakeoff,
                title = stringResource(R.string.more_trips_and_travel),
                onClick = { onNavigate(MoreDestination.TRIPS) },
            )
        }
        item {
            MoreLink(
                icon = Icons.Default.Folder,
                title = stringResource(R.string.more_documents),
                onClick = { onNavigate(MoreDestination.DOCUMENTS) },
            )
        }
        item { SectionHeader(stringResource(R.string.more_section_app)) }
        item {
            MoreLink(
                icon = Icons.Default.Badge,
                title = stringResource(R.string.more_id_card),
                onClick = { onNavigate(MoreDestination.STUDIEKORT) },
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
    isDemo: Boolean,
    modifier: Modifier = Modifier,
) {
    if (loading && overview == null) {
        LoadingBox(modifier)
        return
    }

    if (overview?.isW4 == true) {
        W4AbsenceScreen(
            overview = overview,
            isDemo = isDemo,
            modifier = modifier,
        )
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
                onEdit = { if (it.editable) editing = it },
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
private fun W4AbsenceScreen(
    overview: AbsenceOverview,
    isDemo: Boolean,
    modifier: Modifier = Modifier,
) {
    var ledger by remember { mutableIntStateOf(0) }
    var webTarget by remember { mutableStateOf<W4WebTarget?>(null) }
    val registerTitle = stringResource(R.string.absence_register)
    val filled = AbsencePresentation.sortNewestFirst(overview.registrations)
    val ac = filled.filter { it.lessonTitle.equals("Academics", ignoreCase = true) }
    val ea = filled.filter { it.lessonTitle.equals("EA", ignoreCase = true) }
    val shown = if (ledger == 0) ac else ea
    val acMeter = overview.academicMeter ?: W4AbsenceMeter()
    val eaMeter = overview.eaMeter ?: W4AbsenceMeter()
    Column(modifier.fillMaxSize()) {
        SectionHeader(stringResource(R.string.absence_overview))
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AbsenceStatCard(
                header = stringResource(R.string.absence_meter_academics),
                rows = listOf(
                    stringResource(R.string.absence_meter_absences) to acMeter.absences.toString(),
                    stringResource(R.string.absence_meter_lateness) to acMeter.latenesses.toString(),
                ),
                modifier = Modifier.weight(1f),
            )
            AbsenceStatCard(
                header = stringResource(R.string.absence_meter_ea),
                rows = listOf(
                    stringResource(R.string.absence_meter_absences) to eaMeter.absences.toString(),
                    stringResource(R.string.absence_meter_lateness) to eaMeter.latenesses.toString(),
                ),
                modifier = Modifier.weight(1f),
            )
        }
        PrimaryTabRow(selectedTabIndex = ledger) {
            Tab(
                selected = ledger == 0,
                onClick = { ledger = 0 },
                text = { Text(stringResource(R.string.absence_meter_academics)) },
            )
            Tab(
                selected = ledger == 1,
                onClick = { ledger = 1 },
                text = { Text(stringResource(R.string.absence_meter_ea)) },
            )
        }
        if (shown.isEmpty()) {
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Text(
                    stringResource(R.string.absence_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(24.dp),
                )
            }
        } else {
            LazyColumn(Modifier.weight(1f)) {
                items(shown, key = { it.id }) { reg ->
                    AbsenceRegistrationRow(reg = reg, onClick = null)
                    AppListDivider()
                }
            }
        }
        ListItem(
            headlineContent = { Text(stringResource(R.string.absence_register)) },
            supportingContent = {
                Text(
                    if (isDemo) {
                        stringResource(R.string.absence_register_demo)
                    } else {
                        stringResource(R.string.absence_register_hint)
                    },
                )
            },
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (isDemo) {
                        Modifier
                    } else {
                        Modifier.clickable {
                            webTarget = W4WebTarget(
                                title = registerTitle,
                                url = W4Urls.route(W4Urls.Routes.ABSENCES_REGISTER).toString(),
                            )
                        }
                    },
                ),
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
        )
    }
    W4WebSheet(target = webTarget, onDismiss = { webTarget = null })
}

@Composable
private fun AbsenceOverviewTab(
    overview: AbsenceOverview?,
    modifier: Modifier = Modifier,
) {
    if (overview?.isW4 == true) {
        W4AbsenceOverviewTab(overview = overview, modifier = modifier)
        return
    }
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
private fun W4AbsenceOverviewTab(
    overview: AbsenceOverview,
    modifier: Modifier = Modifier,
) {
    val ac = overview.academicMeter ?: W4AbsenceMeter()
    val ea = overview.eaMeter ?: W4AbsenceMeter()
    val regs = overview.registrations
    LazyColumn(modifier = modifier) {
        item {
            SectionHeader(stringResource(R.string.absence_overview))
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                AbsenceStatCard(
                    header = stringResource(R.string.absence_meter_academics),
                    rows = listOf(
                        stringResource(R.string.absence_meter_absences) to ac.absences.toString(),
                        stringResource(R.string.absence_meter_lateness) to ac.latenesses.toString(),
                    ),
                    modifier = Modifier.weight(1f),
                )
                AbsenceStatCard(
                    header = stringResource(R.string.absence_meter_ea),
                    rows = listOf(
                        stringResource(R.string.absence_meter_absences) to ea.absences.toString(),
                        stringResource(R.string.absence_meter_lateness) to ea.latenesses.toString(),
                    ),
                    modifier = Modifier.weight(1f),
                )
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
    val w4 = overview?.isW4 == true
    val missing = if (w4) {
        emptyList()
    } else {
        overview?.missingReasons.orEmpty().let { AbsencePresentation.sortNewestFirst(it) }
    }
    val filled = if (w4) {
        overview?.registrations.orEmpty().let { AbsencePresentation.sortNewestFirst(it) }
    } else {
        overview?.withCause.orEmpty().let { AbsencePresentation.sortNewestFirst(it) }
    }
    val ac = if (w4) filled.filter { it.lessonTitle.equals("Academics", ignoreCase = true) } else emptyList()
    val ea = if (w4) filled.filter { it.lessonTitle.equals("EA", ignoreCase = true) } else emptyList()
    val other = if (w4) filled.filter { it !in ac && it !in ea } else filled

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
                AbsenceRegistrationRow(
                    reg = reg,
                    onClick = if (reg.editable) ({ onEdit(reg) }) else null,
                )
                AppListDivider()
            }
        }
        if (w4) {
            if (ac.isNotEmpty()) {
                item {
                    SectionHeader(
                        "${stringResource(R.string.absence_meter_academics)} (${ac.size})",
                    )
                }
                items(ac, key = { "ac-${it.id}" }) { reg ->
                    AbsenceRegistrationRow(reg = reg, onClick = null)
                    AppListDivider()
                }
            }
            if (ea.isNotEmpty()) {
                item {
                    SectionHeader(
                        "${stringResource(R.string.absence_meter_ea)} (${ea.size})",
                    )
                }
                items(ea, key = { "ea-${it.id}" }) { reg ->
                    AbsenceRegistrationRow(reg = reg, onClick = null)
                    AppListDivider()
                }
            }
            if (other.isNotEmpty()) {
                item {
                    SectionHeader(
                        "${stringResource(R.string.absence_tab_registrations)} (${other.size})",
                    )
                }
                items(other, key = { "reg-${it.id}" }) { reg ->
                    AbsenceRegistrationRow(reg = reg, onClick = null)
                    AppListDivider()
                }
            }
        } else if (filled.isNotEmpty()) {
            item {
                SectionHeader(
                    "${stringResource(R.string.absence_filled_section)} (${filled.size})",
                )
            }
            items(filled, key = { "reg-${it.id}" }) { reg ->
                AbsenceRegistrationRow(
                    reg = reg,
                    onClick = if (reg.editable) ({ onEdit(reg) }) else null,
                )
                AppListDivider()
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun AbsenceRegistrationRow(
    reg: AbsenceRegistration,
    onClick: (() -> Unit)?,
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
        if (reg.teacher.isNotBlank()) {
            if (isNotEmpty()) append(" · ")
            append(reg.teacher)
        }
    }
    val dateLabel = reg.dateTimeLabel.ifBlank {
        reg.date?.toString().orEmpty()
    }
    val late = W4AbsenceParser.isLateness(reg.cause)

    AppListRow(
        onClick = onClick,
        leading = {
            if (reg.percent == null) {
                Surface(
                    shape = CircleShape,
                    color = if (late) {
                        Color(0xFFD97706).copy(alpha = 0.18f)
                    } else {
                        MaterialTheme.colorScheme.errorContainer
                    },
                    modifier = Modifier.size(48.dp),
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Text(
                            if (late) "L" else "A",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = if (late) Color(0xFFD97706) else MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            } else {
                AbsenceRing(
                    fraction = fraction,
                    size = 48.dp,
                    useSummaryBands = false,
                    approved = reg.isApproved,
                    oneDecimal = false,
                )
            }
        },
        trailing = if (reg.editable) {
            {
                Icon(
                    Icons.Default.Edit,
                    contentDescription = stringResource(R.string.absence_edit_title),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        } else {
            null
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
        if (reg.lessonTitle.isNotBlank() &&
            reg.lessonTitle != hold &&
            !reg.lessonTitle.equals("Academics", ignoreCase = true) &&
            !reg.lessonTitle.equals("EA", ignoreCase = true)
        ) {
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
private fun DocumentsContent(
    padding: PaddingValues,
    listing: W4DocumentListing?,
    loading: Boolean,
    onOpen: (W4DocumentNode) -> Unit,
) {
    when {
        loading && listing == null -> LoadingBox(Modifier.padding(padding))
        listing == null || (listing.items.isEmpty() && listing.bodyHtml.isNullOrBlank()) -> EmptyBox(
            text = stringResource(R.string.empty_documents),
            modifier = Modifier.padding(padding),
        )
        listing.isPage || !listing.bodyHtml.isNullOrBlank() -> Column(
            Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            HtmlBody(html = listing.bodyHtml)
        }
        else -> LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            items(listing.items, key = { "${it.kind}-${it.id}" }) { node ->
                ListItem(
                    headlineContent = { Text(node.title) },
                    leadingContent = {
                        Icon(
                            if (node.kind == W4DocumentKind.FOLDER) {
                                Icons.Default.Folder
                            } else {
                                Icons.Default.Description
                            },
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    modifier = Modifier.clickable { onOpen(node) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
    }
}

@Composable
private fun TripsContent(
    padding: PaddingValues,
    trips: List<W4Trip>,
    loading: Boolean,
) {
    when {
        loading && trips.isEmpty() -> LoadingBox(Modifier.padding(padding))
        trips.isEmpty() -> EmptyBox(
            text = stringResource(R.string.empty_trips),
            modifier = Modifier.padding(padding),
        )
        else -> LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            items(trips, key = { "${it.name}-${it.outgoing}" }) { trip ->
                ListItem(
                    headlineContent = { Text(trip.name) },
                    supportingContent = {
                        val bits = listOf(
                            trip.destination,
                            trip.outgoing,
                            trip.status,
                        ).filter { it.isNotBlank() }
                        Text(
                            bits.joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
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
private fun DirectoryRoleSwitcher(
    selected: DirectoryEntityKind,
    onSelect: (DirectoryEntityKind) -> Unit,
    modifier: Modifier = Modifier,
) {
    val roles = listOf(
        DirectoryEntityKind.STUDENT to R.string.more_students,
        DirectoryEntityKind.TEACHER to R.string.more_teachers,
    )
    SingleChoiceSegmentedButtonRow(modifier) {
        roles.forEachIndexed { index, (kind, label) ->
            SegmentedButton(
                selected = selected == kind,
                onClick = { onSelect(kind) },
                shape = SegmentedButtonDefaults.itemShape(index, roles.size),
                label = { Text(stringResource(label)) },
            )
        }
    }
}

@Composable
private fun DirectoryYearSwitcher(
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val years = listOf(
        null to R.string.directory_year_all,
        "1" to R.string.directory_year_first,
        "2" to R.string.directory_year_second,
    )
    SingleChoiceSegmentedButtonRow(modifier) {
        years.forEachIndexed { index, (year, label) ->
            SegmentedButton(
                selected = selected == year,
                onClick = { onSelect(year) },
                shape = SegmentedButtonDefaults.itemShape(index, years.size),
                label = { Text(stringResource(label)) },
            )
        }
    }
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
            PersonAvatar(entity = entity)
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
        entity.subtitle?.takeIf { it.isNotBlank() }?.let { AppListSecondary(it) }
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
        dk.betterw4.android.feature.settings.SubjectColorResolver.hueToArgb(selectedHue),
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
                    val argb = dk.betterw4.android.feature.settings.SubjectColorResolver.hueToArgb(hue)
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
