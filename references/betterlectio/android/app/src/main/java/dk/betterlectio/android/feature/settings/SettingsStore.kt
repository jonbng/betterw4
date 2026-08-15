package dk.betterlectio.android.feature.settings

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.core.i18n.AppLocale
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.feature.schedule.EventStatus
import dk.betterlectio.android.feature.schedule.ScheduleEvent
import dk.betterlectio.android.feature.supabase.SupabaseSubjectMapping
import dk.betterlectio.android.feature.supabase.SupabaseSubjectService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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
 * Lesson mappings are scoped by student+school, synced from
 * `get_student_lesson_mappings_v2`, and resolved through [SubjectMapper].
 */
@Singleton
class SettingsStore @Inject constructor(
    @ApplicationContext context: Context,
    private val supabaseSubjects: SupabaseSubjectService,
) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("bl_settings", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
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

    private val _notifEvents = MutableStateFlow(prefs.getBoolean("notif_events", true))
    val notifEvents: StateFlow<Boolean> = _notifEvents.asStateFlow()

    private val _notifMessages = MutableStateFlow(prefs.getBoolean("notif_messages", true))
    val notifMessages: StateFlow<Boolean> = _notifMessages.asStateFlow()

    private val _notifAssignments = MutableStateFlow(prefs.getBoolean("notif_assignments", true))
    val notifAssignments: StateFlow<Boolean> = _notifAssignments.asStateFlow()

    /** When true, never append the BetterLectio signature on send/reply. */
    private val _disableSignature = MutableStateFlow(prefs.getBoolean("disable_signature", false))
    val disableSignature: StateFlow<Boolean> = _disableSignature.asStateFlow()

    private val _extensionInviteDismissed =
        MutableStateFlow(prefs.getBoolean(KEY_EXTENSION_INVITE_DISMISSED, false))
    val extensionInviteDismissed: StateFlow<Boolean> = _extensionInviteDismissed.asStateFlow()

    private val _onboardingCompleted =
        MutableStateFlow(prefs.getBoolean(KEY_ONBOARDING_COMPLETED, false))
    val onboardingCompleted: StateFlow<Boolean> = _onboardingCompleted.asStateFlow()

    private val _lessonMappings = MutableStateFlow<Map<String, ResolvedLessonMapping>>(emptyMap())
    val lessonMappings: StateFlow<Map<String, ResolvedLessonMapping>> = _lessonMappings.asStateFlow()

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

    /**
     * Counts this process as one authenticated launch (at most once per process).
     * Returns true when the proactive extension invite should be shown.
     */
    fun recordAuthenticatedLaunch(): Boolean {
        if (!launchRecordedThisProcess) {
            launchRecordedThisProcess = true
            val next = prefs.getInt(KEY_EXTENSION_INVITE_LAUNCH_COUNT, 0) + 1
            prefs.edit { putInt(KEY_EXTENSION_INVITE_LAUNCH_COUNT, next) }
        }
        return shouldShowProactiveExtensionInvite()
    }

    fun shouldShowProactiveExtensionInvite(): Boolean {
        if (_extensionInviteDismissed.value) return false
        return prefs.getInt(KEY_EXTENSION_INVITE_LAUNCH_COUNT, 0) >= EXTENSION_INVITE_LAUNCH_THRESHOLD
    }

    fun dismissExtensionInvite() {
        prefs.edit { putBoolean(KEY_EXTENSION_INVITE_DISMISSED, true) }
        _extensionInviteDismissed.value = true
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

    /**
     * Pull remote lesson mappings and replace the active scope cache
     * (iOS: SettingsStore.syncWithSupabase).
     */
    fun syncSubjectsFromSupabase(student: Student) {
        if (student.isDemo) return
        val studentId = student.studentId
        val schoolId = student.gymId.toString()
        activateScope(studentId, schoolId)
        scope.launch {
            val mappings = supabaseSubjects.fetchMappings(studentId, schoolId)
            if (mappings.isEmpty()) {
                Timber.i("SettingsStore: no remote lesson mappings (or fetch failed)")
                return@launch
            }
            applyRemoteMappings(mappings, studentId, schoolId)
            Timber.i("SettingsStore: synced %d lesson mappings from Supabase", mappings.size)
        }
    }

    /** Suspend variant for settings UI that needs a completion signal. */
    suspend fun syncSubjectsFromSupabaseNow(student: Student): Int {
        if (student.isDemo) return 0
        val studentId = student.studentId
        val schoolId = student.gymId.toString()
        activateScope(studentId, schoolId)
        val mappings = supabaseSubjects.fetchMappings(studentId, schoolId)
        if (mappings.isEmpty()) return 0
        applyRemoteMappings(mappings, studentId, schoolId)
        return mappings.size
    }

    private fun applyRemoteMappings(
        mappings: List<SupabaseSubjectMapping>,
        studentId: String,
        schoolId: String,
    ) {
        val active = mappings
            .filter { it.deletedAt == null }
            .associate { m ->
                m.canonicalKey to ResolvedLessonMapping(
                    mappingId = m.mappingId,
                    canonicalKey = m.canonicalKey,
                    defaultName = m.defaultName,
                    defaultColorHue = m.defaultColorHue,
                    defaultIcon = m.icon,
                    displayName = m.displayName,
                    displayColorHue = m.displayColorHue,
                    displayIcon = m.displayIcon,
                )
            }
        currentStudentId = studentId
        currentSchoolId = schoolId
        cachedLessonMappingsByScope[scopeKey(studentId, schoolId)] = active
        saveLessonMappingCache()
        applyActiveMappings(active)
    }

    private fun applyActiveMappings(mappings: Map<String, ResolvedLessonMapping>) {
        _lessonMappings.value = mappings
        _derivedNames.value = mappings.mapValues { it.value.displayName }
        _derivedColors.value = mappings.mapValues {
            SupabaseSubjectService.hueToArgb(it.value.displayColorHue)
        }
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

    fun colorHueForSubject(rawHold: String): Int {
        val key = SubjectMapper.canonicalKey(rawHold)
        if (key != null) {
            _lessonMappings.value[key]?.let { return it.displayColorHue }
            return SubjectMapper.defaultColorHue(key)
        }
        return SubjectMapper.colorHue(rawHold)
    }

    fun colorForSubject(rawHold: String): Long =
        SupabaseSubjectService.hueToArgb(colorHueForSubject(rawHold))

    /**
     * Schedule block accent: subject hue when [useSubjectColors] is on,
     * otherwise status palette (blue / green / red) matching the web extension.
     */
    fun accentArgbFor(event: ScheduleEvent): Long {
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
        val merged = SubjectMapper.allSubjects(including = extraHolds)
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
        val key = SubjectMapper.canonicalKey(subjectCode)
            ?: SubjectMapper.normalizedHold(subjectCode).lowercase()
        val existing = _lessonMappings.value[key] ?: return

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

        val overrideName = nextName.takeIf { it != existing.defaultName }
        val overrideHue = nextHue.takeIf {
            SubjectMapper.normalizeHue(it) != SubjectMapper.normalizeHue(existing.defaultColorHue)
        }

        if (overrideName == null && overrideHue == null && !next.hasIconOverride) {
            pushMappingReset(next)
        } else {
            pushMappingUpdate(
                mapping = next,
                overrideName = overrideName,
                overrideColorHue = overrideHue,
                overrideIcon = null,
            )
        }
    }

    fun setSubjectColor(subject: String, colorArgb: Long) {
        val hue = SupabaseSubjectService.argbToHue(colorArgb)
        val key = SubjectMapper.canonicalKey(subject)
            ?: SubjectMapper.normalizedHold(subject).lowercase()
        val existing = _lessonMappings.value[key]
        if (existing != null) {
            saveCustomization(key, displayName = null, colorHue = hue)
        } else {
            // Local-only until school mapping exists — still surface via derived color
            // by synthesizing a temporary mapping without remote id (no push).
            Timber.d("setSubjectColor: no mapping for %s — ignored until remote row exists", subject)
        }
    }

    fun setSubjectName(subjectKey: String, displayName: String) {
        val key = SubjectMapper.canonicalKey(subjectKey)
            ?: SubjectMapper.normalizedHold(subjectKey).lowercase()
        if (_lessonMappings.value[key] != null) {
            saveCustomization(key, displayName = displayName, colorHue = null)
        } else {
            Timber.d("setSubjectName: no mapping for %s — ignored until remote row exists", subjectKey)
        }
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
        pushMappingReset(next)
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

    private fun pushMappingUpdate(
        mapping: ResolvedLessonMapping,
        overrideName: String?,
        overrideColorHue: Int?,
        overrideIcon: String?,
    ) {
        val studentId = currentStudentId ?: return
        val schoolId = currentSchoolId ?: return
        scope.launch {
            try {
                if (overrideName == null && overrideColorHue == null && overrideIcon == null) {
                    supabaseSubjects.resetMappingOverride(studentId, schoolId, mapping.mappingId)
                } else {
                    supabaseSubjects.upsertMappingOverride(
                        studentId = studentId,
                        schoolId = schoolId,
                        mappingId = mapping.mappingId,
                        displayName = overrideName,
                        colorHue = overrideColorHue,
                        icon = overrideIcon,
                    )
                }
            } catch (e: Exception) {
                Timber.w(e, "Failed to write lesson mapping override")
                val gym = schoolId.toIntOrNull()
                if (gym != null) {
                    syncSubjectsFromSupabase(
                        Student(studentId = studentId, gymId = gym),
                    )
                }
            }
        }
    }

    private fun pushMappingReset(mapping: ResolvedLessonMapping) {
        val studentId = currentStudentId ?: return
        val schoolId = currentSchoolId ?: return
        scope.launch {
            try {
                supabaseSubjects.resetMappingOverride(studentId, schoolId, mapping.mappingId)
            } catch (e: Exception) {
                Timber.w(e, "Failed to reset lesson mapping override")
            }
        }
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
        const val PRIVACY_POLICY_URL = "https://betterlectio.dk/privatlivspolitik"
        const val DOWNLOAD_URL = "https://betterlectio.dk/download"
        /** Host+path shown in UI (no scheme). */
        const val DOWNLOAD_URL_DISPLAY = "betterlectio.dk/download"

        private const val KEY_LESSON_CACHE = "lessonMappingCacheV2"
        private const val KEY_EXTENSION_INVITE_LAUNCH_COUNT = "extension_invite_launch_count"
        private const val KEY_EXTENSION_INVITE_DISMISSED = "extension_invite_dismissed"
        private const val KEY_ONBOARDING_COMPLETED = "onboarding_completed"
        private const val KEY_USE_SUBJECT_COLORS = "use_subject_colors"
        private const val EXTENSION_INVITE_LAUNCH_THRESHOLD = 4

        /** Status-mode schedule accents (web extension blue / green / red). */
        private const val STATUS_NORMAL_ARGB = 0xFF3362E1L
        private const val STATUS_CHANGED_ARGB = 0xFF2E9E5BL
        private const val STATUS_CANCELLED_ARGB = 0xFFD32F2FL

        @Volatile
        private var launchRecordedThisProcess = false

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
