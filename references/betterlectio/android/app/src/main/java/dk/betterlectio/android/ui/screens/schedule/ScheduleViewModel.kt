package dk.betterlectio.android.ui.screens.schedule

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.posthog.PostHog
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.R
import dk.betterlectio.android.core.i18n.UiText
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.core.util.LectioDateUtils
import dk.betterlectio.android.feature.live.LiveLessonNotifier
import dk.betterlectio.android.feature.live.LiveLessonScheduler
import dk.betterlectio.android.feature.referral.ReferralCoordinator
import dk.betterlectio.android.feature.referral.buildReferralUrl
import dk.betterlectio.android.feature.referral.referralUnlockProgress
import dk.betterlectio.android.feature.review.ReviewPromptCoordinator
import dk.betterlectio.android.feature.review.ReviewTrigger
import dk.betterlectio.android.feature.schedule.LessonDetail
import dk.betterlectio.android.feature.schedule.PrivateEventDraft
import dk.betterlectio.android.feature.schedule.PrivateEventIds
import dk.betterlectio.android.feature.schedule.ScheduleDay
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.schedule.ScheduleRepository
import dk.betterlectio.android.feature.schedule.ScheduleWeek
import dk.betterlectio.android.feature.schedule.timeLabel
import dk.betterlectio.android.feature.settings.CalendarStyle
import dk.betterlectio.android.feature.settings.SettingsStore
import dk.betterlectio.android.feature.wear.PhoneWearSchedulePublisher
import dk.betterlectio.android.feature.widget.ScheduleWidgetProjector
import dk.betterlectio.android.feature.widget.ScheduleWidgetSnapshot
import dk.betterlectio.android.feature.widget.WidgetLesson
import dk.betterlectio.android.feature.widget.WidgetSnapshot
import dk.betterlectio.android.wear.model.WearSyncStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject

data class ScheduleUiState(
    val loading: Boolean = true,
    /** Current week for strip/header (always the week of [selectedDate]). */
    val week: ScheduleWeek? = null,
    val year: Int = LectioDateUtils.isoWeekYear(),
    val weekNum: Int = LectioDateUtils.isoWeek(),
    val selectedDate: LocalDate = LocalDate.now(),
    /** Merged events for any loaded day (multi-week cache for day swipe). */
    val eventsByDate: Map<LocalDate, List<ScheduleEvent>> = emptyMap(),
    /** Days known to have zero events (vs not loaded). */
    val knownEmptyDays: Set<LocalDate> = emptySet(),
    val selectedEvent: ScheduleEvent? = null,
    val lessonDetail: LessonDetail? = null,
    val detailLoading: Boolean = false,
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
)

@HiltViewModel
class ScheduleViewModel @Inject constructor(
    private val repository: ScheduleRepository,
    private val liveLessonNotifier: LiveLessonNotifier,
    private val liveLessonScheduler: LiveLessonScheduler,
    private val settings: SettingsStore,
    private val session: SessionController,
    private val referralCoordinator: ReferralCoordinator,
    private val reviewPromptCoordinator: ReviewPromptCoordinator,
    private val wearPublisher: PhoneWearSchedulePublisher,
    @ApplicationContext private val appContext: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(ScheduleUiState())
    val state: StateFlow<ScheduleUiState> = _state.asStateFlow()

    val referralNudgeVisible = referralCoordinator.nudgeVisible
    val referralCelebrationName = referralCoordinator.celebrationName
    private var referralNudgeScheduled = false

    val calendarStyle: StateFlow<CalendarStyle> = settings.calendarStyle
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.calendarStyle.value)

    val useSubjectColors: StateFlow<Boolean> = settings.useSubjectColors
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.useSubjectColors.value)

    val subjectColors: StateFlow<Map<String, Long>> = settings.subjectColors
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.subjectColors.value)

    val subjectNames: StateFlow<Map<String, String>> = settings.subjectNames
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.subjectNames.value)

    /** Collect so schedule recomposes when Supabase lesson mappings arrive. */
    val lessonMappings = settings.lessonMappings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.lessonMappings.value)

    /** Weeks currently in memory: key = "year-week". */
    private val weekCache = ConcurrentHashMap<String, ScheduleWeek>()
    private val loadingWeeks = ConcurrentHashMap.newKeySet<String>()

    init {
        val today = LocalDate.now()
        _state.update {
            it.copy(
                selectedDate = today,
                year = LectioDateUtils.isoWeekYear(today),
                weekNum = LectioDateUtils.isoWeek(today),
            )
        }
        refresh()
        // Prefetch adjacent weeks for smooth day/week swipes
        ensureWeekLoaded(today.minusWeeks(1), force = false)
        ensureWeekLoaded(today.plusWeeks(1), force = false)
    }

    fun accentArgbFor(event: ScheduleEvent): Long = settings.accentArgbFor(event)

    fun displayTitle(event: ScheduleEvent): String {
        // Prefer team hold code (e.g. "1x MA") so canonical-key resolution works;
        // fall back to title for private events / all-day without team.
        val key = event.team.ifBlank { event.title }
        return settings.displayNameForSubject(key, fallback = event.title.ifBlank { key })
    }

    fun eventsFor(date: LocalDate): List<ScheduleEvent> =
        _state.value.eventsByDate[date].orEmpty()

    /**
     * Whether the day has lessons for the date-strip tint.
     * Unknown/unloaded days return false so weekends/empty days never look busy by default.
     */
    fun hasEvents(date: LocalDate): Boolean {
        val s = _state.value
        if (date in s.knownEmptyDays) return false
        if (date in s.eventsByDate) return s.eventsByDate[date].orEmpty().isNotEmpty()
        s.week?.days?.find { it.date == date }?.let { return it.events.isNotEmpty() }
        return false
    }

    fun refresh(force: Boolean = false) {
        val date = _state.value.selectedDate
        ensureWeekLoaded(date, force = force, setAsPrimary = true)
        ensureWeekLoaded(date.minusWeeks(1), force = force)
        ensureWeekLoaded(date.plusWeeks(1), force = force)
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
        val y = LectioDateUtils.isoWeekYear(date)
        val w = LectioDateUtils.isoWeek(date)
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
        val y = LectioDateUtils.isoWeekYear(date)
        val w = LectioDateUtils.isoWeek(date)
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
                        maybePromptReferral()
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
            val empty = s.knownEmptyDays.toMutableSet()
            val eventsByDate = week.days.associate { it.date to it.events }

            // Always materialise Mon–Sun for the ISO week. Lectio often omits empty
            // weekend columns, which used to leave Sat/Sun "unknown" and tinted busy.
            val weekStart = LectioDateUtils.weekStart(week.year, week.week)
            val fullDays = (0 until 7).map { offset ->
                val date = weekStart.plusDays(offset.toLong())
                val events = eventsByDate[date].orEmpty()
                map[date] = events
                if (events.isEmpty()) empty.add(date) else empty.remove(date)
                week.days.find { it.date == date }
                    ?: ScheduleDay(date = date, events = events)
            }

            val normalizedWeek = week.copy(days = fullDays)
            val selected = s.selectedDate
            val primary = if (setAsPrimary) {
                normalizedWeek
            } else if (
                s.week == null ||
                (LectioDateUtils.isoWeekYear(selected) == week.year &&
                    LectioDateUtils.isoWeek(selected) == week.week)
            ) {
                normalizedWeek
            } else {
                s.week
            }
            s.copy(
                loading = if (setAsPrimary) false else s.loading,
                week = primary,
                eventsByDate = map,
                knownEmptyDays = empty,
                error = if (setAsPrimary) null else s.error,
            )
        }
    }

    private fun publishLiveAndWidget(week: ScheduleWeek) {
        val today = LocalDate.now()
        val todayEvents = week.days.find { it.date == today }?.events.orEmpty()
        val now = LocalDateTime.now()
        liveLessonNotifier.update(todayEvents, now)
        liveLessonScheduler.scheduleBoundaries(todayEvents, now)
        val zone = java.time.ZoneId.systemDefault()
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
            _state.update { it.copy(selectedEvent = null, lessonDetail = null, detailLoading = false) }
            return
        }
        PostHog.capture(
            event = "lesson_detail_viewed",
            properties = mapOf(
                "lesson_title" to event.title,
                "lesson_team" to event.team,
                "lesson_status" to event.status.name,
            ),
        )
        _state.update { it.copy(selectedEvent = event, detailLoading = true, lessonDetail = null) }
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
                    PostHog.capture(
                        event = if (isEdit) "private_event_updated" else "private_event_created",
                    )
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
            PostHog.capture(event = "private_event_deleted")
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

    private fun maybePromptReferral() {
        if (referralNudgeScheduled) return
        referralNudgeScheduled = true
        val student = session.currentStudent ?: return
        viewModelScope.launch {
            referralCoordinator.maybeShowNudge(student)
            if (!referralCoordinator.nudgeVisible.value) {
                reviewPromptCoordinator.maybePrompt(ReviewTrigger.ScheduleLoaded)
            }
        }
    }

    fun dismissReferralNudge() {
        session.currentStudent?.let { referralCoordinator.dismissNudge(it.studentId) }
    }

    fun referralShareUrl(): String? {
        val student = session.currentStudent ?: return null
        if (student.isDemo) return null
        return buildReferralUrl(student.studentId)
    }

    fun onReferralNudgeShared() {
        PostHog.capture(
            event = "referral share",
            properties = mapOf("method" to "nudge_sheet", "platform" to "android"),
        )
        dismissReferralNudge()
    }

    fun referralNudgeRemaining(): Int {
        val conversions = referralCoordinator.cachedStats.value?.conversions ?: 0
        return referralUnlockProgress(conversions).remaining
    }

    fun consumeReferralCelebration() = referralCoordinator.consumeCelebration()
}
