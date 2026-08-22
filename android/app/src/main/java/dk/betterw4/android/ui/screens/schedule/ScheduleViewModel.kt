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
import dk.betterw4.android.feature.schedule.CustomEvents
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
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
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
    /** ISO week keys (`year-week`) currently being fetched from W4. */
    val loadingWeekKeys: Set<String> = emptySet(),
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
    val privateStart: LocalDateTime = W4Dates.today().atTime(8, 0),
    val privateEnd: LocalDateTime = W4Dates.today().atTime(9, 0),
    val privateAllDay: Boolean = false,
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
    /** Other-person weeks currently in memory: key = "id-year-week". */
    private val personWeekCache = ConcurrentHashMap<String, ScheduleWeek>()

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

    /** True once this day's week has been merged into [ScheduleUiState.eventsByDate]. */
    fun isDayLoaded(date: LocalDate): Boolean {
        val s = _state.value
        return date in s.eventsByDate || date in s.knownEmptyDays
    }

    /** True while W4 is still answering for this day's week and there is nothing to draw. */
    fun isDayLoading(date: LocalDate): Boolean {
        if (isDayLoaded(date)) return false
        return weekKey(IsoDateUtils.isoWeekYear(date), IsoDateUtils.isoWeek(date)) in
            _state.value.loadingWeekKeys
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
        _state.update { it.copy(loadingWeekKeys = it.loadingWeekKeys + key) }

        viewModelScope.launch {
            if (!force && !weekCache.containsKey(key)) {
                repository.cachedWeek(y, w)?.let { cached ->
                    weekCache[key] = cached
                    mergeWeekIntoState(cached, setAsPrimary = setAsPrimary)
                    if (setAsPrimary) publishLiveAndWidget(cached)
                }
            }
            val hasData = weekCache.containsKey(key)
            _state.update {
                it.copy(
                    loading = when {
                        force && setAsPrimary -> true
                        setAsPrimary && hasData -> false
                        setAsPrimary && it.week == null && !hasData -> true
                        else -> it.loading
                    },
                    loadingWeekKeys = it.loadingWeekKeys + key,
                    error = if (setAsPrimary && hasData) null else it.error,
                )
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
            _state.update {
                it.copy(
                    loadingWeekKeys = it.loadingWeekKeys - key,
                    loading = if (setAsPrimary) false else it.loading,
                )
            }
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
                SchoolCalendar.subjectMappingKeys(week.days.flatMap { it.events }),
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
        val cached = personWeekCache[personWeekKey(entity.id, year, week)]
            ?: roomScheduleRepo.cachedPersonWeek(entity, year, week)
        if (cached != null) {
            personWeekCache[personWeekKey(entity.id, year, week)] = cached
        }
        _state.update {
            it.copy(
                selectedPerson = entity,
                studentProfile = StudentProfile.from(entity, null),
                personSchedule = cached,
                personWeekYear = year,
                personWeek = week,
                personLoading = cached == null,
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
            val weekData = (weekRes as? AppResult.Success)?.data
            if (weekData != null) {
                personWeekCache[personWeekKey(entity.id, year, week)] = weekData
            }
            _state.update {
                it.copy(
                    personLoading = false,
                    personSchedule = weekData ?: it.personSchedule,
                    studentProfile = StudentProfile.from(entity, placement, parsed),
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
        val cacheKey = personWeekKey(entity.id, year, week)
        val memory = personWeekCache[cacheKey]
        val cached = memory ?: roomScheduleRepo.cachedPersonWeek(entity, year, week)
        if (cached != null) {
            personWeekCache[cacheKey] = cached
        }
        _state.update {
            it.copy(
                personLoading = cached == null,
                personWeekYear = year,
                personWeek = week,
                personSchedule = cached,
            )
        }
        if (memory != null) return@launch
        when (val res = roomScheduleRepo.loadPersonWeek(entity, year, week)) {
            is AppResult.Success -> {
                personWeekCache[cacheKey] = res.data
                _state.update {
                    it.copy(
                        personLoading = false,
                        personWeekYear = year,
                        personWeek = week,
                        personSchedule = res.data,
                    )
                }
            }
            is AppResult.Failure -> _state.update { it.copy(personLoading = false) }
        }
    }

    private fun personWeekKey(id: String, year: Int, week: Int) = "$id-$year-$week"

    fun openPrivateEventSheet(at: LocalDateTime? = null) {
        val start = at ?: CustomEvents.defaultStart(_state.value.selectedDate, W4Dates.now())
        _state.update {
            it.copy(
                showPrivateEvent = true,
                editingPrivateEventId = null,
                privateTitle = "",
                privateNote = "",
                privateStart = start,
                privateEnd = start.plusHours(1),
                privateAllDay = false,
                message = null,
            )
        }
    }

    fun openEditPrivateEvent(event: ScheduleEvent) {
        val start = event.start ?: event.date.atTime(8, 0)
        val end = event.end ?: start.plusHours(1)
        _state.update {
            it.copy(
                showPrivateEvent = true,
                editingPrivateEventId = event.id,
                privateTitle = event.title,
                privateNote = event.notes.orEmpty(),
                privateStart = start,
                privateEnd = if (event.isAllDay && end.toLocalTime() == LocalTime.MIDNIGHT) {
                    end.minusSeconds(1)
                } else {
                    end
                },
                privateAllDay = event.isAllDay,
                selectedEvent = null,
                lessonDetail = null,
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
        start: LocalDateTime? = null,
        end: LocalDateTime? = null,
        allDay: Boolean? = null,
    ) {
        _state.update {
            val nextStart: LocalDateTime
            val nextEnd: LocalDateTime
            if (start != null) {
                val duration = Duration.between(it.privateStart, it.privateEnd)
                    .coerceAtLeast(Duration.ofMinutes(15))
                nextStart = start
                nextEnd = start.plus(duration)
            } else {
                nextStart = it.privateStart
                val proposedEnd = end ?: it.privateEnd
                nextEnd = if (proposedEnd.isAfter(nextStart)) {
                    proposedEnd
                } else {
                    nextStart.plusHours(1)
                }
            }
            it.copy(
                privateTitle = title ?: it.privateTitle,
                privateNote = note ?: it.privateNote,
                privateStart = nextStart,
                privateEnd = nextEnd,
                privateAllDay = allDay ?: it.privateAllDay,
            )
        }
    }

    fun consumeMessage() {
        _state.update { it.copy(message = null) }
    }

    fun savePrivateEvent() {
        val s = _state.value
        if (s.privateTitle.isBlank()) {
            _state.update { it.copy(message = UiText.Res(R.string.private_event_title_required)) }
            return
        }
        viewModelScope.launch {
            val dateFmt = DateTimeFormatter.ofPattern("dd/MM-yyyy")
            val timeFmt = DateTimeFormatter.ofPattern("HH:mm")
            val draft = PrivateEventDraft(
                title = s.privateTitle,
                startDate = s.privateStart.toLocalDate().format(dateFmt),
                startTime = s.privateStart.toLocalTime().format(timeFmt),
                endDate = s.privateEnd.toLocalDate().format(dateFmt),
                endTime = s.privateEnd.toLocalTime().format(timeFmt),
                note = s.privateNote,
                eventId = s.editingPrivateEventId,
                isAllDay = s.privateAllDay,
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
                            message = null,
                        )
                    }
                    if (!isEdit) {
                        reviewPromptCoordinator.maybePrompt(ReviewTrigger.PrivateEventCreated)
                    }
                    relayoutLocalEvents(focusDate = res.data.date)
                }
                is AppResult.Failure -> _state.update {
                    it.copy(message = UiText.Raw(res.error.toString()))
                }
            }
        }
    }

    fun canEditPrivateEvent(event: ScheduleEvent): Boolean = canDeleteEvent(event)

    fun canDeleteEvent(event: ScheduleEvent): Boolean =
        PrivateEventIds.isPrivateEvent(event)

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
            relayoutLocalEvents()
        }
    }

    /**
     * Re-lays device-local custom events over weeks already in memory.
     * Creating an event must not wait on W4.
     */
    private fun relayoutLocalEvents(focusDate: LocalDate? = null) {
        if (weekCache.isEmpty()) {
            refresh(force = false)
            focusDate?.let { selectDate(it) }
            return
        }
        val remeshed = weekCache.mapValues { (_, week) -> repository.overlayLocal(week) }
        weekCache.putAll(remeshed)
        remeshed.values.forEach { week ->
            val selected = _state.value.selectedDate
            val isPrimary = IsoDateUtils.isoWeekYear(selected) == week.year &&
                IsoDateUtils.isoWeek(selected) == week.week
            mergeWeekIntoState(week, setAsPrimary = isPrimary)
        }
        wearPublisher.publishWeeks(weekCache.values)
        weekCache[weekKey(_state.value.year, _state.value.weekNum)]?.let { publishLiveAndWidget(it) }
        if (focusDate != null && focusDate != _state.value.selectedDate) {
            selectDate(focusDate)
        }
    }

    private fun maybePromptReview() {
        if (reviewPromptScheduled) return
        reviewPromptScheduled = true
        reviewPromptCoordinator.maybePrompt(ReviewTrigger.ScheduleLoaded)
    }
}
