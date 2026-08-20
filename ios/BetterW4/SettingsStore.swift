//
//  SettingsStore.swift
//  BetterW4
//
//  Every user preference in the app, and the one place that clears cached W4 data.
//
//  All of it is device-local (`UserDefaults` in the app group). Subject renames and colours are
//  scoped per student — `"w4::<uwcId>"` — so two accounts on one device cannot overwrite each
//  other. W4 is a single school, so there is no school id in any scope key (features.md §6).
//

import Combine
import SwiftUI
import UIKit

/// Calendar visual style preference.
enum CalendarStyle: String, CaseIterable, Identifiable {
    case professional
    case standard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .professional: return "Professional"
        case .standard: return "Standard"
        }
    }

    var description: String {
        switch self {
        case .professional:
            return "Minimal, compact layout that puts the content first"
        case .standard:
            return "Colourful cards with icons and a relaxed style"
        }
    }
}

/// App appearance vs the system setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// Value for `.preferredColorScheme`; `nil` follows the device.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// How long before a lesson its reminder fires.
enum LessonReminderLead: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }

    var displayName: String { "\(rawValue) min" }
}

/// Manages user preferences, their persistence, and cache teardown.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Subject mappings are scoped `"w4::<uwcId>"`; W4 is one school, so the namespace is fixed.
    static let scopeNamespace = "w4"

    private let userDefaults: UserDefaults

    // MARK: - Keys
    private enum Keys {
        static let lessonMappingCache = "w4.settings.subjectMappings"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyAssessments = "w4.notify.assessments"
        static let notifyLessonReminder = "w4.notify.lessonReminder"
        static let lessonReminderMinutes = "w4.notify.lessonReminderMinutes"
        static let calendarStyle = "calendarStyle"
        static let appearanceMode = "appearanceMode"
        static let useSubjectColors = "useSubjectColors"
    }

    // MARK: - Published Properties
    @Published private(set) var lessonMappings: [String: SubjectMapper.ResolvedLessonMapping] = [:]
    @Published var calendarStyle: CalendarStyle = .professional
    @Published var appearanceMode: AppearanceMode = .system
    /// When true, timetable blocks use per-subject hues; when false, status blue/green/red.
    @Published var useSubjectColors: Bool = true

    /// Master switch. Every per-type toggle below is only honoured while this is on.
    ///
    /// There used to be two more — `notifyNewMail` and `notifyTimetableChanges`. Both were
    /// removed rather than fixed: answering either question means fetching W4 on a schedule and
    /// diffing the result, which needs background refresh this app does not implement. They were
    /// write-only switches over nothing. What survives is what `NotificationPlanner` can actually
    /// schedule ahead of time from data already on disk.
    @Published var notificationsEnabled: Bool = false
    @Published var notifyAssessments: Bool = true
    @Published var notifyLessonReminder: Bool = false
    @Published var lessonReminderMinutes: LessonReminderLead = .ten

    private var cachedLessonMappingsByScope: [String: [String: SubjectMapper.ResolvedLessonMapping]] = [:]
    private var currentStudentId: String?

    // MARK: - Initialization
    private init() {
        // `UserDefaults.standard`, not an app-group suite. This used to open
        // `UserDefaults(suiteName: "group.dk.elliottf.betterw4")` against an entitlements file
        // that declares no app group, so the suite was always nil and every preference write in
        // this file was silently discarded on a real device — theme, calendar style, subject
        // colours and the notification toggles all forgot themselves on relaunch. Nothing shares
        // these preferences with an extension, so the app's own defaults are the right home for
        // them. Adding the entitlement instead would also change the privacy manifest's
        // UserDefaults reason away from CA92.1.
        self.userDefaults = .standard
        loadSettings()

        SubjectMapper.mappingProvider = { [weak self] canonicalKey in
            self?.lessonMappings[canonicalKey]
        }
        SubjectMapper.subjectInfoProvider = { [weak self] in
            // Start from the built-in subject catalogue and overlay the local renames, so the
            // subject list is never empty just because nothing has been customised yet.
            var subjectsByCode = Dictionary(
                uniqueKeysWithValues: SubjectMapper.knownSubjects.map { ($0.code, $0) }
            )

            let localMappings = self?.lessonMappings ?? [:]
            for mapping in localMappings.values {
                subjectsByCode[mapping.canonicalKey] = SubjectMapper.SubjectInfo(
                    code: mapping.canonicalKey,
                    name: mapping.displayName,
                    mappingId: mapping.mappingId
                )
            }

            return subjectsByCode.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    // MARK: - Loading
    private func loadSettings() {
        if let data = userDefaults.data(forKey: Keys.lessonMappingCache),
           let cached = try? JSONDecoder().decode([String: [String: SubjectMapper.ResolvedLessonMapping]].self, from: data) {
            cachedLessonMappingsByScope = cached
        }

        notificationsEnabled = bool(Keys.notificationsEnabled, default: false)
        notifyAssessments = bool(Keys.notifyAssessments, default: true)
        notifyLessonReminder = bool(Keys.notifyLessonReminder, default: false)

        if let raw = userDefaults.object(forKey: Keys.lessonReminderMinutes) as? Int,
           let lead = LessonReminderLead(rawValue: raw) {
            lessonReminderMinutes = lead
        }

        if let raw = userDefaults.string(forKey: Keys.calendarStyle),
           let style = CalendarStyle(rawValue: raw) {
            calendarStyle = style
        }

        if let raw = userDefaults.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }

        useSubjectColors = bool(Keys.useSubjectColors, default: true)
    }

    /// `UserDefaults.bool` cannot tell "false" from "never set", so the default is applied here.
    private func bool(_ key: String, default fallback: Bool) -> Bool {
        guard let stored = userDefaults.object(forKey: key) as? Bool else { return fallback }
        return stored
    }

    // MARK: - Saving
    private func saveLessonMappingCache() {
        guard let data = try? JSONEncoder().encode(cachedLessonMappingsByScope) else { return }
        userDefaults.set(data, forKey: Keys.lessonMappingCache)
    }

    func saveNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        userDefaults.set(enabled, forKey: Keys.notificationsEnabled)
    }

    func saveNotifyAssessments(_ enabled: Bool) {
        notifyAssessments = enabled
        userDefaults.set(enabled, forKey: Keys.notifyAssessments)
    }

    func saveNotifyLessonReminder(_ enabled: Bool) {
        notifyLessonReminder = enabled
        userDefaults.set(enabled, forKey: Keys.notifyLessonReminder)
    }

    func saveLessonReminderMinutes(_ lead: LessonReminderLead) {
        lessonReminderMinutes = lead
        userDefaults.set(lead.rawValue, forKey: Keys.lessonReminderMinutes)
    }

    func saveCalendarStyle(_ style: CalendarStyle) {
        calendarStyle = style
        userDefaults.set(style.rawValue, forKey: Keys.calendarStyle)
    }

    func saveAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        userDefaults.set(mode.rawValue, forKey: Keys.appearanceMode)
    }

    func saveUseSubjectColors(_ enabled: Bool) {
        useSubjectColors = enabled
        userDefaults.set(enabled, forKey: Keys.useSubjectColors)
    }

    /// Timetable block accent: the subject hue when enabled, otherwise the status palette.
    func accentColor(for event: ScheduleEvent) -> Color {
        if useSubjectColors {
            return SubjectMapper.color(for: event.title)
        }
        switch event.status {
        case .normal:
            return Color(red: 51 / 255, green: 98 / 255, blue: 225 / 255) // #3362E1
        case .changed, .moved:
            return Color(red: 46 / 255, green: 158 / 255, blue: 91 / 255) // #2E9E5B
        case .cancelled:
            return Color(red: 211 / 255, green: 47 / 255, blue: 47 / 255) // #D32F2F
        }
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.preferredColorScheme
    }

    // MARK: - Subject Mapping Scope

    /// Activates the local settings scope for a student.
    ///
    /// W4 is one college, so the scope is the uwc id alone — there is no second half to the key.
    func activateScope(studentId: String) {
        currentStudentId = studentId
        lessonMappings = cachedLessonMappingsByScope[Self.scopeKey(uwcId: studentId)] ?? [:]
    }

    // MARK: - Subject Mapping Accessors

    func displayName(for subjectCode: String) -> String? {
        mapping(for: subjectCode)?.displayName
    }

    func defaultName(for subjectCode: String) -> String? {
        if let mapping = mapping(for: subjectCode) {
            return mapping.defaultName
        }
        return SubjectMapper.defaultName(for: subjectCode, fallback: nil)
    }

    /// The effective display colour for the canonical mapping, if one exists.
    func color(for subjectCode: String) -> Color? {
        mapping(for: subjectCode).map { Color.lessonMappingHue($0.displayColorHue) }
    }

    func defaultColor(for subjectCode: String) -> Color? {
        if let mapping = mapping(for: subjectCode) {
            return Color.lessonMappingHue(mapping.defaultColorHue)
        }
        return SubjectMapper.defaultColor(for: subjectCode)
    }

    /// Only a user override, never the effective display name.
    func customName(for subjectCode: String) -> String? {
        guard let mapping = mapping(for: subjectCode), mapping.displayName != mapping.defaultName else {
            return nil
        }
        return mapping.displayName
    }

    func hasCustomName(for subjectCode: String) -> Bool {
        customName(for: subjectCode) != nil
    }

    func hasCustomColor(for subjectCode: String) -> Bool {
        guard let mapping = mapping(for: subjectCode) else {
            return false
        }
        return mapping.displayColorHue != mapping.defaultColorHue
    }

    func hasAnyOverride(for subjectCode: String) -> Bool {
        guard let mapping = mapping(for: subjectCode) else {
            return false
        }
        return mapping.displayName != mapping.defaultName
            || mapping.displayColorHue != mapping.defaultColorHue
            || mapping.displayIcon != mapping.defaultIcon
    }

    // MARK: - Subject Mapping Mutations

    /// Stores a rename and/or colour override locally. A subject with no mapping yet gets one
    /// synthesised from the built-in defaults — there is no remote mapping table.
    func saveCustomization(name: String?, color: Color?, for subjectCode: String) {
        guard let canonicalKey = canonicalKey(for: subjectCode) else {
            return
        }

        var mapping: SubjectMapper.ResolvedLessonMapping
        if let existing = lessonMappings[canonicalKey] {
            mapping = existing
        } else {
            mapping = makeLocalMapping(canonicalKey: canonicalKey)
        }

        let overrideName = normalizedOverrideName(name, defaultName: mapping.defaultName)
        let overrideColorHue = normalizedOverrideHue(color, defaultHue: mapping.defaultColorHue)

        mapping.displayName = overrideName ?? mapping.defaultName
        mapping.displayColorHue = overrideColorHue ?? mapping.defaultColorHue

        applyLocalMapping(mapping, for: canonicalKey)
    }

    func resetMapping(for subjectCode: String) {
        guard
            let canonicalKey = canonicalKey(for: subjectCode),
            var mapping = lessonMappings[canonicalKey]
        else {
            return
        }

        mapping.displayName = mapping.defaultName
        mapping.displayColorHue = mapping.defaultColorHue
        mapping.displayIcon = mapping.defaultIcon

        applyLocalMapping(mapping, for: canonicalKey)
    }

    func resetAllLessonMappings() {
        let overriddenKeys = lessonMappings.keys.filter(hasAnyOverride(for:))
        for canonicalKey in overriddenKeys {
            resetMapping(for: canonicalKey)
        }
    }

    // MARK: - Cache Management

    /// Clears every cached W4 page and every derived store: portraits, the URL cache, the page
    /// cache, the timetable, assessments, mail, attachments, the directory and the page chrome.
    ///
    /// Deliberately **not** cleared: Keychain credentials, the session cookie, and preferences
    /// (theme, calendar style, subject colours, notification toggles). Clearing the cache is not
    /// signing out — features.md §3 rule 10.
    ///
    /// Posts `.betterW4CachesDidClear` when it finishes so open screens reload.
    func clearAllCaches() {
        Task { @MainActor in
            await W4ImageLoader.shared.clearCache()
            await PublicProfileImageLoader.shared.clearCache()
            URLCache.shared.removeAllCachedResponses()

            await W4PageCache.shared.clear()
            await MessageCacheManager.clearCache()
            await AttachmentCache.shared.clear()
            await AssessmentStore.shared.clear(uwcId: nil)
            await TimetableRepository.shared.clearStoredLessons()
            await DirectoryStore.shared.clearAllDirectoryDataAsync()
            await ChromeObserver.shared.reset()

            NotificationCenter.default.post(name: .betterW4CachesDidClear, object: nil)

            print("🗑️ Cleared every cached W4 page and derived store")
        }
    }

    /// Bytes currently held by the caches Settings reports on. Best effort — a cache that cannot
    /// measure itself contributes zero rather than failing the row.
    static func cacheSizeInBytes() async -> Int64 {
        async let pages = W4PageCache.shared.sizeInBytes()
        async let mail = MessageCacheManager.mailCacheSizeInBytes()
        async let attachments = AttachmentCache.shared.sizeInBytes()
        return await (pages + mail + attachments)
    }

    // MARK: - Available Subjects

    var availableSubjects: [(code: String, name: String, defaultColor: Color)] {
        SubjectMapper.allSubjects.map { subject in
            (
                code: subject.code,
                name: subject.name,
                defaultColor: defaultColor(for: subject.code) ?? SubjectMapper.defaultColor(for: subject.code)
            )
        }
    }

    // MARK: - Helpers

    private func mapping(for subjectCode: String) -> SubjectMapper.ResolvedLessonMapping? {
        guard let canonicalKey = canonicalKey(for: subjectCode) else {
            return nil
        }
        return lessonMappings[canonicalKey]
    }

    /// Lower-cases with the POSIX-ish `en_GB` locale W4 itself renders in; never a Danish locale,
    /// whose dotless-i rules do not apply to IB subject names.
    private func canonicalKey(for subjectCode: String) -> String? {
        let normalized = SubjectMapper.normalizedHold(subjectCode)
        if let canonical = SubjectMapper.canonicalKey(for: normalized) {
            return canonical
        }

        let lowered = normalized.lowercased(with: Locale(identifier: "en_GB"))
        return lowered.isEmpty ? nil : lowered
    }

    /// Builds a mapping for a subject that has never been customised on this device.
    /// The identifier is purely local — there is no remote mapping table.
    private func makeLocalMapping(canonicalKey: String) -> SubjectMapper.ResolvedLessonMapping {
        let resolvedDefaultName = SubjectMapper.defaultName(for: canonicalKey, fallback: canonicalKey)
        let defaultHue = SubjectMapper.defaultColorHue(for: canonicalKey)
        let defaultIcon = SubjectMapper.iconName(for: canonicalKey)

        return SubjectMapper.ResolvedLessonMapping(
            mappingId: UUID(),
            canonicalKey: canonicalKey,
            defaultName: resolvedDefaultName,
            defaultColorHue: defaultHue,
            defaultIcon: defaultIcon,
            displayName: resolvedDefaultName,
            displayColorHue: defaultHue,
            displayIcon: defaultIcon
        )
    }

    private func normalizedOverrideName(_ name: String?, defaultName: String) -> String? {
        guard let name else { return nil }
        let trimmed = SubjectMapper.normalizedHold(name)
        guard !trimmed.isEmpty, trimmed != defaultName else {
            return nil
        }
        return trimmed
    }

    private func normalizedOverrideHue(_ color: Color?, defaultHue: Int) -> Int? {
        guard let color, let hue = color.lessonMappingHueValue() else {
            return nil
        }
        return hue == normalizedHue(defaultHue) ? nil : hue
    }

    private func applyLocalMapping(_ mapping: SubjectMapper.ResolvedLessonMapping, for canonicalKey: String) {
        lessonMappings[canonicalKey] = mapping
        persistCurrentScopeMappings()
    }

    private func persistCurrentScopeMappings() {
        guard let studentId = currentStudentId else { return }
        cachedLessonMappingsByScope[Self.scopeKey(uwcId: studentId)] = lessonMappings
        saveLessonMappingCache()
    }

    /// `"w4::nc26abcd"` — features.md §6.
    static func scopeKey(uwcId: String) -> String {
        "\(scopeNamespace)::\(uwcId)"
    }

    private func normalizedHue(_ hue: Int) -> Int {
        ((hue % 360) + 360) % 360
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted after `SettingsStore.clearAllCaches()` finishes. Open screens reload on it.
    static let betterW4CachesDidClear = Notification.Name("dk.elliottf.betterw4.cachesDidClear")
}

// MARK: - Color Extensions

extension Color {
    /// Renders a subject-mapping hue (0–359) as the app's subject colour.
    static func lessonMappingHue(_ hue: Int) -> Color {
        let normalizedHue = Double(((hue % 360) + 360) % 360) / 360.0
        return Color(hue: normalizedHue, saturation: 0.72, brightness: 0.88)
    }

    func lessonMappingHueValue() -> Int? {
        let uiColor = UIColor(self)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }

        return Int(round(hue * 359.0)) % 360
    }
}
