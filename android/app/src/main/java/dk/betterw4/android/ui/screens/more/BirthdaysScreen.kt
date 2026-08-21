package dk.betterw4.android.ui.screens.more

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cake
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.outlined.Cake
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.R
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.feature.birthdays.BirthdayDay
import dk.betterw4.android.feature.birthdays.BirthdayKindFilter
import dk.betterw4.android.feature.birthdays.BirthdayMonth
import dk.betterw4.android.feature.birthdays.BirthdayMonthRef
import dk.betterw4.android.feature.birthdays.BirthdayPerson
import dk.betterw4.android.feature.birthdays.BirthdayRepository
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.ErrorBox
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.SectionHeader
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import javax.inject.Inject

data class BirthdaysUiState(
    val selected: BirthdayMonthRef = BirthdayMonthRef.of(W4Dates.today()),
    val filter: BirthdayKindFilter = BirthdayKindFilter.ALL,
    val month: BirthdayMonth? = null,
    val followingMonth: BirthdayMonth? = null,
    val loading: Boolean = true,
    val error: AppError? = null,
)

@HiltViewModel
class BirthdaysViewModel @Inject constructor(
    private val repository: BirthdayRepository,
) : ViewModel() {
    private val _state = MutableStateFlow(BirthdaysUiState())
    val state = _state.asStateFlow()

    init {
        refresh(force = false)
    }

    fun setFilter(filter: BirthdayKindFilter) {
        _state.value = _state.value.copy(filter = filter)
    }

    fun goToPreviousMonth() {
        val current = _state.value
        val next = current.month?.previous ?: current.selected.offset(-1)
        select(next)
    }

    fun goToNextMonth() {
        val current = _state.value
        val next = current.month?.next ?: current.selected.offset(1)
        select(next)
    }

    fun goToCurrentMonth() {
        select(BirthdayMonthRef.of(W4Dates.today()))
    }

    fun refresh(force: Boolean = true) {
        val ref = _state.value.selected
        viewModelScope.launch { load(ref, force) }
    }

    private fun select(ref: BirthdayMonthRef) {
        val current = _state.value
        _state.value = current.copy(
            selected = ref,
            month = if (current.month?.ref == ref) current.month else null,
            followingMonth = if (current.month?.ref == ref) current.followingMonth else null,
            loading = current.month?.ref != ref,
        )
        viewModelScope.launch { load(ref, force = false) }
    }

    private suspend fun load(ref: BirthdayMonthRef, force: Boolean) {
        _state.value = _state.value.copy(loading = _state.value.month?.ref != ref || force)
        when (val res = repository.loadMonth(ref, force)) {
            is AppResult.Success -> {
                _state.value = _state.value.copy(
                    month = res.data,
                    error = null,
                    loading = false,
                    selected = res.data.ref ?: ref,
                )
            }
            is AppResult.Failure -> {
                _state.value = _state.value.copy(
                    error = res.error,
                    loading = false,
                )
            }
        }
        val nextRef = _state.value.month?.next ?: ref.offset(1)
        when (val extra = repository.loadMonth(nextRef, force, FetchPriority.Opportunistic)) {
            is AppResult.Success -> _state.value = _state.value.copy(followingMonth = extra.data)
            is AppResult.Failure -> Unit
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BirthdaysSurface(
    padding: PaddingValues,
    onOpenPerson: (DirectoryEntity) -> Unit,
    viewModel: BirthdaysViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val today = remember { W4Dates.today() }

    PullToRefreshBox(
        isRefreshing = state.loading && state.month != null,
        onRefresh = { viewModel.refresh(true) },
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
    ) {
        when {
            state.loading && state.month == null -> LoadingBox()
            state.error != null && state.month == null -> ErrorBox(
                state.error,
                onRetry = { viewModel.refresh(true) },
            )
            else -> BirthdaysList(
                state = state,
                today = today,
                listState = listState,
                onFilter = viewModel::setFilter,
                onPrevious = viewModel::goToPreviousMonth,
                onNext = viewModel::goToNextMonth,
                onThisMonth = viewModel::goToCurrentMonth,
                onOpenPerson = onOpenPerson,
            )
        }
    }
}

@Composable
private fun BirthdaysList(
    state: BirthdaysUiState,
    today: LocalDate,
    listState: LazyListState,
    onFilter: (BirthdayKindFilter) -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onThisMonth: () -> Unit,
    onOpenPerson: (DirectoryEntity) -> Unit,
) {
    val month = (state.month ?: BirthdayMonth()).filtered(state.filter)
    val following = (state.followingMonth ?: BirthdayMonth()).filtered(state.filter)
    val isCurrent = state.selected.year == today.year && state.selected.month == today.monthValue
    val todayPeople = if (isCurrent) month.day(today)?.people.orEmpty() else emptyList()
    val tomorrow = today.plusDays(1)
    val tomorrowPeople = if (isCurrent) {
        month.day(tomorrow)?.people ?: following.day(tomorrow)?.people.orEmpty()
    } else {
        emptyList()
    }
    val upcomingFrom = if (tomorrowPeople.isEmpty()) tomorrow else tomorrow.plusDays(1)
    val upcoming = if (isCurrent) {
        (month.daysWithPeople(from = upcomingFrom) + following.daysWithPeople()).take(12)
    } else {
        month.daysWithPeople()
    }
    val earlier = if (isCurrent) month.daysWithPeople(through = today.minusDays(1)) else emptyList()
    val emptyText = when (state.filter) {
        BirthdayKindFilter.ALL -> stringResource(R.string.birthdays_empty)
        BirthdayKindFilter.STUDENTS -> stringResource(R.string.birthdays_empty_students)
        BirthdayKindFilter.STAFF -> stringResource(R.string.birthdays_empty_staff)
    }

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item(key = "filters") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = state.filter == BirthdayKindFilter.ALL,
                    onClick = { onFilter(BirthdayKindFilter.ALL) },
                    label = { Text(stringResource(R.string.birthdays_filter_all)) },
                )
                FilterChip(
                    selected = state.filter == BirthdayKindFilter.STUDENTS,
                    onClick = { onFilter(BirthdayKindFilter.STUDENTS) },
                    label = { Text(stringResource(R.string.birthdays_filter_students)) },
                )
                FilterChip(
                    selected = state.filter == BirthdayKindFilter.STAFF,
                    onClick = { onFilter(BirthdayKindFilter.STAFF) },
                    label = { Text(stringResource(R.string.birthdays_filter_staff)) },
                )
            }
        }
        item(key = "month-nav") {
            MonthHeader(
                label = month.monthLabel ?: state.selected.label,
                showThisMonth = !isCurrent,
                onPrevious = onPrevious,
                onNext = onNext,
                onThisMonth = onThisMonth,
            )
        }
        item(key = "grid") {
            BirthdayMonthGrid(
                month = month,
                selected = state.selected,
                today = today,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
        if (isCurrent) {
            item(key = "today-header") {
                SectionHeader(stringResource(R.string.birthdays_today))
            }
            if (todayPeople.isEmpty()) {
                item(key = "today-empty") {
                    Text(
                        stringResource(R.string.birthdays_today_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            } else {
                items(todayPeople, key = { "today-${it.uwcId}" }) { person ->
                    BirthdayPersonCard(
                        person = person,
                        prominent = true,
                        onClick = { onOpenPerson(person.toEntity()) },
                    )
                }
            }
            if (tomorrowPeople.isNotEmpty()) {
                item(key = "tomorrow-header") {
                    SectionHeader(stringResource(R.string.birthdays_tomorrow))
                }
                items(tomorrowPeople, key = { "tomorrow-${it.uwcId}" }) { person ->
                    BirthdayPersonCard(
                        person = person,
                        prominent = false,
                        onClick = { onOpenPerson(person.toEntity()) },
                    )
                }
            }
        }
        upcoming
            .filter { day ->
                val date = day.date ?: return@filter true
                if (!isCurrent) return@filter true
                date != today && (date != tomorrow || tomorrowPeople.isEmpty())
            }
            .forEach { day ->
                item(key = "header-${day.id}") {
                    SectionHeader(captionFor(day, today))
                }
                items(day.people, key = { "${day.id}-${it.uwcId}" }) { person ->
                    BirthdayPersonCard(
                        person = person,
                        prominent = false,
                        onClick = { onOpenPerson(person.toEntity()) },
                    )
                }
            }
        earlier.forEach { day ->
            item(key = "earlier-${day.id}") {
                SectionHeader(captionFor(day, today))
            }
            items(day.people, key = { "earlier-${day.id}-${it.uwcId}" }) { person ->
                BirthdayPersonCard(
                    person = person,
                    prominent = false,
                    onClick = { onOpenPerson(person.toEntity()) },
                )
            }
        }
        if (upcoming.isEmpty() && todayPeople.isEmpty() && tomorrowPeople.isEmpty() && earlier.isEmpty() && !state.loading) {
            item(key = "empty") {
                EmptyBox(
                    text = emptyText,
                    description = stringResource(R.string.birthdays_empty_hint),
                    icon = Icons.Outlined.Cake,
                    modifier = Modifier.padding(top = 24.dp),
                )
            }
        }
    }
}

@Composable
private fun MonthHeader(
    label: String,
    showThisMonth: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onThisMonth: () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onPrevious) {
                Icon(Icons.Default.ChevronLeft, contentDescription = stringResource(R.string.birthdays_previous_month))
            }
            Text(
                label,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onNext) {
                Icon(Icons.Default.ChevronRight, contentDescription = stringResource(R.string.birthdays_next_month))
            }
        }
        if (showThisMonth) {
            TextButton(
                onClick = onThisMonth,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            ) {
                Text(stringResource(R.string.birthdays_this_month))
            }
        }
    }
}

@Composable
private fun BirthdayMonthGrid(
    month: BirthdayMonth,
    selected: BirthdayMonthRef,
    today: LocalDate,
    modifier: Modifier = Modifier,
) {
    val yearMonth = YearMonth.of(month.year ?: selected.year, month.month ?: selected.month)
    val first = yearMonth.atDay(1)
    val leading = ((first.dayOfWeek.value + 6) % 7)
    val byNumber = month.days.associateBy { it.dayNumber }
    val cells = buildList {
        repeat(leading) { add(null) }
        for (day in 1..yearMonth.lengthOfMonth()) {
            add(
                byNumber[day] ?: BirthdayDay(
                    date = yearMonth.atDay(day),
                    dayNumber = day,
                    dateLabel = yearMonth.atDay(day).format(DISPLAY_DAY),
                ),
            )
        }
    }
    val weeks = cells.chunked(7)
    val weekdays = remember {
        DayOfWeek.entries.map { it.getDisplayName(TextStyle.NARROW, Locale.UK) }
    }

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(12.dp)) {
            Row(Modifier.fillMaxWidth()) {
                weekdays.forEach { letter ->
                    Text(
                        letter,
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            weeks.forEach { week ->
                Row(Modifier.fillMaxWidth()) {
                    week.forEach { day ->
                        Box(Modifier.weight(1f)) {
                            if (day != null) {
                                BirthdayGridDay(
                                    day = day,
                                    isToday = day.date == today,
                                )
                            } else {
                                Spacer(Modifier.height(44.dp))
                            }
                        }
                    }
                    repeat(7 - week.size) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun BirthdayGridDay(
    day: BirthdayDay,
    isToday: Boolean,
) {
    val hasPeople = day.people.isNotEmpty()
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .padding(vertical = 4.dp)
            .semantics {
                contentDescription = buildString {
                    if (isToday) append("Today, ")
                    append(day.dateLabel)
                    if (hasPeople) {
                        append(", ")
                        append(
                            if (day.people.size == 1) day.people[0].displayName
                            else "${day.people.size} birthdays",
                        )
                    }
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(if (isToday) MaterialTheme.colorScheme.primary else Color.Transparent),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                day.dayNumber.toString(),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal,
                color = when {
                    isToday -> MaterialTheme.colorScheme.onPrimary
                    hasPeople -> MaterialTheme.colorScheme.onSurface
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
        Spacer(Modifier.height(4.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            day.people.take(3).forEach { person ->
                Box(
                    Modifier
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(
                            if (person.isStaff) MaterialTheme.colorScheme.tertiary
                            else MaterialTheme.colorScheme.primary,
                        ),
                )
            }
            if (day.people.isEmpty()) {
                Spacer(Modifier.size(4.dp))
            }
        }
    }
}

@Composable
private fun BirthdayPersonCard(
    person: BirthdayPerson,
    prominent: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        color = if (prominent) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerLow
        },
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PersonAvatar(
                name = person.displayName,
                size = if (prominent) 56.dp else 44.dp,
                entityId = person.uwcId,
                kind = person.toEntity().kind,
                knownUrl = person.photoUrl,
            )
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    person.displayName,
                    style = if (prominent) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    person.roleLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (prominent) {
                Icon(
                    Icons.Default.Cake,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

private val DISPLAY_DAY: DateTimeFormatter = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK)
private val WEEKDAY: DateTimeFormatter = DateTimeFormatter.ofPattern("EEEE", Locale.UK)

private fun captionFor(day: BirthdayDay, today: LocalDate): String {
    val date = day.date ?: return day.dateLabel
    if (date == today) return "Today"
    if (date == today.plusDays(1)) return "Tomorrow"
    val startOfWeek = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val endOfWeek = startOfWeek.plusDays(6)
    if (!date.isBefore(startOfWeek) && !date.isAfter(endOfWeek)) {
        return date.format(WEEKDAY)
    }
    return day.dateLabel
}
