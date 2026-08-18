package dk.betterw4.android.feature.settings

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterw4.android.core.i18n.AppLocale
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.ScheduleEvent
import dk.betterw4.android.feature.schedule.SchoolCalendar
import dk.betterw4.android.feature.schedule.W4ClassId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

enum class AppearanceMode { SYSTEM, LIGHT, DARK }
enum class CalendarStyle { PROFESSIONAL, STANDARD }
enum class AppLanguage { SYSTEM, DANISH, ENGLISH }

/**
 * App preferences + lesson-mapping v2 store (iOS SettingsStore parity).
 *
 * Lesson mappings are scoped by student+school and resolved through [SubjectMapper].
 */
@Singleton
class SettingsStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("bl_settings", Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private var currentStudentId: String? = null
    private var currentSchoolId: String? = null
    private var cachedLessonMappingsByScope: MutableMap<String, Map<String, ResolvedLessonMapping>> =
        loadLessonMappingCache().toMutableMap()

    private val _appearance = MutableStateFlow(loadAppearance())
    val appearance: StateFlow<AppearanceMode> = _appearance.asStateFlow()

    private val _language = MutableStateFlow(loadLanguage())
    val language: StateFlow<AppLanguage> = _language.asStateFlow()

    private val _calendarStyle = MutableStateFlow(loadCalendarStyle())
    val calendarStyle: StateFlow<CalendarStyle> = _calendarStyle.asStateFlow()

    /** When true, schedule blocks use per-subject hues; when false, status blue/green/red. */
    private val _useSubjectColors = MutableStateFlow(prefs.getBoolean(KEY_USE_SUBJECT_COLORS, true))
    val useSubjectColors: StateFlow<Boolean> = _useSubjectColors.asStateFlow()

    /** When true, the public college Google Calendar is drawn on the timetable. */
    private val _showSchoolCalendar = MutableStateFlow(
        prefs.getBoolean(KEY_SHOW_SCHOOL_CALENDAR, true),
    )
    val showSchoolCalendar: StateFlow<Boolean> = _showSchoolCalendar.asStateFlow()

    private val _notifEvents = MutableStateFlow(prefs.getBoolean("notif_events", true))
    val notifEvents: StateFlow<Boolean> = _notifEvents.asStateFlow()

    private val _notifMessages = MutableStateFlow(prefs.getBoolean("notif_messages", true))
    val notifMessages: StateFlow<Boolean> = _notifMessages.asStateFlow()

    private val _notifAssignments = MutableStateFlow(prefs.getBoolean("notif_assignments", true))
    val notifAssignments: StateFlow<Boolean> = _notifAssignments.asStateFlow()

    /** When true, never append the BetterW4 signature on send/reply. */
    private val _disableSignature = MutableStateFlow(prefs.getBoolean("disable_signature", false))
    val disableSignature: StateFlow<Boolean> = _disableSignature.asStateFlow()

    private val _onboardingCompleted =
        MutableStateFlow(prefs.getBoolean(KEY_ONBOARDING_COMPLETED, false))
    val onboardingCompleted: StateFlow<Boolean> = _onboardingCompleted.asStateFlow()

    private val _lessonMappings = MutableStateFlow<Map<String, ResolvedLessonMapping>>(emptyMap())
    val lessonMappings: StateFlow<Map<String, ResolvedLessonMapping>> = _lessonMappings.asStateFlow()

    private val _observedHolds = MutableStateFlow<Set<String>>(emptySet())

    private val _notificationHistory = MutableStateFlow(loadNotificationHistory())
    val notificationHistory: StateFlow<List<String>> = _notificationHistory.asStateFlow()

    /**
     * Derived maps for Compose collectors that still key by display/canonical string.
     * Prefer [displayNameForSubject] / [colorForSubject] which canonicalize raw holds.
     */
    val subjectNames: StateFlow<Map<String, String>>
        get() = _derivedNames
    val subjectColors: StateFlow<Map<String, Long>>
        get() = _derivedColors

    private val _derivedNames = MutableStateFlow<Map<String, String>>(emptyMap())
    private val _derivedColors = MutableStateFlow<Map<String, Long>>(emptyMap())

    init {
        SubjectMapper.mappingProvider = { key -> _lessonMappings.value[key] }
        SubjectMapper.subjectInfoProvider = {
            _lessonMappings.value.values.map { m ->
                SubjectInfo(
                    code = m.canonicalKey,
                    name = m.displayName,
                    mappingId = m.mappingId,
                )
            }
        }
        // Clear legacy flat string maps if present (no longer authoritative).
        if (prefs.contains("subject_colors") || prefs.contains("subject_names")) {
            prefs.edit {
                remove("subject_colors")
                remove("subject_names")
            }
        }
    }

    fun setAppearance(mode: AppearanceMode) {
        prefs.edit { putString("appearance", mode.name) }
        _appearance.value = mode
    }

    fun setLanguage(language: AppLanguage) {
        prefs.edit { putString("language", language.name) }
        _language.value = language
        AppLocale.apply(language, appContext)
    }

    fun applyStoredLanguage() {
        AppLocale.apply(_language.value, appContext)
    }

    fun setCalendarStyle(style: CalendarStyle) {
        prefs.edit { putString("calendar_style", style.name) }
        _calendarStyle.value = style
    }

    fun setUseSubjectColors(v: Boolean) {
        prefs.edit { putBoolean(KEY_USE_SUBJECT_COLORS, v) }
        _useSubjectColors.value = v
    }

    fun setShowSchoolCalendar(v: Boolean) {
        prefs.edit { putBoolean(KEY_SHOW_SCHOOL_CALENDAR, v) }
        _showSchoolCalendar.value = v
    }

    fun setNotifEvents(v: Boolean) {
        prefs.edit { putBoolean("notif_events", v) }
        _notifEvents.value = v
    }

    fun setNotifMessages(v: Boolean) {
        prefs.edit { putBoolean("notif_messages", v) }
        _notifMessages.value = v
    }

    fun setNotifAssignments(v: Boolean) {
        prefs.edit { putBoolean("notif_assignments", v) }
        _notifAssignments.value = v
    }

    fun setDisableSignature(v: Boolean) {
        prefs.edit { putBoolean("disable_signature", v) }
        _disableSignature.value = v
    }

    /** True when the first-login onboarding overlay should be shown. */
    fun shouldShowOnboarding(): Boolean = !_onboardingCompleted.value

    fun markOnboardingCompleted() {
        prefs.edit { putBoolean(KEY_ONBOARDING_COMPLETED, true) }
        _onboardingCompleted.value = true
    }

    // ── Lesson mapping scope ──────────────────────────────────────────

    fun activateScope(studentId: String, schoolId: String) {
        currentStudentId = studentId
        currentSchoolId = schoolId
        val cached = cachedLessonMappingsByScope[scopeKey(studentId, schoolId)].orEmpty()
        applyActiveMappings(cached)
    }

    private fun applyActiveMappings(mappings: Map<String, ResolvedLessonMapping>) {
        _lessonMappings.value = mappings
        _derivedNames.value = mappings.mapValues { it.value.displayName }
        _derivedColors.value = mappings.mapValues {
            SubjectColorResolver.hueToArgb(it.value.displayColorHue)
        }
    }

    private fun mappingOrLocal(subjectCode: String): Pair<String, ResolvedLessonMapping>? {
        val key = SubjectMapper.canonicalKey(subjectCode)
            ?: SubjectMapper.normalizedHold(subjectCode).lowercase().takeIf { it.isNotEmpty() }
            ?: return null
        val existing = _lessonMappings.value[key]
        if (existing != null) return key to existing
        val defaultName = SubjectMapper.defaultName(key, fallback = key)
        val defaultHue = SubjectMapper.defaultColorHue(key)
        val created = ResolvedLessonMapping(
            mappingId = "local:$key",
            canonicalKey = key,
            defaultName = defaultName,
            defaultColorHue = defaultHue,
            defaultIcon = SubjectMapper.iconKey(key),
            displayName = defaultName,
            displayColorHue = defaultHue,
            displayIcon = SubjectMapper.iconKey(key),
        )
        return key to created
    }

    // ── Accessors (raw hold → resolved) ───────────────────────────────

    fun displayNameForSubject(rawHold: String, fallback: String = rawHold): String {
        val key = SubjectMapper.canonicalKey(rawHold)
        if (key != null) {
            _lessonMappings.value[key]?.displayName?.takeIf { it.isNotBlank() }?.let { return it }
            return SubjectMapper.defaultName(key, fallback = SubjectMapper.normalizedHold(rawHold).ifEmpty { fallback })
        }
        val normalized = SubjectMapper.normalizedHold(rawHold)
        return if (normalized.isNotEmpty()) normalized else fallback
    }

    /**
     * Name shown on a schedule brick: user alias, then W4's tooltip title, then the
     * catalogue name. Compact class ids (`1EA16CECOX`) are never shown as the title.
     */
    fun displayTitleForEvent(event: ScheduleEvent): String {
        if (SchoolCalendar.isSchoolCalendarEvent(event)) return event.title
        val key = event.team.ifBlank { event.title }
        customName(key)?.let { return it }
        val title = event.title.trim()
        if (title.isNotEmpty() && !W4ClassId.looksLike(title)) return title
        return displayNameForSubject(key, title.ifBlank { key })
    }

    fun colorHueForSubject(rawHold: String): Int {
        val key = SubjectMapper.canonicalKey(rawHold)
        if (key != null) {
            _lessonMappings.value[key]?.let { return it.displayColorHue }
            return SubjectMapper.defaultColorHue(key)
        }
        return SubjectMapper.colorHue(rawHold)
    }

    fun colorForSubject(rawHold: String): Long =
        SubjectColorResolver.hueToArgb(colorHueForSubject(rawHold))

    /**
     * Schedule block accent: subject hue when [useSubjectColors] is on,
     * otherwise status palette (blue / green / red) matching the web extension.
     */
    fun accentArgbFor(event: ScheduleEvent): Long {
        if (SchoolCalendar.isSchoolCalendarEvent(event)) {
            return SCHOOL_CALENDAR_ARGB
        }
        if (!_useSubjectColors.value) {
            return when (event.status) {
                EventStatus.NORMAL -> STATUS_NORMAL_ARGB
                EventStatus.CHANGED -> STATUS_CHANGED_ARGB
                EventStatus.CANCELLED -> STATUS_CANCELLED_ARGB
            }
        }
        val key = event.team.ifBlank { event.title }
        return colorForSubject(key)
    }

    fun iconKeyForSubject(rawHold: String): String = SubjectMapper.iconKey(rawHold)

    fun mappingFor(rawHoldOrCode: String): ResolvedLessonMapping? {
        val key = SubjectMapper.canonicalKey(rawHoldOrCode)
            ?: SubjectMapper.normalizedHold(rawHoldOrCode).lowercase()
        return _lessonMappings.value[key]
            ?: _lessonMappings.value[rawHoldOrCode]
    }

    fun customName(forCode: String): String? {
        val m = mappingFor(forCode) ?: return null
        return m.displayName.takeIf { it != m.defaultName }
    }

    fun hasCustomName(forCode: String): Boolean = customName(forCode) != null

    fun hasCustomColor(forCode: String): Boolean {
        val m = mappingFor(forCode) ?: return false
        return m.displayColorHue != m.defaultColorHue
    }

    fun hasAnyOverride(forCode: String): Boolean {
        val m = mappingFor(forCode) ?: return false
        return m.hasAnyOverride
    }

    fun defaultNameFor(code: String): String {
        mappingFor(code)?.let { return it.defaultName }
        return SubjectMapper.defaultName(code, fallback = code)
    }

    fun availableSubjects(extraHolds: Collection<String> = emptyList()): List<SubjectInfo> {
        val fromRemote = _lessonMappings.value.values.map {
            SubjectInfo(code = it.canonicalKey, name = it.displayName, mappingId = it.mappingId)
        }
        val merged = SubjectMapper.allSubjects(including = extraHolds + _observedHolds.value)
        val byCode = (fromRemote + merged).associateBy { it.code }.toMutableMap()
        // Prefer remote display names / mapping ids
        for (m in _lessonMappings.value.values) {
            byCode[m.canonicalKey] = SubjectInfo(
                code = m.canonicalKey,
                name = m.displayName,
                mappingId = m.mappingId,
            )
        }
        return byCode.values.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    fun noteObservedHolds(holds: Collection<String>) {
        val additions = holds.map { it.trim() }.filter { it.isNotEmpty() }
        if (additions.isEmpty()) return
        val next = _observedHolds.value.toMutableSet()
        if (!next.addAll(additions)) return
        _observedHolds.value = next
    }

    /** @deprecated Prefer [availableSubjects]. Kept for call-site compatibility during migration. */
    fun editableSubjects(extra: Collection<String> = emptyList()): List<String> =
        availableSubjects(extra).map { it.code }

    // ── Mutations ─────────────────────────────────────────────────────

    /**
     * Save name and/or color override for a subject (canonical key or raw hold).
     * - [displayName] null = leave name unchanged; blank/default = clear name override
     * - [colorHue] null = leave hue unchanged; default hue = clear color override
     */
    fun saveCustomization(
        subjectCode: String,
        displayName: String? = null,
        colorHue: Int? = null,
    ) {
        val (key, existing) = mappingOrLocal(subjectCode) ?: return

        val nextName = if (displayName == null) {
            existing.displayName
        } else {
            normalizedOverrideName(displayName, existing.defaultName) ?: existing.defaultName
        }
        val nextHue = if (colorHue == null) {
            existing.displayColorHue
        } else {
            val h = SubjectMapper.normalizeHue(colorHue)
            if (h == SubjectMapper.normalizeHue(existing.defaultColorHue)) {
                existing.defaultColorHue
            } else {
                h
            }
        }

        val next = existing.copy(
            displayName = nextName,
            displayColorHue = nextHue,
        )
        applyLocalMapping(key, next)
    }

    fun setSubjectColor(subject: String, colorArgb: Long) {
        val hue = SubjectColorResolver.argbToHue(colorArgb)
        saveCustomization(subject, displayName = null, colorHue = hue)
    }

    fun setSubjectName(subjectKey: String, displayName: String) {
        saveCustomization(subjectKey, displayName = displayName, colorHue = null)
    }

    fun setSubjectColorHue(subjectCode: String, hue: Int) {
        saveCustomization(subjectCode, displayName = null, colorHue = hue)
    }

    fun resetMapping(subjectCode: String) {
        val key = SubjectMapper.canonicalKey(subjectCode)
            ?: SubjectMapper.normalizedHold(subjectCode).lowercase()
        val existing = _lessonMappings.value[key] ?: return
        val next = existing.copy(
            displayName = existing.defaultName,
            displayColorHue = existing.defaultColorHue,
            displayIcon = existing.defaultIcon,
        )
        applyLocalMapping(key, next)
    }

    fun resetAllLessonMappings() {
        val overridden = _lessonMappings.value.keys.filter { hasAnyOverride(it) }
        for (key in overridden) {
            resetMapping(key)
        }
    }

    private fun applyLocalMapping(canonicalKey: String, mapping: ResolvedLessonMapping) {
        val next = _lessonMappings.value.toMutableMap()
        next[canonicalKey] = mapping
        applyActiveMappings(next)
        persistCurrentScopeMappings()
    }

    private fun persistCurrentScopeMappings() {
        val studentId = currentStudentId ?: return
        val schoolId = currentSchoolId ?: return
        cachedLessonMappingsByScope[scopeKey(studentId, schoolId)] = _lessonMappings.value
        saveLessonMappingCache()
    }

    private fun normalizedOverrideName(name: String?, defaultName: String): String? {
        if (name == null) return null
        val trimmed = SubjectMapper.normalizedHold(name)
        if (trimmed.isEmpty() || trimmed == defaultName) return null
        return trimmed
    }

    private fun scopeKey(studentId: String, schoolId: String): String = "$schoolId::$studentId"

    // ── Notification history ──────────────────────────────────────────

    fun appendNotificationHistory(entry: String) {
        val next = (listOf("${System.currentTimeMillis()}|$entry") + _notificationHistory.value).take(50)
        prefs.edit { putString("notif_history", next.joinToString("\n")) }
        _notificationHistory.value = next
    }

    fun clearNotificationHistory() {
        prefs.edit { remove("notif_history") }
        _notificationHistory.value = emptyList()
    }

    companion object {
        const val PRIVACY_POLICY_URL = "https://w4.jonathanb.dk/privatlivspolitik"

        private const val KEY_LESSON_CACHE = "lessonMappingCacheV2"
        private const val KEY_ONBOARDING_COMPLETED = "onboarding_completed"
        private const val KEY_USE_SUBJECT_COLORS = "use_subject_colors"
        private const val KEY_SHOW_SCHOOL_CALENDAR = "show_school_calendar"

        /** Status-mode schedule accents (blue / green / red). */
        private const val STATUS_NORMAL_ARGB = 0xFF3362E1L
        private const val STATUS_CHANGED_ARGB = 0xFF2E9E5BL
        private const val STATUS_CANCELLED_ARGB = 0xFFD32F2FL
        /** Public college Google Calendar overlay — distinct from subject hues. */
        private const val SCHOOL_CALENDAR_ARGB = 0xFF0B8043L

        /** Fallback palette (non-subject UI). Subject colors use hue→ARGB. */
        val DEFAULT_PALETTE = listOf(
            0xFF3362E1L,
            0xFF0B8043L,
            0xFFD50000L,
            0xFFF4511EL,
            0xFF8E24AAL,
            0xFF039BE5L,
            0xFF33B679L,
            0xFFE67C73L,
        )
    }

    private fun loadAppearance(): AppearanceMode =
        runCatching { AppearanceMode.valueOf(prefs.getString("appearance", null) ?: "SYSTEM") }
            .getOrDefault(AppearanceMode.SYSTEM)

    private fun loadLanguage(): AppLanguage =
        runCatching { AppLanguage.valueOf(prefs.getString("language", null) ?: "SYSTEM") }
            .getOrDefault(AppLanguage.SYSTEM)

    private fun loadCalendarStyle(): CalendarStyle =
        runCatching { CalendarStyle.valueOf(prefs.getString("calendar_style", null) ?: "PROFESSIONAL") }
            .getOrDefault(CalendarStyle.PROFESSIONAL)

    private fun loadNotificationHistory(): List<String> {
        val raw = prefs.getString("notif_history", null) ?: return emptyList()
        return raw.split('\n').filter { it.isNotBlank() }
    }

    private fun loadLessonMappingCache(): Map<String, Map<String, ResolvedLessonMapping>> {
        val raw = prefs.getString(KEY_LESSON_CACHE, null) ?: return emptyMap()
        return runCatching {
            json.decodeFromString<Map<String, Map<String, ResolvedLessonMapping>>>(raw)
        }.getOrElse {
            Timber.w(it, "Failed to decode lesson mapping cache")
            emptyMap()
        }
    }

    private fun saveLessonMappingCache() {
        runCatching {
            val encoded = json.encodeToString(cachedLessonMappingsByScope)
            prefs.edit { putString(KEY_LESSON_CACHE, encoded) }
        }.onFailure {
            Timber.w(it, "Failed to encode lesson mapping cache")
        }
    }
}
