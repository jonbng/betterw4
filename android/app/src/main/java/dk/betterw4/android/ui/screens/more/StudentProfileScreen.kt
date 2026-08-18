package dk.betterw4.android.ui.screens.more

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import dagger.hilt.android.EntryPointAccessors
import dk.betterw4.android.R
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.InstagramHandles
import dk.betterw4.android.feature.directory.StudentProfile
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleWeek
import dk.betterw4.android.feature.schedule.statusLabelText
import dk.betterw4.android.feature.schedule.timeLabelText
import dk.betterw4.android.feature.settings.CalendarStyle
import dk.betterw4.android.ui.components.AvatarRepositoryEntryPoint
import dk.betterw4.android.ui.components.DateStrip
import dk.betterw4.android.ui.components.DateStripDay
import dk.betterw4.android.ui.components.DetailSheetHeader
import dk.betterw4.android.ui.components.DetailSheetPadding
import dk.betterw4.android.ui.components.InitialsAvatar
import dk.betterw4.android.ui.components.RemoteImagePreviewDialog
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.StatusChip
import dk.betterw4.android.ui.screens.schedule.ScheduleDayPager
import dk.betterw4.android.ui.screens.schedule.StandardDayList
import dk.betterw4.android.ui.screens.schedule.TimelineDayView
import dk.betterw4.android.ui.theme.BetterW4ThemeExtras
import dk.betterw4.android.core.w4.W4Dates
import java.time.LocalDate

@Composable
fun StudentProfileScreen(
    loading: Boolean,
    entity: DirectoryEntity,
    profile: StudentProfile?,
    week: ScheduleWeek?,
    weekNumber: Int,
    weekYear: Int,
    pinned: Boolean,
    defaultCalendarStyle: CalendarStyle,
    displayTitle: (ScheduleEvent) -> String,
    accentFor: (ScheduleEvent) -> Color,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
    onViewClass: () -> Unit,
    onPrevWeek: () -> Unit,
    onNextWeek: () -> Unit,
    onGoToToday: () -> Unit,
    onLoadWeekForDate: (LocalDate) -> Unit,
) {
    if (loading && week == null) {
        LoadingBox()
        return
    }

    val hasBetterW4 = profile?.hasBetterW4 == true
    val displayName = profile?.displayName(entity.name) ?: entity.name
    val classLabel = profile?.className?.takeIf { it.isNotBlank() }
        ?: entity.subtitle?.takeIf { it.isNotBlank() }

    Column(Modifier.fillMaxSize()) {
        StudentProfileHero(
            entity = entity,
            profile = profile,
            displayName = displayName,
            classLabel = classLabel,
            hasBetterW4 = hasBetterW4,
            pinned = pinned,
            onWriteMessage = onWriteMessage,
            onTogglePin = onTogglePin,
            onViewClass = onViewClass,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
        )
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
            thickness = 0.5.dp,
        )
        PersonSchedulePane(
            loading = loading,
            week = week,
            weekNumber = weekNumber,
            weekYear = weekYear,
            defaultCalendarStyle = defaultCalendarStyle,
            displayTitle = displayTitle,
            accentFor = accentFor,
            onPrevWeek = onPrevWeek,
            onNextWeek = onNextWeek,
            onGoToToday = onGoToToday,
            onLoadWeekForDate = onLoadWeekForDate,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonSchedulePane(
    loading: Boolean,
    week: ScheduleWeek?,
    weekNumber: Int,
    weekYear: Int,
    defaultCalendarStyle: CalendarStyle,
    displayTitle: (ScheduleEvent) -> String,
    accentFor: (ScheduleEvent) -> Color,
    onPrevWeek: () -> Unit,
    onNextWeek: () -> Unit,
    onGoToToday: () -> Unit,
    onLoadWeekForDate: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
) {
    val today = W4Dates.today()
    val extended = BetterW4ThemeExtras.extendedColors
    var calendarStyle by remember(defaultCalendarStyle) { mutableStateOf(defaultCalendarStyle) }
    var selectedDate by remember { mutableStateOf(today) }
    var selectedEvent by remember { mutableStateOf<ScheduleEvent?>(null) }

    LaunchedEffect(week?.year, week?.week, week?.days) {
        val days = week?.days.orEmpty()
        if (days.isEmpty()) return@LaunchedEffect
        val inWeek = days.any { it.date == selectedDate }
        if (!inWeek) {
            selectedDate = days.firstOrNull { it.date == today }?.date
                ?: days.firstOrNull { it.events.isNotEmpty() }?.date
                ?: days.first().date
        }
    }

    val weekDays = week?.days.orEmpty()
    val isCurrentWeek = weekYear == IsoDateUtils.isoWeekYear(today) &&
        weekNumber == IsoDateUtils.isoWeek(today)

    fun selectDate(date: LocalDate) {
        selectedDate = date
        val inLoadedWeek = weekDays.any { it.date == date }
        if (!inLoadedWeek) onLoadWeekForDate(date)
    }

    Column(modifier = modifier.fillMaxSize()) {
        PersonWeekHeader(
            weekNumber = week?.week ?: weekNumber,
            loading = loading,
            showToday = !isCurrentWeek || selectedDate != today,
            onPrevWeek = onPrevWeek,
            onNextWeek = onNextWeek,
            onGoToToday = {
                selectedDate = today
                onGoToToday()
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
        )
        subtitle?.takeIf { it.isNotBlank() }?.let { sub ->
            Text(
                sub,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(
                selected = calendarStyle == CalendarStyle.PROFESSIONAL,
                onClick = { calendarStyle = CalendarStyle.PROFESSIONAL },
                label = { Text(stringResource(R.string.settings_calendar_timeline)) },
            )
            FilterChip(
                selected = calendarStyle == CalendarStyle.STANDARD,
                onClick = { calendarStyle = CalendarStyle.STANDARD },
                label = { Text(stringResource(R.string.settings_calendar_list)) },
            )
        }

        DateStrip(
            days = weekDays.map { day ->
                DateStripDay(
                    date = day.date,
                    hasEvents = day.events.isNotEmpty(),
                )
            },
            selected = selectedDate,
            onSelect = ::selectDate,
            onWeekChanged = ::selectDate,
            hasEvents = { date ->
                weekDays.find { it.date == date }?.events?.isNotEmpty() == true
            },
            modifier = Modifier.fillMaxWidth(),
        )

        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
            thickness = 0.5.dp,
        )

        Box(
            Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            when {
                loading && week == null -> LoadingBox()
                week == null -> {
                    Text(
                        stringResource(R.string.directory_person_schedule_empty),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(16.dp),
                    )
                }
                else -> {
                    ScheduleDayPager(
                        selectedDate = selectedDate,
                        onSelectDate = ::selectDate,
                        modifier = Modifier.fillMaxSize(),
                    ) { date ->
                        val events = weekDays.find { it.date == date }?.events.orEmpty()
                        when (calendarStyle) {
                            CalendarStyle.PROFESSIONAL -> {
                                TimelineDayView(
                                    date = date,
                                    events = events,
                                    displayTitle = displayTitle,
                                    accentFor = accentFor,
                                    onEventClick = { selectedEvent = it },
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                            CalendarStyle.STANDARD -> {
                                StandardDayList(
                                    events = events,
                                    displayTitle = displayTitle,
                                    accentFor = accentFor,
                                    onEventClick = { selectedEvent = it },
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    selectedEvent?.let { event ->
        val accent = accentFor(event)
        val statusColor = when (event.status) {
            EventStatus.CHANGED -> extended.statusChanged
            EventStatus.CANCELLED -> extended.statusCancelled
            EventStatus.NORMAL -> extended.statusNormal
        }
        ModalBottomSheet(onDismissRequest = { selectedEvent = null }) {
            DetailSheetPadding {
                DetailSheetHeader(
                    title = displayTitle(event),
                    subtitle = event.timeLabelText(),
                    meta = listOfNotNull(event.teacher, event.room).joinToString(" · ")
                        .ifBlank { null },
                    trailing = {
                        event.statusLabelText()?.takeIf { it.isNotBlank() }?.let { label ->
                            StatusChip(text = label, color = statusColor)
                        }
                    },
                )
                Spacer(Modifier.height(8.dp))
                event.notes?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                }
                event.homework?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        stringResource(R.string.homework_lesson_content),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                }
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(accent),
                )
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StudentProfileHero(
    entity: DirectoryEntity,
    profile: StudentProfile?,
    displayName: String,
    classLabel: String?,
    hasBetterW4: Boolean,
    pinned: Boolean,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
    onViewClass: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val avatarRepo = remember {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            AvatarRepositoryEntryPoint::class.java,
        ).avatarRepository()
    }
    val preferredUrl = profile?.pictureUrl(entity.avatarUrl)
    var resolvedUrl by remember(entity.id, preferredUrl) {
        mutableStateOf(
            preferredUrl
                ?: avatarRepo.peekUrl(
                    entityId = entity.id,
                    name = entity.name,
                    knownUrl = entity.avatarUrl,
                )
                ?: entity.avatarUrl,
        )
    }
    var showPhotoPreview by remember { mutableStateOf(false) }
    // Prefer schedule space; auto-expand once when a rich BL profile loads.
    var expanded by remember(entity.id) { mutableStateOf(false) }
    var userCollapsed by remember(entity.id) { mutableStateOf(false) }
    var collapseDrag by remember { mutableFloatStateOf(0f) }

    val hasRichProfile = hasBetterW4 && (
        !profile?.description.isNullOrBlank() ||
            profile?.formattedBirthday() != null ||
            InstagramHandles.format(profile?.instagram).isNotEmpty()
        )

    LaunchedEffect(entity.id, hasRichProfile) {
        if (hasRichProfile && !userCollapsed) expanded = true
    }

    LaunchedEffect(entity.id, preferredUrl, entity.avatarUrl) {
        if (!preferredUrl.isNullOrBlank()) {
            resolvedUrl = preferredUrl
            return@LaunchedEffect
        }
        val resolved = avatarRepo.resolveUrl(
            entityId = entity.id,
            name = entity.name,
            kind = entity.kind,
            knownUrl = entity.avatarUrl ?: resolvedUrl,
        )
        if (!resolved.isNullOrBlank()) resolvedUrl = resolved
    }

    val openPreview = {
        if (!resolvedUrl.isNullOrBlank()) showPhotoPreview = true
    }

    Surface(
        modifier = modifier
            .pointerInput(expanded) {
                if (!expanded) return@pointerInput
                detectVerticalDragGestures(
                    onDragEnd = {
                        if (collapseDrag < -48f) {
                            userCollapsed = true
                            expanded = false
                        }
                        collapseDrag = 0f
                    },
                    onDragCancel = { collapseDrag = 0f },
                    onVerticalDrag = { _, dragAmount ->
                        collapseDrag += dragAmount
                        if (collapseDrag < -72f) {
                            userCollapsed = true
                            expanded = false
                            collapseDrag = 0f
                        }
                    },
                )
            },
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
        shape = RoundedCornerShape(16.dp),
    ) {
        AnimatedContent(
            targetState = expanded,
            transitionSpec = {
                fadeIn() togetherWith fadeOut() using SizeTransform(clip = true)
            },
            label = "student-profile-hero",
        ) { isExpanded ->
            if (isExpanded) {
                ExpandedStudentProfile(
                    displayName = displayName,
                    classLabel = classLabel,
                    hasBetterW4 = hasBetterW4,
                    profile = profile,
                    resolvedUrl = resolvedUrl,
                    pinned = pinned,
                    onWriteMessage = onWriteMessage,
                    onTogglePin = onTogglePin,
                    onViewClass = onViewClass,
                    onCollapse = {
                        userCollapsed = true
                        expanded = false
                    },
                    onPhotoClick = openPreview,
                )
            } else {
                CollapsedStudentProfile(
                    displayName = displayName,
                    classLabel = classLabel,
                    hasBetterW4 = hasBetterW4,
                    resolvedUrl = resolvedUrl,
                    pinned = pinned,
                    onWriteMessage = onWriteMessage,
                    onTogglePin = onTogglePin,
                    onExpand = {
                        userCollapsed = false
                        expanded = true
                    },
                    onPhotoClick = openPreview,
                )
            }
        }
    }

    if (showPhotoPreview) {
        val url = resolvedUrl
        if (!url.isNullOrBlank()) {
            RemoteImagePreviewDialog(
                url = url,
                contentDescription = displayName,
                onDismiss = { showPhotoPreview = false },
            )
        }
    }
}

@Composable
private fun CollapsedStudentProfile(
    displayName: String,
    classLabel: String?,
    hasBetterW4: Boolean,
    resolvedUrl: String?,
    pinned: Boolean,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
    onExpand: () -> Unit,
    onPhotoClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onExpand)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        StudentPortrait(
            url = resolvedUrl,
            displayName = displayName,
            hasBetterW4 = hasBetterW4,
            width = 36.dp,
            height = 48.dp,
            corner = 10.dp,
            onClick = onPhotoClick,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                displayName,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val subtitle = buildString {
                classLabel?.let { append(it) }
                if (hasBetterW4) {
                    if (isNotEmpty()) append(" · ")
                    append(stringResource(R.string.student_profile_bl_badge))
                }
            }
            if (subtitle.isNotEmpty()) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        IconButton(
            onClick = onWriteMessage,
            modifier = Modifier.size(40.dp),
        ) {
            Icon(
                Icons.AutoMirrored.Filled.Message,
                contentDescription = stringResource(R.string.directory_write_message),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        IconButton(
            onClick = onTogglePin,
            modifier = Modifier.size(40.dp),
        ) {
            Icon(
                imageVector = if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                contentDescription = stringResource(
                    if (pinned) R.string.directory_unpin else R.string.directory_pin,
                ),
                tint = if (pinned) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
        Icon(
            Icons.Default.KeyboardArrowDown,
            contentDescription = stringResource(R.string.student_profile_expand_cd),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ExpandedStudentProfile(
    displayName: String,
    classLabel: String?,
    hasBetterW4: Boolean,
    profile: StudentProfile?,
    resolvedUrl: String?,
    pinned: Boolean,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
    onViewClass: () -> Unit,
    onCollapse: () -> Unit,
    onPhotoClick: () -> Unit,
) {
    val context = LocalContext.current
    val bio = profile?.description?.takeIf { it.isNotBlank() }.takeIf { hasBetterW4 }
    val birthday = profile?.formattedBirthday().takeIf { hasBetterW4 }
    val igHandle = InstagramHandles.format(profile?.instagram).takeIf { hasBetterW4 && it.isNotEmpty() }
    val igUrl = InstagramHandles.profileUrl(profile?.instagram).takeIf { igHandle != null }

    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            StudentPortrait(
                url = resolvedUrl,
                displayName = displayName,
                hasBetterW4 = hasBetterW4,
                width = 52.dp,
                height = 68.dp,
                corner = 12.dp,
                onClick = onPhotoClick,
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    displayName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    classLabel?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                    }
                    if (hasBetterW4) {
                        Surface(
                            color = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.14f),
                            shape = RoundedCornerShape(6.dp),
                        ) {
                            Text(
                                stringResource(R.string.student_profile_bl_badge),
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.tertiary,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                            )
                        }
                    }
                }
            }

            IconButton(
                onClick = onWriteMessage,
                modifier = Modifier.size(40.dp),
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Message,
                    contentDescription = stringResource(R.string.directory_write_message),
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
            IconButton(
                onClick = onTogglePin,
                modifier = Modifier.size(40.dp),
            ) {
                Icon(
                    imageVector = if (pinned) Icons.Filled.PushPin else Icons.Outlined.PushPin,
                    contentDescription = stringResource(
                        if (pinned) R.string.directory_unpin else R.string.directory_pin,
                    ),
                    tint = if (pinned) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
            IconButton(
                onClick = onCollapse,
                modifier = Modifier.size(40.dp),
            ) {
                Icon(
                    Icons.Default.KeyboardArrowUp,
                    contentDescription = stringResource(R.string.student_profile_collapse_cd),
                )
            }
        }

        if (bio != null) {
            Text(
                bio,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if (birthday != null || igHandle != null || !classLabel.isNullOrBlank()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                birthday?.let {
                    ProfileInfoChip(
                        icon = Icons.Default.Cake,
                        label = it,
                        contentDescription = stringResource(R.string.student_profile_birthday_cd),
                    )
                }
                if (igHandle != null && igUrl != null) {
                    ProfileInfoChip(
                        icon = Icons.Default.Link,
                        label = igHandle,
                        contentDescription = stringResource(R.string.student_profile_instagram_cd),
                        onClick = {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(igUrl)),
                            )
                        },
                    )
                }
                classLabel?.let { label ->
                    ProfileInfoChip(
                        icon = Icons.Default.School,
                        label = label,
                        contentDescription = stringResource(R.string.directory_view_class),
                        onClick = onViewClass,
                    )
                }
            }
        }
    }
}

@Composable
private fun StudentPortrait(
    url: String?,
    displayName: String,
    hasBetterW4: Boolean,
    width: Dp,
    height: Dp,
    corner: Dp,
    onClick: () -> Unit,
) {
    val context = LocalContext.current
    val shape = RoundedCornerShape(corner)
    Box(
        modifier = Modifier
            .size(width = width, height = height)
            .clip(shape)
            .border(
                width = if (hasBetterW4) 1.5.dp else 1.dp,
                color = if (hasBetterW4) {
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
                } else {
                    MaterialTheme.colorScheme.outlineVariant
                },
                shape = shape,
            )
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(enabled = !url.isNullOrBlank(), onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (!url.isNullOrBlank()) {
            SubcomposeAsyncImage(
                model = ImageRequest.Builder(context)
                    .data(url)
                    .crossfade(true)
                    .build(),
                contentDescription = stringResource(
                    R.string.student_profile_photo_cd,
                    displayName,
                ),
                contentScale = ContentScale.Crop,
                alignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxSize()
                    .clip(shape),
                loading = {
                    InitialsAvatar(
                        label = displayName,
                        modifier = Modifier.fillMaxSize(),
                    )
                },
                error = {
                    InitialsAvatar(
                        label = displayName,
                        modifier = Modifier.fillMaxSize(),
                    )
                },
            )
        } else {
            InitialsAvatar(
                label = displayName,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun PersonWeekHeader(
    weekNumber: Int,
    loading: Boolean,
    onPrevWeek: () -> Unit,
    onNextWeek: () -> Unit,
    modifier: Modifier = Modifier,
    showToday: Boolean = false,
    onGoToToday: (() -> Unit)? = null,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            stringResource(R.string.directory_person_schedule) + " · uge $weekNumber",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.weight(1f),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (showToday && onGoToToday != null) {
                TextButton(onClick = onGoToToday, enabled = !loading) {
                    Text(stringResource(R.string.schedule_go_to_today))
                }
            }
            IconButton(onClick = onPrevWeek, enabled = !loading) {
                Icon(
                    Icons.Default.ChevronLeft,
                    contentDescription = stringResource(R.string.student_profile_week_prev_cd),
                )
            }
            IconButton(onClick = onNextWeek, enabled = !loading) {
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = stringResource(R.string.student_profile_week_next_cd),
                )
            }
        }
    }
}

@Composable
private fun ProfileInfoChip(
    icon: ImageVector,
    label: String,
    contentDescription: String?,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(10.dp)
    Row(
        modifier = Modifier
            .clip(shape)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape)
            .then(
                if (onClick != null) {
                    Modifier.clickable(onClick = onClick)
                } else {
                    Modifier
                },
            )
            .padding(horizontal = 8.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}
