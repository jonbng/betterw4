package dk.betterw4.android.ui.screens.more

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Badge
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
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.directory.PersonBirthday
import dk.betterw4.android.feature.directory.StaffActivity
import dk.betterw4.android.feature.directory.StudentProfile
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleWeek
import dk.betterw4.android.feature.schedule.statusLabelText
import dk.betterw4.android.feature.schedule.timeLabelText
import dk.betterw4.android.feature.settings.CalendarStyle
import dk.betterw4.android.core.FeatureFlags
import dk.betterw4.android.feature.directory.houseFlagLabel
import dk.betterw4.android.feature.schedule.PersonClass
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.AvatarRepositoryEntryPoint
import dk.betterw4.android.ui.components.SectionHeader
import dk.betterw4.android.ui.components.DateStrip
import dk.betterw4.android.ui.components.DateStripDay
import dk.betterw4.android.ui.components.DetailSheetHeader
import dk.betterw4.android.ui.components.DetailSheetPadding
import dk.betterw4.android.ui.components.InitialsAvatar
import dk.betterw4.android.ui.components.RemoteImagePreviewDialog
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.ScheduleDaySkeleton
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
    tab: PersonProfileTab = PersonProfileTab.SCHEDULE,
    defaultCalendarStyle: CalendarStyle,
    displayTitle: (ScheduleEvent) -> String,
    accentFor: (ScheduleEvent) -> Color,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
    onSelectTab: (PersonProfileTab) -> Unit = {},
    onOpenHouse: () -> Unit = {},
    onOpenRoom: () -> Unit = {},
    onOpenClass: (PersonClass) -> Unit = {},
    onOpenAdvisor: (DirectoryEntity) -> Unit = {},
    onPrevWeek: () -> Unit,
    onNextWeek: () -> Unit,
    onGoToToday: () -> Unit,
    onLoadWeekForDate: (LocalDate) -> Unit,
) {
    if (loading && week == null && profile == null) {
        LoadingBox()
        return
    }

    val displayName = profile?.displayName(entity.name) ?: entity.name
    val subtitle = profile?.subtitle ?: entity.subtitle?.takeIf { it.isNotBlank() }
    var selectedTab by remember(entity.id) { mutableStateOf(tab) }
    LaunchedEffect(tab) { selectedTab = tab }

    Column(Modifier.fillMaxSize()) {
        StudentProfileHero(
            entity = entity,
            profile = profile,
            displayName = displayName,
            subtitle = subtitle,
            pinned = pinned,
            onWriteMessage = onWriteMessage,
            onTogglePin = onTogglePin,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
        )
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(
                selected = selectedTab == PersonProfileTab.SCHEDULE,
                onClick = {
                    selectedTab = PersonProfileTab.SCHEDULE
                    onSelectTab(PersonProfileTab.SCHEDULE)
                },
                label = { Text(stringResource(R.string.student_profile_tab_schedule)) },
            )
            FilterChip(
                selected = selectedTab == PersonProfileTab.ABOUT,
                onClick = {
                    selectedTab = PersonProfileTab.ABOUT
                    onSelectTab(PersonProfileTab.ABOUT)
                },
                label = { Text(stringResource(R.string.student_profile_tab_about)) },
            )
        }
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
            thickness = 0.5.dp,
        )
        when (selectedTab) {
            PersonProfileTab.SCHEDULE -> PersonSchedulePane(
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
            PersonProfileTab.ABOUT -> StudentAboutPane(
                kind = profile?.kind ?: entity.kind,
                profile = profile,
                onOpenHouse = onOpenHouse,
                onOpenRoom = onOpenRoom,
                onOpenClass = onOpenClass,
                onOpenAdvisor = onOpenAdvisor,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StudentAboutPane(
    kind: DirectoryEntityKind,
    profile: StudentProfile?,
    onOpenHouse: () -> Unit,
    onOpenRoom: () -> Unit,
    onOpenClass: (PersonClass) -> Unit,
    onOpenAdvisor: (DirectoryEntity) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (kind == DirectoryEntityKind.TEACHER) {
        StaffAboutPane(
            profile = profile,
            onOpenClass = onOpenClass,
            modifier = modifier,
        )
        return
    }

    val house = profile?.house?.takeIf { it.isNotBlank() }
    val houseId = profile?.houseId
    val room = profile?.room?.takeIf { it.isNotBlank() }
    val classes = profile?.classes.orEmpty()
    val year = profile?.year
    val country = profile?.country
    val pronouns = profile?.pronouns?.takeIf { it.isNotBlank() }
    val email = profile?.email?.takeIf { it.isNotBlank() }
    val mobile = profile?.mobile?.takeIf { it.isNotBlank() }
    val graduation = profile?.graduationYear?.takeIf { it.isNotBlank() }
    val advisor = profile?.advisor
    val birthday = profile?.parsedBirthday
    val birthdayRaw = profile?.birthday?.takeIf { it.isNotBlank() }

    LazyColumn(modifier = modifier.fillMaxSize()) {
        item { SectionHeader(stringResource(R.string.student_profile_section_house)) }
        if (house == null && room == null) {
            item {
                AppListRow {
                    AppListSecondary(stringResource(R.string.student_profile_house_unknown))
                }
                AppListDivider()
            }
        } else {
            house?.let {
                item {
                    AppListRow(
                        onClick = houseId?.let { { onOpenHouse() } },
                        leading = {
                            Icon(
                                Icons.Default.Home,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        },
                    ) {
                        AppListPrimary(
                            houseFlagLabel(it, houseId),
                            emphasized = true,
                        )
                        AppListSecondary(stringResource(R.string.student_profile_open_house))
                    }
                    AppListDivider()
                }
            }
            room?.let {
                item {
                    AppListRow(
                        onClick = houseId?.let { { onOpenRoom() } },
                        leading = {
                            Icon(
                                Icons.Default.MeetingRoom,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        },
                    ) {
                        AppListPrimary(it, emphasized = true)
                        AppListSecondary(
                            house?.let { name ->
                                stringResource(R.string.student_profile_room_in_house, name)
                            } ?: stringResource(R.string.student_profile_open_house),
                        )
                    }
                    AppListDivider()
                }
            }
        }

        if (birthday != null || birthdayRaw != null) {
            item { SectionHeader(stringResource(R.string.student_profile_section_birthday)) }
            item { BirthdayRow(birthday = birthday, raw = birthdayRaw) }
        }

        item { SectionHeader(stringResource(R.string.student_profile_section_classes)) }
        if (classes.isEmpty()) {
            item {
                AppListRow {
                    AppListSecondary(stringResource(R.string.student_profile_classes_unknown))
                }
                AppListDivider()
            }
        } else {
            items(classes, key = { it.id ?: it.name }) { item ->
                ClassRow(item, onOpenClass)
            }
        }

        item { SectionHeader(stringResource(R.string.student_profile_section_more)) }
        year?.let {
            item {
                AppListRow {
                    AppListPrimary(stringResource(R.string.student_profile_year, it))
                }
                AppListDivider()
            }
        }
        graduation?.let {
            item {
                AppListRow(
                    leading = {
                        Icon(
                            Icons.Default.CalendarMonth,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                ) {
                    AppListPrimary(it, emphasized = true)
                    AppListSecondary(stringResource(R.string.student_profile_graduation))
                }
                AppListDivider()
            }
        }
        country?.let {
            item {
                AppListRow { AppListPrimary(it) }
                AppListDivider()
            }
        }
        pronouns?.let {
            item {
                AppListRow {
                    AppListPrimary(it, emphasized = true)
                    AppListSecondary(stringResource(R.string.student_profile_pronouns))
                }
                AppListDivider()
            }
        }
        advisor?.let { person ->
            item {
                AppListRow(
                    onClick = { onOpenAdvisor(person.entity) },
                    leading = {
                        Icon(
                            Icons.Default.Person,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                ) {
                    AppListPrimary(person.name, emphasized = true)
                    AppListSecondary(stringResource(R.string.student_profile_advisor))
                }
                AppListDivider()
            }
        }
        email?.let { address ->
            item {
                AppListRow(
                    leading = {
                        Icon(
                            Icons.Default.Email,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                ) {
                    AppListPrimary(address, emphasized = true)
                    AppListSecondary(stringResource(R.string.student_profile_email))
                }
                AppListDivider()
            }
        }
        mobile?.let { number ->
            item {
                AppListRow(
                    leading = {
                        Icon(
                            Icons.Default.Phone,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                ) {
                    AppListPrimary(number, emphasized = true)
                    AppListSecondary(stringResource(R.string.student_profile_mobile))
                }
                AppListDivider()
            }
        }
        profile?.id?.takeIf { it.isNotBlank() }?.let { uwcId ->
            item {
                AppListRow(
                    leading = {
                        Icon(
                            Icons.Default.Badge,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    },
                ) {
                    AppListPrimary(uwcId, emphasized = true)
                    AppListSecondary(stringResource(R.string.student_profile_uwc_id))
                }
                AppListDivider()
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StaffAboutPane(
    profile: StudentProfile?,
    onOpenClass: (PersonClass) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val positions = profile?.positions.orEmpty()
    val email = profile?.email?.takeIf { it.isNotBlank() }
    val officeTel = profile?.officeTel?.takeIf { it.isNotBlank() }
    val mobile = profile?.mobile?.takeIf { it.isNotBlank() }
    val classes = profile?.classes.orEmpty()
    val activities = profile?.activities.orEmpty()
    val country = profile?.country?.takeIf { it.isNotBlank() }
    val birthday = profile?.birthday?.takeIf { it.isNotBlank() }

    fun openUri(uri: Uri) {
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
    }

    LazyColumn(modifier = modifier.fillMaxSize()) {
        if (positions.isNotEmpty()) {
            item { SectionHeader(stringResource(R.string.student_profile_section_roles)) }
            item {
                FlowRow(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    positions.forEach { role ->
                        Surface(
                            shape = RoundedCornerShape(50),
                            color = MaterialTheme.colorScheme.secondaryContainer,
                        ) {
                            Text(
                                role,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                            )
                        }
                    }
                }
            }
        }

        item { SectionHeader(stringResource(R.string.student_profile_section_contact)) }
        if (email == null && officeTel == null && mobile == null) {
            item {
                AppListRow {
                    AppListSecondary(stringResource(R.string.student_profile_email))
                }
                AppListDivider()
            }
        } else {
            email?.let { address ->
                item {
                    AppListRow(
                        onClick = { openUri(Uri.parse("mailto:$address")) },
                        leading = {
                            Icon(
                                Icons.Default.Email,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        },
                    ) {
                        AppListPrimary(address, emphasized = true)
                        AppListSecondary(stringResource(R.string.student_profile_email))
                    }
                    AppListDivider()
                }
            }
            officeTel?.let { tel ->
                item {
                    AppListRow(
                        leading = {
                            Icon(
                                Icons.Default.Phone,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        },
                    ) {
                        AppListPrimary(tel, emphasized = true)
                        AppListSecondary(stringResource(R.string.student_profile_office))
                    }
                    AppListDivider()
                }
            }
            mobile?.let { number ->
                val dial = phoneUri(number)
                item {
                    AppListRow(
                        onClick = dial?.let { uri -> { openUri(uri) } },
                        leading = {
                            Icon(
                                Icons.Default.Phone,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        },
                    ) {
                        AppListPrimary(number, emphasized = true)
                        AppListSecondary(stringResource(R.string.student_profile_mobile))
                    }
                    AppListDivider()
                }
            }
        }

        item { SectionHeader(stringResource(R.string.student_profile_section_taught)) }
        if (classes.isEmpty()) {
            item {
                AppListRow {
                    AppListSecondary(stringResource(R.string.student_profile_classes_none))
                }
                AppListDivider()
            }
        } else {
            items(classes, key = { it.id ?: it.name }) { item ->
                ClassRow(item, onOpenClass)
            }
        }

        item { SectionHeader(stringResource(R.string.student_profile_section_activities)) }
        if (activities.isEmpty()) {
            item {
                AppListRow {
                    AppListSecondary(stringResource(R.string.student_profile_activities_none))
                }
                AppListDivider()
            }
        } else {
            items(activities, key = { it.name + (it.dates ?: "") }) { activity ->
                ActivityRow(activity)
            }
        }

        if (birthday != null) {
            item { SectionHeader(stringResource(R.string.student_profile_section_birthday)) }
            item { BirthdayRow(birthday = PersonBirthday.parse(birthday), raw = birthday) }
        }
        if (country != null) {
            item { SectionHeader(stringResource(R.string.student_profile_section_more)) }
            item {
                AppListRow { AppListPrimary(country) }
                AppListDivider()
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun BirthdayRow(
    birthday: PersonBirthday?,
    raw: String?,
) {
    val today = birthday?.isToday() == true
    val title = birthday?.display ?: raw.orEmpty()
    val subtitle = when {
        today -> stringResource(R.string.student_profile_birthday_today)
        birthday?.isTomorrow() == true -> stringResource(R.string.student_profile_birthday_tomorrow)
        birthday != null -> stringResource(
            R.string.student_profile_birthday_in_days,
            birthday.daysUntil(),
        )
        else -> stringResource(R.string.student_profile_birthday)
    }
    val container = if (today) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        Color.Transparent
    }
    val iconColor = if (today) {
        MaterialTheme.colorScheme.onPrimaryContainer
    } else {
        MaterialTheme.colorScheme.primary
    }
    Surface(color = container) {
        AppListRow(
            leading = {
                Icon(
                    Icons.Default.Cake,
                    contentDescription = stringResource(R.string.student_profile_birthday_cd),
                    tint = iconColor,
                )
            },
        ) {
            AppListPrimary(title, emphasized = true)
            AppListSecondary(subtitle)
        }
    }
    AppListDivider()
}

@Composable
private fun ClassRow(
    item: PersonClass,
    onOpenClass: (PersonClass) -> Unit,
) {
    AppListRow(
        onClick = if (item.canOpen) {{ onOpenClass(item) }} else null,
        leading = {
            Icon(
                Icons.Default.School,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
    ) {
        AppListPrimary(item.name, emphasized = true)
        val secondary = item.subtitle
            ?: if (item.canOpen) stringResource(R.string.student_profile_open_class) else null
        secondary?.let { AppListSecondary(it) }
    }
    AppListDivider()
}

@Composable
private fun ActivityRow(activity: StaffActivity) {
    AppListRow(
        leading = {
            Icon(
                Icons.AutoMirrored.Filled.DirectionsBike,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
    ) {
        AppListPrimary(activity.name, emphasized = true)
        val meta = listOfNotNull(
            activity.category?.replaceFirstChar { it.uppercase() },
            activity.dates,
        ).joinToString(" · ")
        if (meta.isNotBlank()) AppListSecondary(meta)
    }
    AppListDivider()
}

private fun phoneUri(raw: String): Uri? {
    val digits = raw.filter { it.isDigit() || it == '+' }
    if (digits.count { it.isDigit() } < 8) return null
    return Uri.parse("tel:$digits")
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
            // Prefer today. Otherwise keep the same weekday in the newly
            // loaded week so prev/next-week does not leave the pager on a
            // date that is no longer in [week]. Never jump to "first day
            // with lessons" — that used to open the timetable on a random
            // weekday.
            selectedDate = days.firstOrNull { it.date == today }?.date
                ?: days.firstOrNull { it.date.dayOfWeek == selectedDate.dayOfWeek }?.date
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
                loading && (week == null || weekDays.none { it.date == selectedDate }) ->
                    ScheduleDaySkeleton()
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
                        if (loading && events.isEmpty() && weekDays.none { it.date == date }) {
                            ScheduleDaySkeleton()
                            return@ScheduleDayPager
                        }
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

@Composable
private fun StudentProfileHero(
    entity: DirectoryEntity,
    profile: StudentProfile?,
    displayName: String,
    subtitle: String?,
    pinned: Boolean,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
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
        modifier = modifier,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
        shape = RoundedCornerShape(16.dp),
    ) {
        CollapsedStudentProfile(
            displayName = displayName,
            subtitle = subtitle,
            resolvedUrl = resolvedUrl,
            pinned = pinned,
            onWriteMessage = onWriteMessage,
            onTogglePin = onTogglePin,
            onPhotoClick = openPreview,
        )
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
    subtitle: String?,
    resolvedUrl: String?,
    pinned: Boolean,
    onWriteMessage: () -> Unit,
    onTogglePin: () -> Unit,
    onPhotoClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        StudentPortrait(
            url = resolvedUrl,
            displayName = displayName,
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
            if (!subtitle.isNullOrBlank()) {
                Text(
                    subtitle,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (FeatureFlags.MAIL_ENABLED) {
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
    }
}


@Composable
private fun StudentPortrait(
    url: String?,
    displayName: String,
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
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant,
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
