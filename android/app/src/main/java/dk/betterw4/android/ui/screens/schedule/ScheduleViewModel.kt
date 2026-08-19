package dk.betterw4.android.ui.screens.schedule

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.R
import dk.betterw4.android.core.i18n.UiText
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.util.IsoDateUtils
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.campus.CampusStatusRepository
import dk.betterw4.android.feature.live.LiveLessonNotifier
import dk.betterw4.android.feature.live.LiveLessonScheduler
import dk.betterw4.android.feature.notifications.W4NotificationItem
import dk.betterw4.android.feature.notifications.W4NotificationRepository
import dk.betterw4.android.feature.review.ReviewPromptCoordinator
import dk.betterw4.android.feature.review.ReviewTrigger
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryPinRepository
import dk.betterw4.android.feature.directory.DirectoryRepository
import dk.betterw4.android.feature.directory.HouseRepository
import dk.betterw4.android.feature.directory.RoomScheduleRepository
import dk.betterw4.android.feature.directory.StudentProfile
import dk.betterw4.android.feature.schedule.LessonDetail
import dk.betterw4.android.feature.schedule.PersonClasses
import dk.betterw4.android.feature.schedule.PrivateEventDraft
import dk.betterw4.android.feature.schedule.PrivateEventIds
import dk.betterw4.android.feature.schedule.ScheduleDay
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.ScheduleRepository
import dk.betterw4.android.feature.schedule.ScheduleWeek
import dk.betterw4.android.feature.schedule.SchoolCalendar
import dk.betterw4.android.feature.schedule.timeLabel
import dk.betterw4.android.feature.settings.CalendarStyle
import dk.betterw4.android.feature.settings.SettingsStore
import dk.betterw4.android.feature.wear.PhoneWearSchedulePublisher
import dk.betterw4.android.feature.widget.ScheduleWidgetProjector
import dk.betterw4.android.feature.widget.ScheduleWidgetSnapshot
import dk.betterw4.android.feature.widget.WidgetLesson
import dk.betterw4.android.feature.widget.WidgetSnapshot
import dk.betterw4.android.wear.model.WearSyncStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject

data class ScheduleUiState(
    val loading: Boolean = true,
    /** Current week for strip/header (always the week of [selectedDate]). */
    val week: ScheduleWeek? = null,
    val year: Int = IsoDateUtils.isoWeekYear(),
    val weekNum: Int = IsoDateUtils.isoWeek(),
    val selectedDate: LocalDate = W4Dates.today(),
    /** Merged events for any loaded day (multi-week cache for day swipe). */
    val eventsByDate: Map<LocalDate, List<ScheduleEvent>> = emptyMap(),
    /** Rotation / no-classes metadata for any loaded day. */
    val daysByDate: Map<LocalDate, ScheduleDay> = emptyMap(),
    /** Days known to have zero events (vs not loaded). */
    val knownEmptyDays: Set<LocalDate> = emptySet(),
    val selectedEvent: ScheduleEvent? = null,
    val lessonDetail: LessonDetail? = null,
    val detailLoading: Boolean = false,
    /** Person opened from the class roster in the lesson sheet. */
    val selectedPerson: DirectoryEntity? = null,
    val studentProfile: StudentProfile? = null,
    val personSchedule: ScheduleWeek? = null,
    val personWeekYear: Int = IsoDateUtils.isoWeekYear(),
    val personWeek: Int = IsoDateUtils.isoWeek(),
    val personLoading: Boolean = false,
    val pinnedIds: Set<String> = emptySet(),
    val showPrivateEvent: Boolean = false,
    /** Non-null when editing an existing private event. */
    val editingPrivateEventId: String? = null,
    val privateTitle: String = "",
    val privateNote: String = "",
    val privateStartDate: String = "",
    val privateStartTime: String = "08:00",
    val privateEndDate: String = "",
    val privateEndTime: String = "09:00",
    val message: UiText? = null,
    val error: AppError? = null,
    val campus: dk.betterw4.android.feature.campus.CampusStatus? = null,
    val notifications: dk.betterw4.android.feature.notifications.W4NotificationSnapshot =
        dk.betterw4.android.feature.notifications.W4NotificationSnapshot(),
    val pendingNotificationHref: String? = null,
)

@HiltViewModel
class ScheduleViewModel @Inject constructor(
    private val repository: ScheduleRepository,
    private val roomScheduleRepo: RoomScheduleRepository,
    private val houseRepo: HouseRepository,
    private val directoryRepo: DirectoryRepository,
    private val pinRepo: DirectoryPinRepository,
    private val campusStatus: CampusStatusRepository,
    private val notificationsRepo: W4NotificationRepository,
    private val liveLessonNotifier: LiveLessonNotifier,
    private val liveLessonScheduler: LiveLessonScheduler,
    private val settings: SettingsStore,
    private val reviewPromptCoordinator: ReviewPromptCoordinator,
    private val wearPublisher: PhoneWearSchedulePublisher,
    @ApplicationContext private val appContext: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(ScheduleUiState())
    val state: StateFlow<ScheduleUiState> = _state.asStateFlow()

    private var reviewPromptScheduled = false

    val calendarStyle: StateFlow<CalendarStyle> = settings.calendarStyle
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.calendarStyle.value)

    val useSubjectColors: StateFlow<Boolean> = settings.useSubjectColors
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.useSubjectColors.value)

    val showSchoolCalendar: StateFlow<Boolean> = settings.showSchoolCalendar
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.showSchoolCalendar.value)

    val subjectColors: StateFlow<Map<String, Long>> = settings.subjectColors
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.subjectColors.value)

    val subjectNames: StateFlow<Map<String, String>> = settings.subjectNames
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.subjectNames.value)

    /** Collect so schedule recomposes when lesson mappings change. */
    val lessonMappings = settings.lessonMappings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.lessonMappings.value)

    /** Weeks currently in memory: key = "year-week". */
    private val weekCache = ConcurrentHashMap<String, ScheduleWeek>()
    private val loadingWeeks = ConcurrentHashMap.newKeySet<String>()

    init {
        val today = W4Dates.today()
        _state.update {
            it.copy(
                selectedDate = today,
                year = IsoDateUtils.isoWeekYear(today),
                weekNum = IsoDateUtils.isoWeek(today),
            )
        }
        refresh()
        // Prefetch adjacent weeks for smooth day/week swipes
        ensureWeekLoaded(today.minusWeeks(1), force = false)
        ensureWeekLoaded(today.plusWeeks(1), force = false)
        viewModelScope.launch {
            campusStatus.status.collect { status ->
                _state.update { it.copy(campus = status) }
            }
        }
        viewModelScope.launch { campusStatus.refresh() }
        notificationsRepo.startPolling()
        viewModelScope.launch {
            notificationsRepo.snapshot.collect { snap ->
                _state.update { it.copy(notifications = snap) }
            }
        }
        viewModelScope.launch {
            var previous = settings.showSchoolCalendar.value
            settings.showSchoolCalendar.collect { enabled ->
                weekCache[weekKey(_state.value.year, _state.value.weekNum)]?.let {
                    publishLiveAndWidget(it)
                }
                if (enabled && !previous) {
                    val missing = weekCache.values.none { week ->
                        week.days.any { day -> day.events.any(SchoolCalendar::isSchoolCalendarEvent) }
                    }
                    if (missing) {
                        weekCache.clear()
                        refresh(force = true)
                    }
                }
                previous = enabled
            }
        }
    }

    fun setNotificationsOpen(open: Boolean) {
        notificationsRepo.setDropdownOpen(open)
    }

    fun markNotificationRead(item: W4NotificationItem) = viewModelScope.launch {
        notificationsRepo.markRead(item.id)
        _state.update { it.copy(pendingNotificationHref = item.href) }
    }

    fun consumeNotificationHref() {
        _state.update { it.copy(pendingNotificationHref = null) }
    }

    fun markAllNotificationsRead() = viewModelScope.launch {
        notificationsRepo.markAllRead()
    }

    fun markAllNotificationEmailsRead() = viewModelScope.launch {
        notificationsRepo.markAllEmailsRead()
    }

    fun accentArgbFor(event: ScheduleEvent): Long = settings.accentArgbFor(event)

    fun displayTitle(event: ScheduleEvent): String = settings.displayTitleForEvent(event)

    fun eventsFor(date: LocalDate): List<ScheduleEvent> =
        visibleEvents(_state.value.eventsByDate[date].orEmpty())

    fun visibleEvents(events: List<ScheduleEvent>): List<ScheduleEvent> =
        SchoolCalendar.visibleEvents(events, showSchoolCalendar.value)

    fun setShowSchoolCalendar(enabled: Boolean) {
        settings.setShowSchoolCalendar(enabled)
    }

    /**
     * Whether the day has lessons for the date-strip tint.
     * Unknown/unloaded days return false so weekends/empty days never look busy by default.
     */
    fun hasEvents(date: LocalDate): Boolean {
        val s = _state.value
        if (date in s.knownEmptyDays && date !in s.eventsByDate) return false
        if (date in s.eventsByDate) return visibleEvents(s.eventsByDate[date].orEmpty()).isNotEmpty()
        s.week?.days?.find { it.date == date }?.let { return visibleEvents(it.events).isNotEmpty() }
        return false
    }

    fun refresh(force: Boolean = false) {
        val date = _state.value.selectedDate
        ensureWeekLoaded(date, force = force, setAsPrimary = true)
        ensureWeekLoaded(date.minusWeeks(1), force = force)
        ensureWeekLoaded(date.plusWeeks(1), force = force)
        if (force) {
            viewModelScope.launch { campusStatus.refresh() }
        }
    }

    fun prevWeek() = shiftWeek(-1)
    fun nextWeek() = shiftWeek(1)

    private fun shiftWeek(delta: Int) {
        val current = _state.value.selectedDate
        val target = current.plusWeeks(delta.toLong())
        selectDate(target)
    }

    /**
     * Select a day. Loads the week if needed and keeps adjacent weeks warm.
     */
    fun selectDate(date: LocalDate) {
        val y = IsoDateUtils.isoWeekYear(date)
        val w = IsoDateUtils.isoWeek(date)
        _state.update {
            it.copy(
                selectedDate = date,
                year = y,
                weekNum = w,
                selectedEvent = null,
                lessonDetail = null,
            )
        }
        // Promote cached week to primary if available
        weekCache[weekKey(y, w)]?.let { week ->
            _state.update { it.copy(week = week, loading = false, error = null) }
        }
        ensureWeekLoaded(date, force = false, setAsPrimary = true)
        ensureWeekLoaded(date.minusWeeks(1), force = false)
        ensureWeekLoaded(date.plusWeeks(1), force = false)
    }

    private fun weekKey(year: Int, week: Int) = "$year-$week"

    private fun ensureWeekLoaded(
        date: LocalDate,
        force: Boolean,
        setAsPrimary: Boolean = false,
    ) {
        val y = IsoDateUtils.isoWeekYear(date)
        val w = IsoDateUtils.isoWeek(date)
        val key = weekKey(y, w)

        if (!force && weekCache.containsKey(key)) {
            if (setAsPrimary) {
                weekCache[key]?.let { week ->
                    mergeWeekIntoState(week, setAsPrimary = true)
                    publishLiveAndWidget(week)
                }
            }
            return
        }
        if (!force && !loadingWeeks.add(key)) return
        if (force) loadingWeeks.add(key)

        viewModelScope.launch {
            if (setAsPrimary) {
                _state.update { it.copy(loading = true, error = null) }
            }
            when (val res = repository.loadWeek(y, w, force)) {
                is AppResult.Success -> {
                    weekCache[key] = res.data
                    mergeWeekIntoState(res.data, setAsPrimary = setAsPrimary)
                    wearPublisher.publishWeeks(weekCache.values)
                    if (setAsPrimary) {
                        publishLiveAndWidget(res.data)
                        maybePromptReview()
                    }
                }
                is AppResult.Failure -> {
                    if (res.error is AppError.Unauthorized || res.error is AppError.SessionExpired) {
                        wearPublisher.publishStatus(WearSyncStatus.AUTH_REQUIRED)
                    }
                    if (setAsPrimary) {
                        reviewPromptCoordinator.reportRecentError()
                    }
                    if (setAsPrimary && _state.value.week == null) {
                        _state.update { it.copy(loading = false, error = res.error) }
                    } else if (setAsPrimary) {
                        _state.update { it.copy(loading = false) }
                    }
                }
            }
            loadingWeeks.remove(key)
        }
    }

    private fun mergeWeekIntoState(week: ScheduleWeek, setAsPrimary: Boolean) {
        _state.update { s ->
            val map = s.eventsByDate.toMutableMap()
            val daysMap = s.daysByDate.toMutableMap()
            val empty = s.knownEmptyDays.toMutableSet()
            val eventsByDate = week.days.associate { it.date to it.events }

            // Always materialise Mon–Sun for the ISO week. Lectio often omits empty
            // weekend columns, which used to leave Sat/Sun "unknown" and tinted busy.
            val weekStart = IsoDateUtils.weekStart(week.year, week.week)
            val fullDays = (0 until 7).map { offset ->
                val date = weekStart.plusDays(offset.toLong())
                val events = eventsByDate[date].orEmpty()
                map[date] = events
                if (events.isEmpty()) empty.add(date) else empty.remove(date)
                week.days.find { it.date == date }
                    ?: ScheduleDay(date = date, events = events)
            }
            fullDays.forEach { daysMap[it.date] = it }

            val normalizedWeek = week.copy(days = fullDays)
            settings.noteObservedHolds(
                week.days.flatMap { day -> day.events.flatMap { listOf(it.team, it.title) } },
            )
            val selected = s.selectedDate
            val primary = if (setAsPrimary) {
                normalizedWeek
            } else if (
                s.week == null ||
                (IsoDateUtils.isoWeekYear(selected) == week.year &&
                    IsoDateUtils.isoWeek(selected) == week.week)
            ) {
                normalizedWeek
            } else {
                s.week
            }
            s.copy(
                loading = if (setAsPrimary) false else s.loading,
                week = primary,
                eventsByDate = map,
                daysByDate = daysMap,
                knownEmptyDays = empty,
                error = if (setAsPrimary) null else s.error,
            )
        }
    }

    private fun publishLiveAndWidget(week: ScheduleWeek) {
        val today = W4Dates.today()
        val todayEvents = visibleEvents(week.days.find { it.date == today }?.events.orEmpty())
        val now = W4Dates.now()
        liveLessonNotifier.update(todayEvents, now)
        liveLessonScheduler.scheduleBoundaries(todayEvents, now)
        val zone = W4Dates.ZONE
        ScheduleWidgetSnapshot.write(
            appContext,
            WidgetSnapshot(
                date = today.toString(),
                dayLabel = ScheduleWidgetSnapshot.defaultDayLabel(today),
                lessons = todayEvents.map { e ->
                    val range = e.timeLabel(appContext)
                    val startLabel = when {
                        e.isAllDay -> appContext.getString(R.string.event_all_day)
                        else -> ScheduleWidgetProjector.startLabelFromEpoch(
                            ScheduleWidgetSnapshot.epochMilli(e.start, zone),
                            zone,
                        ) ?: range.take(5)
                    }
                    WidgetLesson(
                        id = e.id,
                        title = displayTitle(e),
                        startLabel = startLabel,
                        timeRange = range,
                        room = e.room,
                        status = e.status.name,
                        accentArgb = accentArgbFor(e),
                        startEpochMilli = ScheduleWidgetSnapshot.epochMilli(e.start, zone),
                        endEpochMilli = ScheduleWidgetSnapshot.epochMilli(e.end, zone),
                        isAllDay = e.isAllDay,
                    )
                },
            ),
        )
    }

    fun selectEvent(event: ScheduleEvent?) {
        if (event == null) {
            _state.update {
                it.copy(
                    selectedEvent = null,
                    lessonDetail = null,
                    detailLoading = false,
                    selectedPerson = null,
                    studentProfile = null,
                    personSchedule = null,
                    personLoading = false,
                )
            }
            return
        }
        _state.update {
            it.copy(
                selectedEvent = event,
                detailLoading = true,
                lessonDetail = null,
                selectedPerson = null,
                studentProfile = null,
                personSchedule = null,
                personLoading = false,
                pinnedIds = pinRepo.pinnedIds(),
            )
        }
        viewModelScope.launch {
            when (val res = repository.loadLessonDetail(event)) {
                is AppResult.Success -> _state.update {
                    it.copy(detailLoading = false, lessonDetail = res.data)
                }
                is AppResult.Failure -> _state.update {
                    it.copy(
                        detailLoading = false,
                        lessonDetail = LessonDetail(
                            eventId = event.id,
                            title = event.title,
                            note = event.notes,
                            homework = event.homework,
                        ),
                    )
                }
            }
        }
    }

    fun openPerson(entity: DirectoryEntity) = viewModelScope.launch {
        val year = IsoDateUtils.isoWeekYear()
        val week = IsoDateUtils.isoWeek()
        _state.update {
            it.copy(
                selectedPerson = entity,
                studentProfile = StudentProfile.from(entity, null),
                personSchedule = null,
                personWeekYear = year,
                personWeek = week,
                personLoading = true,
                pinnedIds = pinRepo.pinnedIds(),
            )
        }
        coroutineScope {
            val weekDeferred = async { roomScheduleRepo.loadPersonWeek(entity, year, week) }
            val placementDeferred = async {
                if (entity.kind == dk.betterw4.android.feature.directory.DirectoryEntityKind.TEACHER) {
                    null
                } else {
                    houseRepo.findPlacement(entity.id)
                }
            }
            val profileDeferred = async { directoryRepo.loadProfile(entity) }
            val weekRes = weekDeferred.await()
            val placement = placementDeferred.await()
            val parsed = (profileDeferred.await() as? AppResult.Success)?.data
            val classes = when (weekRes) {
                is AppResult.Success -> PersonClasses.fromWeek(weekRes.data)
                is AppResult.Failure -> emptyList()
            }
            _state.update {
                it.copy(
                    personLoading = false,
                    personSchedule = (weekRes as? AppResult.Success)?.data,
                    studentProfile = StudentProfile.from(entity, placement, classes, parsed),
                )
            }
        }
    }

    fun closePerson() {
        _state.update {
            it.copy(
                selectedPerson = null,
                studentProfile = null,
                personSchedule = null,
                personLoading = false,
            )
        }
    }

    fun togglePersonPin() {
        val entity = _state.value.selectedPerson ?: return
        pinRepo.toggle(entity.id)
        _state.update { it.copy(pinnedIds = pinRepo.pinnedIds()) }
    }

    fun shiftPersonWeek(delta: Int) {
        val currentStart = IsoDateUtils.weekStart(
            _state.value.personWeekYear,
            _state.value.personWeek,
        )
        loadPersonWeekForDate(currentStart.plusWeeks(delta.toLong()))
    }

    fun goToPersonToday() {
        loadPersonWeekForDate(W4Dates.today())
    }

    fun loadPersonWeekForDate(date: LocalDate) = viewModelScope.launch {
        val entity = _state.value.selectedPerson ?: return@launch
        val year = IsoDateUtils.isoWeekYear(date)
        val week = IsoDateUtils.isoWeek(date)
        if (year == _state.value.personWeekYear &&
            week == _state.value.personWeek &&
            _state.value.personSchedule != null
        ) {
            return@launch
        }
        _state.update { it.copy(personLoading = true) }
        when (val res = roomScheduleRepo.loadPersonWeek(entity, year, week)) {
            is AppResult.Success -> _state.update {
                val merged = PersonClasses.merge(
                    it.studentProfile?.classes.orEmpty(),
                    PersonClasses.fromWeek(res.data),
                )
                it.copy(
                    personLoading = false,
                    personWeekYear = year,
                    personWeek = week,
                    personSchedule = res.data,
                    studentProfile = (it.studentProfile
                        ?: StudentProfile(id = entity.id, name = entity.name, kind = entity.kind))
                        .copy(classes = merged),
                )
            }
            is AppResult.Failure -> _state.update { it.copy(personLoading = false) }
        }
    }

    fun openPrivateEventSheet() {
        val d = _state.value.selectedDate
        val fmt = DateTimeFormatter.ofPattern("dd/MM-yyyy")
        _state.update {
            it.copy(
                showPrivateEvent = true,
                editingPrivateEventId = null,
                privateTitle = "",
                privateNote = "",
                privateStartDate = d.format(fmt),
                privateEndDate = d.format(fmt),
                privateStartTime = "08:00",
                privateEndTime = "09:00",
                message = null,
            )
        }
    }

    fun openEditPrivateEvent(event: ScheduleEvent) {
        val dateFmt = DateTimeFormatter.ofPattern("dd/MM-yyyy")
        val timeFmt = DateTimeFormatter.ofPattern("HH:mm")
        _state.update {
            it.copy(
                showPrivateEvent = true,
                editingPrivateEventId = event.id,
                privateTitle = event.title,
                privateNote = event.notes.orEmpty(),
                privateStartDate = (event.start?.toLocalDate() ?: event.date).format(dateFmt),
                privateEndDate = (event.end?.toLocalDate() ?: event.date).format(dateFmt),
                privateStartTime = event.start?.format(timeFmt) ?: "08:00",
                privateEndTime = event.end?.format(timeFmt) ?: "09:00",
                message = null,
            )
        }
    }

    fun closePrivateEventSheet() {
        _state.update { it.copy(showPrivateEvent = false, editingPrivateEventId = null) }
    }

    fun updatePrivateField(
        title: String? = null,
        note: String? = null,
        startDate: String? = null,
        startTime: String? = null,
        endDate: String? = null,
        endTime: String? = null,
    ) {
        _state.update {
            it.copy(
                privateTitle = title ?: it.privateTitle,
                privateNote = note ?: it.privateNote,
                privateStartDate = startDate ?: it.privateStartDate,
                privateStartTime = startTime ?: it.privateStartTime,
                privateEndDate = endDate ?: it.privateEndDate,
                privateEndTime = endTime ?: it.privateEndTime,
            )
        }
    }

    fun savePrivateEvent() {
        val s = _state.value
        if (s.privateTitle.isBlank()) {
            _state.update { it.copy(message = UiText.Res(R.string.private_event_title_required)) }
            return
        }
        viewModelScope.launch {
            val draft = PrivateEventDraft(
                title = s.privateTitle,
                startDate = s.privateStartDate,
                startTime = s.privateStartTime,
                endDate = s.privateEndDate,
                endTime = s.privateEndTime,
                note = s.privateNote,
                eventId = s.editingPrivateEventId,
            )
            val isEdit = s.editingPrivateEventId != null
            when (val res = repository.createPrivateEvent(draft)) {
                is AppResult.Success -> {
                    _state.update {
                        it.copy(
                            showPrivateEvent = false,
                            editingPrivateEventId = null,
                            selectedEvent = null,
                            lessonDetail = null,
                            message = UiText.Res(
                                if (isEdit) R.string.private_event_updated
                                else R.string.private_event_created,
                            ),
                        )
                    }
                    if (!isEdit) {
                        reviewPromptCoordinator.maybePrompt(ReviewTrigger.PrivateEventCreated)
                    }
                    // Invalidate cache for the week and reload
                    weekCache.clear()
                    refresh(force = true)
                }
                is AppResult.Failure -> _state.update {
                    it.copy(message = UiText.Raw(res.error.toString()))
                }
            }
        }
    }

    fun canEditPrivateEvent(event: ScheduleEvent): Boolean = canDeleteEvent(event)

    fun canDeleteEvent(event: ScheduleEvent): Boolean =
        PrivateEventIds.isPrivateEvent(event) ||
            repository.localPrivate.contains(event.id)

    fun deletePrivateEvent(event: ScheduleEvent) {
        viewModelScope.launch {
            repository.deletePrivateEvent(event)
            _state.update {
                it.copy(
                    selectedEvent = null,
                    lessonDetail = null,
                    message = UiText.Res(R.string.private_event_deleted),
                )
            }
            weekCache.clear()
            refresh(force = true)
        }
    }

    private fun maybePromptReview() {
        if (reviewPromptScheduled) return
        reviewPromptScheduled = true
        reviewPromptCoordinator.maybePrompt(ReviewTrigger.ScheduleLoaded)
    }
}
