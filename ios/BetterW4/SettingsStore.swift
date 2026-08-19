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

/// Manages user preferences, their persistence, and cache teardown.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let appGroupIdentifier = "group.dk.elliottf.betterw4"

    /// Subject mappings are scoped `"w4::<uwcId>"`; W4 is one school, so the namespace is fixed.
    static let scopeNamespace = "w4"

    private let userDefaults: UserDefaults?

    // MARK: - Keys
    private enum Keys {
        static let lessonMappingCache = "w4.settings.subjectMappings"
        static let notificationsEnabled = "notificationsEnabled"
        static let notifyAssessments = "w4.notify.assessments"
        static let notifyTimetableChanges = "w4.notify.timetableChanges"
        static let notifyTrips = "w4.notify.trips"
        static let calendarStyle = "calendarStyle"
        static let appearanceMode = "appearanceMode"
        static let useSubjectColors = "useSubjectColors"
        static let showSchoolCalendar = "showSchoolCalendar"
    }

    // MARK: - Published Properties
    @Published private(set) var lessonMappings: [String: SubjectMapper.ResolvedLessonMapping] = [:]
    @Published var calendarStyle: CalendarStyle = .professional
    @Published var appearanceMode: AppearanceMode = .system
    /// When true, timetable blocks use per-subject hues; when false, status blue/green/red.
    @Published var useSubjectColors: Bool = true
    /// When true, the public college Google Calendar is drawn on the timetable.
    @Published var showSchoolCalendar: Bool = SchoolCalendar.isEnabledByDefault

    /// Master switch. Every per-type toggle below is only honoured while this is on.
    @Published var notificationsEnabled: Bool = false
    @Published var notifyAssessments: Bool = true
    @Published var notifyTimetableChanges: Bool = true
    @Published var notifyTrips: Bool = true

    private var cachedLessonMappingsByScope: [String: [String: SubjectMapper.ResolvedLessonMapping]] = [:]
    private var currentStudentId: String?

    // MARK: - Initialization
    private init() {
        // The app-group suite has no entitlement, so it does not persist. Standard
        // defaults are what the background refresh reads.
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
        if let data = userDefaults?.data(forKey: Keys.lessonMappingCache),
           let cached = try? JSONDecoder().decode([String: [String: SubjectMapper.ResolvedLessonMapping]].self, from: data) {
            cachedLessonMappingsByScope = cached
        }

        notificationsEnabled = bool(Keys.notificationsEnabled, default: false)
        notifyAssessments = bool(Keys.notifyAssessments, default: true)
        notifyTimetableChanges = bool(Keys.notifyTimetableChanges, default: true)
        notifyTrips = bool(Keys.notifyTrips, default: true)

        if let raw = userDefaults?.string(forKey: Keys.calendarStyle),
           let style = CalendarStyle(rawValue: raw) {
            calendarStyle = style
        }

        if let raw = userDefaults?.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }

        useSubjectColors = bool(Keys.useSubjectColors, default: true)
        showSchoolCalendar = bool(Keys.showSchoolCalendar, default: SchoolCalendar.isEnabledByDefault)
    }

    /// `UserDefaults.bool` cannot tell "false" from "never set", so the default is applied here.
    private func bool(_ key: String, default fallback: Bool) -> Bool {
        guard let stored = userDefaults?.object(forKey: key) as? Bool else { return fallback }
        return stored
    }

    // MARK: - Saving
    private func saveLessonMappingCache() {
        guard let data = try? JSONEncoder().encode(cachedLessonMappingsByScope) else { return }
        userDefaults?.set(data, forKey: Keys.lessonMappingCache)
    }

    func saveNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        userDefaults?.set(enabled, forKey: Keys.notificationsEnabled)
    }

    func saveNotifyAssessments(_ enabled: Bool) {
        notifyAssessments = enabled
        userDefaults?.set(enabled, forKey: Keys.notifyAssessments)
    }

    func saveNotifyTimetableChanges(_ enabled: Bool) {
        notifyTimetableChanges = enabled
        userDefaults?.set(enabled, forKey: Keys.notifyTimetableChanges)
    }

    func saveNotifyTrips(_ enabled: Bool) {
        notifyTrips = enabled
        userDefaults?.set(enabled, forKey: Keys.notifyTrips)
    }

    func saveCalendarStyle(_ style: CalendarStyle) {
        calendarStyle = style
        userDefaults?.set(style.rawValue, forKey: Keys.calendarStyle)
    }

    func saveAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        userDefaults?.set(mode.rawValue, forKey: Keys.appearanceMode)
    }

    func saveUseSubjectColors(_ enabled: Bool) {
        useSubjectColors = enabled
        userDefaults?.set(enabled, forKey: Keys.useSubjectColors)
    }

    func saveShowSchoolCalendar(_ enabled: Bool) {
        showSchoolCalendar = enabled
        userDefaults?.set(enabled, forKey: Keys.showSchoolCalendar)
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

    /// WCAG relative luminance of this colour in sRGB, or 0 if it cannot be read.
    var relativeLuminance: CGFloat {
        guard let rgb = srgbComponents else { return 0 }
        func lin(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(rgb.r) + 0.7152 * lin(rgb.g) + 0.0722 * lin(rgb.b)
    }

    func contrastRatio(against background: Color) -> CGFloat {
        let l1 = relativeLuminance
        let l2 = background.relativeLuminance
        let light = max(l1, l2)
        let dark = min(l1, l2)
        return (light + 0.05) / (dark + 0.05)
    }

    /// Darken on light surfaces (or lighten on dark ones) so this colour is usable as
    /// text / icon. Fills should keep the original swatch from `lessonMappingHue`.
    func ensuringContrast(against background: Color, minRatio: CGFloat = 4.5) -> Color {
        if contrastRatio(against: background) >= minRatio { return self }
        guard var hsv = hsvComponents else { return self }
        let darken = background.relativeLuminance > 0.5
        if darken {
            hsv.s = min(hsv.s * 1.15, 0.88)
        }

        var lo: CGFloat
        var hi: CGFloat
        var best: Color
        if darken {
            lo = 0.18
            hi = hsv.v
            best = Color(hue: hsv.h, saturation: hsv.s, brightness: lo)
        } else {
            lo = hsv.v
            hi = 1
            best = Color(hue: hsv.h, saturation: hsv.s, brightness: hi)
        }
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            let candidate = Color(hue: hsv.h, saturation: hsv.s, brightness: mid)
            if candidate.contrastRatio(against: background) >= minRatio {
                best = candidate
                if darken { lo = mid } else { hi = mid }
            } else {
                if darken { hi = mid } else { lo = mid }
            }
        }
        return best
    }

    /// Subject/status accent that stays readable as text on the current surface.
    func readableAccent(colorScheme: ColorScheme) -> Color {
        ensuringContrast(
            against: colorScheme == .dark
                ? Color(red: 0.07, green: 0.07, blue: 0.07)
                : Color(red: 1, green: 1, blue: 1)
        )
    }

    /// Mix [amount] of [accent] into this surface. ~0.18 is a quiet wash that still reads as colour.
    func tinted(with accent: Color, amount: CGFloat = 0.18) -> Color {
        let base = UIColor(self)
        let tint = UIColor(accent)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        tint.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let a = min(max(amount, 0), 1)
        return Color(
            red: Double(r1 + (r2 - r1) * a),
            green: Double(g1 + (g2 - g1) * a),
            blue: Double(b1 + (b2 - b1) * a),
            opacity: 1
        )
    }

    /// Foreground that sits on this colour (white on dark jewel tones, near-black on yellows).
    var onColor: Color {
        relativeLuminance > 0.22 ? Color.black.opacity(0.88) : Color.white
    }

    private var srgbComponents: (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b)
        }
        guard let converted = ui.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ), let comps = converted.components, comps.count >= 3 else {
            return nil
        }
        return (comps[0], comps[1], comps[2])
    }

    private var hsvComponents: (h: CGFloat, s: CGFloat, v: CGFloat)? {
        guard let rgb = srgbComponents else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            .getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (h, s, v)
    }
}
