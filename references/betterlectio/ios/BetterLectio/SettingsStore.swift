//
//  SettingsStore.swift
//  BetterLectio
//
//  Created by Kilo Code on 04/03/2026.
//

import SwiftUI
import Combine
import UIKit

/// Calendar visual style preference
enum CalendarStyle: String, CaseIterable, Identifiable {
    case professional = "professional"
    case standard = "standard"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .professional: return "Professionel"
        case .standard: return "Standard"
        }
    }

    var description: String {
        switch self {
        case .professional:
            return "Minimalistisk, kompakt design med fokus på indhold"
        case .standard:
            return "Farverige kort med ikoner og afslappet stil"
        }
    }
}

/// App appearance vs system setting
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Lys"
        case .dark: return "Mørk"
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

/// Manages user preferences and settings persistence
class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let appGroupIdentifier = "group.dk.elliottf.betterlectio"

    private let userDefaults: UserDefaults?

    // MARK: - Keys
    private enum Keys {
        static let lessonMappingCache = "lessonMappingCacheV2"
        static let liveActivityVariant = "liveActivityVariant"
        static let notificationsEnabled = "notificationsEnabled"
        static let calendarStyle = "calendarStyle"
        static let appearanceMode = "appearanceMode"
        static let messageSignatureEnabled = "messageSignatureEnabled"
        static let useSubjectColors = "useSubjectColors"
    }

    // MARK: - Published Properties
    @Published private(set) var lessonMappings: [String: SubjectMapper.ResolvedLessonMapping] = [:]
    @Published var liveActivityVariant: LiveActivityVariant = .standard
    @Published var notificationsEnabled: Bool = false
    @Published var calendarStyle: CalendarStyle = .professional
    @Published var appearanceMode: AppearanceMode = .system
    @Published var messageSignatureEnabled: Bool = true
    /// When true, schedule blocks use per-subject hues; when false, status blue/green/red.
    @Published var useSubjectColors: Bool = true

    private var cachedLessonMappingsByScope: [String: [String: SubjectMapper.ResolvedLessonMapping]] = [:]
    private var currentStudentId: String?
    private var currentSchoolId: String?

    // MARK: - Initialization
    private init() {
        self.userDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        loadSettings()

        SubjectMapper.mappingProvider = { [weak self] canonicalKey in
            self?.lessonMappings[canonicalKey]
        }
        SubjectMapper.subjectInfoProvider = { [weak self] in
            self?.lessonMappings.values
                .map { mapping in
                    SubjectMapper.SubjectInfo(
                        code: mapping.canonicalKey,
                        name: mapping.displayName,
                        mappingId: mapping.mappingId
                    )
                } ?? []
        }
    }

    // MARK: - Loading
    private func loadSettings() {
        if let data = userDefaults?.data(forKey: Keys.lessonMappingCache),
           let cached = try? JSONDecoder().decode([String: [String: SubjectMapper.ResolvedLessonMapping]].self, from: data) {
            cachedLessonMappingsByScope = cached
        }

        if let raw = userDefaults?.string(forKey: Keys.liveActivityVariant),
           let variant = LiveActivityVariant(rawValue: raw) {
            liveActivityVariant = variant
        }

        notificationsEnabled = userDefaults?.bool(forKey: Keys.notificationsEnabled) ?? false

        if let raw = userDefaults?.string(forKey: Keys.calendarStyle),
           let style = CalendarStyle(rawValue: raw) {
            calendarStyle = style
        }

        if let raw = userDefaults?.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        }

        messageSignatureEnabled = userDefaults?.object(forKey: Keys.messageSignatureEnabled) as? Bool ?? true

        if userDefaults?.object(forKey: Keys.useSubjectColors) != nil {
            useSubjectColors = userDefaults?.bool(forKey: Keys.useSubjectColors) ?? true
        } else {
            useSubjectColors = true
        }
    }

    // MARK: - Saving
    private func saveLessonMappingCache() {
        guard let data = try? JSONEncoder().encode(cachedLessonMappingsByScope) else { return }
        userDefaults?.set(data, forKey: Keys.lessonMappingCache)
    }

    func saveLiveActivityVariant(_ variant: LiveActivityVariant) {
        liveActivityVariant = variant
        userDefaults?.set(variant.rawValue, forKey: Keys.liveActivityVariant)
    }

    func saveNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        userDefaults?.set(enabled, forKey: Keys.notificationsEnabled)
    }

    func saveCalendarStyle(_ style: CalendarStyle) {
        calendarStyle = style
        userDefaults?.set(style.rawValue, forKey: Keys.calendarStyle)
    }

    func saveAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        userDefaults?.set(mode.rawValue, forKey: Keys.appearanceMode)
    }

    func saveMessageSignatureEnabled(_ enabled: Bool) {
        messageSignatureEnabled = enabled
        userDefaults?.set(enabled, forKey: Keys.messageSignatureEnabled)
    }

    func saveUseSubjectColors(_ enabled: Bool) {
        useSubjectColors = enabled
        userDefaults?.set(enabled, forKey: Keys.useSubjectColors)
    }

    /// Schedule block accent: subject hue when enabled, otherwise status blue/green/red.
    func accentColor(for event: ScheduleEvent) -> Color {
        if useSubjectColors {
            return SubjectMapper.color(for: event.title)
        }
        switch event.status {
        case .normal:
            return Color(red: 51 / 255, green: 98 / 255, blue: 225 / 255) // BrandBlue #3362E1
        case .changed, .moved:
            return Color(red: 46 / 255, green: 158 / 255, blue: 91 / 255) // #2E9E5B
        case .cancelled:
            return Color(red: 211 / 255, green: 47 / 255, blue: 47 / 255) // #D32F2F
        }
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.preferredColorScheme
    }

    // MARK: - Lesson Mapping Scope

    func activateScope(studentId: String, schoolId: String) {
        currentStudentId = studentId
        currentSchoolId = schoolId
        lessonMappings = cachedLessonMappingsByScope[scopeKey(studentId: studentId, schoolId: schoolId)] ?? [:]
    }

    // MARK: - Lesson Mapping Accessors

    func displayName(for subjectCode: String) -> String? {
        mapping(for: subjectCode)?.displayName
    }

    func defaultName(for subjectCode: String) -> String? {
        if let mapping = mapping(for: subjectCode) {
            return mapping.defaultName
        }
        return SubjectMapper.defaultName(for: subjectCode, fallback: nil)
    }

    /// Returns the effective display color for the canonical mapping if one exists.
    func color(for subjectCode: String) -> Color? {
        mapping(for: subjectCode).map { Color.lessonMappingHue($0.displayColorHue) }
    }

    func defaultColor(for subjectCode: String) -> Color? {
        if let mapping = mapping(for: subjectCode) {
            return Color.lessonMappingHue(mapping.defaultColorHue)
        }
        return SubjectMapper.defaultColor(for: subjectCode)
    }

    /// Returns only a user override, not the effective display name.
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

    // MARK: - Lesson Mapping Mutations

    func saveCustomization(name: String?, color: Color?, for subjectCode: String) {
        guard
            let canonicalKey = canonicalKey(for: subjectCode),
            var mapping = lessonMappings[canonicalKey]
        else {
            return
        }

        let overrideName = normalizedOverrideName(name, defaultName: mapping.defaultName)
        let overrideColorHue = normalizedOverrideHue(color, defaultHue: mapping.defaultColorHue)
        let overrideIcon = iconOverride(for: mapping)

        mapping.displayName = overrideName ?? mapping.defaultName
        mapping.displayColorHue = overrideColorHue ?? mapping.defaultColorHue

        applyLocalMapping(mapping, for: canonicalKey)
        pushMappingUpdate(
            mapping: mapping,
            overrideName: overrideName,
            overrideColorHue: overrideColorHue,
            overrideIcon: overrideIcon
        )
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
        pushMappingReset(mapping: mapping)
    }

    func resetAllLessonMappings() {
        let overriddenKeys = lessonMappings.keys.filter(hasAnyOverride(for:))
        for canonicalKey in overriddenKeys {
            resetMapping(for: canonicalKey)
        }
    }

    // MARK: - Supabase Sync

    func syncWithSupabase(studentId: String, schoolId: String) async {
        await MainActor.run {
            self.activateScope(studentId: studentId, schoolId: schoolId)
        }

        do {
            let remoteMappings = try await SupabaseSubjectService.shared.fetchMappings(
                studentId: studentId,
                schoolId: schoolId
            )

            let activeMappings = remoteMappings
                .filter { $0.deletedAt == nil }
                .reduce(into: [String: SubjectMapper.ResolvedLessonMapping]()) { result, mapping in
                    result[mapping.canonicalKey] = SubjectMapper.ResolvedLessonMapping(
                        mappingId: mapping.mappingId,
                        canonicalKey: mapping.canonicalKey,
                        defaultName: mapping.defaultName,
                        defaultColorHue: mapping.defaultColorHue,
                        defaultIcon: mapping.icon,
                        displayName: mapping.displayName,
                        displayColorHue: mapping.displayColorHue,
                        displayIcon: mapping.displayIcon
                    )
                }

            await MainActor.run {
                self.currentStudentId = studentId
                self.currentSchoolId = schoolId
                self.cachedLessonMappingsByScope[self.scopeKey(studentId: studentId, schoolId: schoolId)] = activeMappings
                self.lessonMappings = activeMappings
                self.saveLessonMappingCache()
            }

            print("✅ [SettingsStore] Synced lesson mappings v2")
        } catch {
            print("⚠️ [SettingsStore] Failed to sync lesson mappings v2: \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Management

    /// Clears locally cached Lectio data (schedules, directory, messages, homework, student search, images).
    /// Does not remove credentials, cookies, or app preferences (appearance, notifications, subject mappings).
    func clearAllCaches() {
        Task { @MainActor in
            await LectioImageLoader.shared.clearCache()
            URLCache.shared.removeAllCachedResponses()

            await ScheduleStore.shared.clearAllSchedulesAsync()
            SharedScheduleData.clear()
            await DirectoryStore.shared.clearAllDirectoryDataAsync()
            await StudentStore.shared.clearAllStudentsAsync()
            await HomeworkStore.shared.clearAllHomeworkAsync()
            await MessageCacheManager.clearCache()

            NotificationCenter.default.post(name: .betterLectioCachesDidClear, object: nil)

            print("🗑️ All caches cleared")
        }
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

    private func canonicalKey(for subjectCode: String) -> String? {
        let normalized = SubjectMapper.normalizedHold(subjectCode)
        if let canonical = SubjectMapper.canonicalKey(for: normalized) {
            return canonical
        }

        let lowered = normalized.lowercased(with: Locale(identifier: "da_DK"))
        return lowered.isEmpty ? nil : lowered
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

    private func iconOverride(for mapping: SubjectMapper.ResolvedLessonMapping) -> String? {
        guard mapping.displayIcon != mapping.defaultIcon else {
            return nil
        }
        return mapping.displayIcon
    }

    private func applyLocalMapping(_ mapping: SubjectMapper.ResolvedLessonMapping, for canonicalKey: String) {
        lessonMappings[canonicalKey] = mapping
        persistCurrentScopeMappings()
    }

    private func persistCurrentScopeMappings() {
        guard let scopeKey = currentScopeKey else { return }
        cachedLessonMappingsByScope[scopeKey] = lessonMappings
        saveLessonMappingCache()
    }

    private func pushMappingUpdate(
        mapping: SubjectMapper.ResolvedLessonMapping,
        overrideName: String?,
        overrideColorHue: Int?,
        overrideIcon: String?
    ) {
        guard
            let studentId = currentStudentId,
            let schoolId = currentSchoolId
        else {
            return
        }

        Task {
            do {
                if overrideName == nil, overrideColorHue == nil, overrideIcon == nil {
                    try await SupabaseSubjectService.shared.resetMappingOverride(
                        studentId: studentId,
                        schoolId: schoolId,
                        mappingId: mapping.mappingId
                    )
                } else {
                    try await SupabaseSubjectService.shared.upsertMappingOverride(
                        studentId: studentId,
                        schoolId: schoolId,
                        mappingId: mapping.mappingId,
                        displayName: overrideName,
                        colorHue: overrideColorHue,
                        icon: overrideIcon
                    )
                }
            } catch {
                print("⚠️ [SettingsStore] Failed to write lesson mapping override: \(error.localizedDescription)")
                await self.syncWithSupabase(studentId: studentId, schoolId: schoolId)
            }
        }
    }

    private func pushMappingReset(mapping: SubjectMapper.ResolvedLessonMapping) {
        guard
            let studentId = currentStudentId,
            let schoolId = currentSchoolId
        else {
            return
        }

        Task {
            do {
                try await SupabaseSubjectService.shared.resetMappingOverride(
                    studentId: studentId,
                    schoolId: schoolId,
                    mappingId: mapping.mappingId
                )
            } catch {
                print("⚠️ [SettingsStore] Failed to reset lesson mapping override: \(error.localizedDescription)")
                await self.syncWithSupabase(studentId: studentId, schoolId: schoolId)
            }
        }
    }

    private var currentScopeKey: String? {
        guard let studentId = currentStudentId, let schoolId = currentSchoolId else {
            return nil
        }
        return scopeKey(studentId: studentId, schoolId: schoolId)
    }

    private func scopeKey(studentId: String, schoolId: String) -> String {
        "\(schoolId)::\(studentId)"
    }

    private func normalizedHue(_ hue: Int) -> Int {
        ((hue % 360) + 360) % 360
    }
}

// MARK: - Color Extensions

extension Notification.Name {
    /// Posted after `SettingsStore.clearAllCaches()` finishes clearing disk and memory caches. Views should reload from network.
    static let betterLectioCachesDidClear = Notification.Name("dk.elliottf.betterlectio.cachesDidClear")
}

extension Color {
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
