//
//  ScheduleViewModel.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import SwiftUI
import Combine

/// View model for managing schedule data and state
@MainActor
class ScheduleViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var events: [ScheduleEvent] = [] {
        didSet {
            eventsByDayCache = Dictionary(grouping: events) {
                Calendar.current.startOfDay(for: $0.date)
            }
            rebuildDayEventsCache()
        }
    }
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var requiresReauthentication = false
    @Published var lastUpdated: Date?
    @Published var lessonContent: [String: LessonContent] = [:] // keyed by eventId

    // MARK: - Services

    private let httpClient = LectioHTTPClient()
    private let store = ScheduleStore.shared
    private let directoryStore = DirectoryStore.shared
    private let supabaseScheduleService = SupabaseScheduleService()
    private let keychainManager = KeychainManager.shared
    private var fetchedWeekKeys: Set<String> = []
    private var fetchingWeekKeys: Set<String> = []
    private var contentFetchingIds: Set<String> = []
    private var prefetchTask: Task<Void, Never>?
    private var loadedTargetKey: String?
    private var lastSuccessfulRefreshByTarget: [String: Date] = [:]
    private var eventsByDayCache: [Date: [ScheduleEvent]] = [:]

    // MARK: - Load Schedule

    /// Loads schedule for a student (from cache first, then fetches fresh data)
    /// - Parameters:
    ///   - target: The schedule target to view
    ///   - authenticatedStudent: The logged-in student used for credentials
    func loadSchedule(for target: SchedulableTarget, authenticatedStudent: Student) async {
        print("📅 Loading schedule for \(target.displayName)")

        if authenticatedStudent.isDemo {
            loadDemoSchedule()
            return
        }

        if loadedTargetKey == target.storageKey,
           let refreshedAt = lastSuccessfulRefreshByTarget[target.storageKey],
           TimeProvider.now.timeIntervalSince(refreshedAt) < 5 * 60 {
            return
        }

        let targetChanged = loadedTargetKey != target.storageKey
        if targetChanged {
            prefetchTask?.cancel()
            fetchedWeekKeys.removeAll()
            fetchingWeekKeys.removeAll()
            isRefreshing = false
            contentFetchingIds.removeAll()
            lessonContent.removeAll()
        }

        await store.migrateLegacyCacheIfNeededAsync(for: target.storageKey)
        guard !Task.isCancelled else { return }
        loadedTargetKey = target.storageKey

        // 1. Load from cache immediately (for instant UI)
        let cachedData = await store.loadScheduleAsync(for: target.storageKey)
        guard loadedTargetKey == target.storageKey, !Task.isCancelled else { return }
        if let cachedData {
            events = cachedData.events
            lastUpdated = cachedData.lastUpdated
            fetchedWeekKeys.formUnion(cachedData.events.map { ScheduleIdentity.weekKey(for: $0.date) })
            print("✅ Loaded \(events.count) cached events from \(cachedData.lastUpdated)")

            // Log cached events
            if !events.isEmpty {
                print("📦 Cached events preview:")
                for (index, event) in events.prefix(3).enumerated() {
                    print("   [\(index + 1)] \(event.title) at \(event.startTime)")
                }
            }
        } else {
            print("📭 No cached data found")
            events = []
            lastUpdated = nil
            fetchedWeekKeys.removeAll()
            lessonContent.removeAll()
            fetchingWeekKeys.removeAll()
            contentFetchingIds.removeAll()
        }

        // 2. ALWAYS fetch fresh data (don't wait for staleness)
        print("🔄 Fetching fresh schedule data...")
        await refreshSchedule(for: target, authenticatedStudent: authenticatedStudent)
    }

    // MARK: - Refresh Schedule

    /// Fetches fresh schedule data from Lectio
    func refreshSchedule(for target: SchedulableTarget, authenticatedStudent: Student) async {
        if authenticatedStudent.isDemo {
            loadDemoSchedule()
            return
        }
        await refreshSchedule(for: target, authenticatedStudent: authenticatedStudent, weekOf: TimeProvider.now, force: true)
    }

    /// Fetches a specific week when not already available in local cache.
    func ensureWeekLoadedIfNeeded(for date: Date, target: SchedulableTarget, authenticatedStudent: Student) async {
        if authenticatedStudent.isDemo {
            loadDemoSchedule(weekOf: date)
            return
        }
        let weekKey = ScheduleIdentity.weekKey(for: date)

        if fetchedWeekKeys.contains(weekKey) {
            return
        }

        // If we already have events for the week in local store, treat it as loaded.
        if await store.hasEventsAsync(studentId: target.storageKey, weekKey: weekKey) {
            fetchedWeekKeys.insert(weekKey)
            return
        }

        await refreshSchedule(for: target, authenticatedStudent: authenticatedStudent, weekOf: date, force: false)
    }

    /// Fetches fresh schedule data for a specific week from Lectio.
    func refreshSchedule(for target: SchedulableTarget, authenticatedStudent: Student, weekOf date: Date, force: Bool) async {
        if authenticatedStudent.isDemo {
            loadDemoSchedule(weekOf: date)
            return
        }
        let weekKey = ScheduleIdentity.weekKey(for: date)
        let fetchKey = "\(target.storageKey)|\(weekKey)"

        if !force && fetchedWeekKeys.contains(weekKey) {
            return
        }

        if fetchingWeekKeys.contains(fetchKey) {
            return
        }
        fetchingWeekKeys.insert(fetchKey)
        defer {
            fetchingWeekKeys.remove(fetchKey)
            isRefreshing = !fetchingWeekKeys.isEmpty
        }

        isRefreshing = true
        errorMessage = nil
        requiresReauthentication = false

        do {
            // Always use the logged-in user's credentials. We do not gate on expiry dates —
            // stale-looking credentials are still worth trying; Lectio rotates cookies on the
            // next request and the HTTP client's retry loop handles transient failures.
            //
            // A nil keychain read is treated as a transient failure (locked-keychain in a
            // pre-first-unlock background launch, momentary OS error), NOT a logout signal.
            // Throwing `.invalidCredentials` here would route through `notifyIfSessionExpired()`
            // and force-log-out the user from a recoverable hiccup. Surface a banner instead;
            // the next refresh will reload from keychain and recover.
            guard let credentials = keychainManager.loadCredentials(for: authenticatedStudent.studentId) else {
                print("⚠️ [Schedule] Keychain returned nil for \(authenticatedStudent.studentId) — surfacing banner, not logging out")
                errorMessage = "Kunne ikke læse loginoplysninger. Prøv igen."
                return
            }

            print("🌐 Fetching schedule from Lectio...")

            let lectioWeekParam = ScheduleIdentity.lectioWeekParameter(for: date)

            // Fetch schedule HTML
            let result = try await httpClient.fetchSchedule(
                credentials: credentials,
                studentId: authenticatedStudent.studentId,
                target: target,
                week: lectioWeekParam
            )
            let html = result.html

            print("✅ Received schedule HTML (\(html.count) characters)")

            // Store enriched student info if available (only when fetching own schedule)
            if let studentInfo = result.studentInfo,
               target.kind == .student,
               target.id == authenticatedStudent.studentId {
                await directoryStore.saveLoggedInStudentInfoAsync(
                    pictureID: studentInfo.pictureId,
                    classLabel: studentInfo.classLabel,
                    for: authenticatedStudent.studentId,
                    gymId: target.gymId
                )
                try Task.checkCancellation()
                print("💾 Saved enriched student info - Picture: \(studentInfo.pictureId ?? "nil"), Class: \(studentInfo.classLabel ?? "nil")")
            }

            // Parse HTML into events
            let newEvents = try await Task.detached(priority: .userInitiated) {
                try ScheduleParser.parseSchedule(from: html)
            }.value
            try Task.checkCancellation()

            print("📋 Schedule Schema Fetched:")
            print("   Total events: \(newEvents.count)")
            print("   Last updated: \(TimeProvider.now)")

            // Print sample events for debugging
            if !newEvents.isEmpty {
                print("   Sample events:")
                for (index, event) in newEvents.prefix(5).enumerated() {
                    print("   [\(index + 1)] \(event.title)")
                    print("       - Date: \(event.date)")
                    print("       - Time: \(event.startTime) - \(event.endTime)")
                    print("       - Teacher: \(event.teacher ?? "N/A")")
                    print("       - Room: \(event.room ?? "N/A")")
                    print("       - Status: \(event.status.rawValue)")
                }
            }

            // Persist and reload on a background SwiftData context.
            let snapshot = try await store.persistWeekAsync(
                studentId: target.storageKey,
                weekKey: weekKey,
                events: newEvents
            )
            try Task.checkCancellation()
            guard loadedTargetKey == target.storageKey else { return }
            events = snapshot.events
            lastUpdated = snapshot.lastUpdated
            fetchedWeekKeys.insert(weekKey)
            lastSuccessfulRefreshByTarget[target.storageKey] = TimeProvider.now

            // Remote sync is best-effort and should not block local UX.
            if target.kind == .student {
                Task {
                    await supabaseScheduleService.syncWeek(
                        studentId: target.id,
                        weekKey: weekKey,
                        events: newEvents
                    )
                }
            }

            // Background pre-fetch lesson content for this week's events.
            prefetchTask?.cancel()
            prefetchTask = Task { [weak self] in
                guard let self else { return }
                await prefetchContent(for: newEvents, target: target, authenticatedStudent: authenticatedStudent)
            }

        } catch {
            guard loadedTargetKey == target.storageKey else { return }
            handleError(error)
        }
    }

    // MARK: - Filter Events by Date

    /// Pre-split events for a single day, plus the day's latest lesson end (in minutes
    /// since midnight). Computed once when `events` changes rather than re-filtering the
    /// full events array (and re-parsing time strings) on every view render.
    struct DayEvents {
        var allDay: [ScheduleEvent] = []
        var timed: [ScheduleEvent] = []
        var maxEndMinutes: Int?
    }

    /// Per-day cache keyed by `startOfDay`, rebuilt whenever `events` changes.
    private var dayEventsCache: [Date: DayEvents] = [:]

    private func rebuildDayEventsCache() {
        let calendar = Calendar.current
        var cache: [Date: DayEvents] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            var bucket = cache[day] ?? DayEvents()
            if event.isAllDay {
                bucket.allDay.append(event)
            } else {
                bucket.timed.append(event)
                let end = event.timeToMinutes(event.endTime)
                bucket.maxEndMinutes = max(bucket.maxEndMinutes ?? 0, end)
            }
            cache[day] = bucket
        }
        dayEventsCache = cache
    }

    /// Returns the pre-split, cached events for a specific day.
    func dayEvents(for date: Date) -> DayEvents {
        dayEventsCache[Calendar.current.startOfDay(for: date)] ?? DayEvents()
    }

    /// Returns events for a specific date
    func events(for date: Date) -> [ScheduleEvent] {
        eventsByDayCache[Calendar.current.startOfDay(for: date)] ?? []
    }

    /// Returns events grouped by date
    func eventsByDate() -> [Date: [ScheduleEvent]] {
        eventsByDayCache
    }

    // MARK: - Lesson Content

    /// Returns cached content (in-memory or local store) without any network request.
    func cachedContent(for event: ScheduleEvent, target: SchedulableTarget) async -> LessonContent? {
        if let cached = lessonContent[event.id] {
            return cached
        }
        if let stored = await store.loadContentAsync(for: event.id, studentId: target.storageKey) {
            guard !Task.isCancelled else { return nil }
            lessonContent[event.id] = stored
            return stored
        }
        return nil
    }

    /// Fetches fresh content from Lectio. Updates in-memory cache, local store, and Supabase.
    @discardableResult
    func refreshContent(for event: ScheduleEvent, target: SchedulableTarget, authenticatedStudent: Student) async -> LessonContent? {
        return await fetchAndStoreContent(for: event, target: target, authenticatedStudent: authenticatedStudent)
    }

    /// Fetches lesson content from Lectio, parses it, stores locally, and syncs to Supabase.
    func fetchAndStoreContent(
        for event: ScheduleEvent,
        target: SchedulableTarget,
        authenticatedStudent: Student,
        priority: FetchPriority = .important
    ) async -> LessonContent? {
        if authenticatedStudent.isDemo {
            let content = DemoDataProvider.lessonContent(for: event)
            lessonContent[event.id] = content
            return content
        }

        // Private appointments (`AFT...`) don't have lesson-content pages.
        // Surface their inline note from the schedule tooltip as detail content.
        if event.id.hasPrefix("AFT") {
            let privateEventContent = LessonContent(
                teacherNote: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil,
                items: []
            )
            await store.saveContentAsync(for: event.id, studentId: target.storageKey, content: privateEventContent)
            guard !Task.isCancelled else { return nil }
            lessonContent[event.id] = privateEventContent
            return privateEventContent
        }

        guard let absId = LectioHTTPClient.absId(from: event.id) else {
            print("⚠️ Could not extract absId from event id: \(event.id)")
            return nil
        }

        // Prevent duplicate fetches
        guard !contentFetchingIds.contains(event.id) else { return nil }
        contentFetchingIds.insert(event.id)
        defer { contentFetchingIds.remove(event.id) }

        do {
            guard let credentials = keychainManager.loadCredentials(for: authenticatedStudent.studentId) else {
                return nil
            }

            let html = try await httpClient.fetchLessonContent(
                credentials: credentials,
                studentId: authenticatedStudent.studentId,
                schoolId: target.gymId,
                absId: absId,
                priority: priority
            )

            let content = try await Task.detached(priority: .userInitiated) {
                try ScheduleParser.parseLessonContent(from: html)
            }.value
            try Task.checkCancellation()

            // Save locally
            await store.saveContentAsync(for: event.id, studentId: target.storageKey, content: content)
            try Task.checkCancellation()

            // Update in-memory cache
            lessonContent[event.id] = content

            // Sync to Supabase (best-effort, non-blocking)
            if target.kind == .student {
                let lessonKey = ScheduleIdentity.lessonKey(for: event, studentId: target.id)
                Task {
                    await supabaseScheduleService.syncLessonContent(
                        studentId: target.id,
                        lessonKey: lessonKey,
                        content: content
                    )
                }
            }

            return content
        } catch {
            print("❌ Failed to fetch lesson content for \(event.title): \(error.localizedDescription)")
            return nil
        }
    }

    /// Pre-fetches content for all events in a week. Called after schedule refresh.
    /// Throttles requests to avoid overwhelming Lectio.
    func prefetchContent(for events: [ScheduleEvent], target: SchedulableTarget, authenticatedStudent: Student) async {
        if authenticatedStudent.isDemo { return }
        let storedContents = await store.loadContentsAsync(
            for: Set(events.map(\.id)),
            studentId: target.storageKey
        )
        guard !Task.isCancelled else { return }
        for event in events {
            guard !Task.isCancelled else { return }
            // Skip if already cached
            if lessonContent[event.id] != nil { continue }
            if let stored = storedContents[event.id] {
                lessonContent[event.id] = stored
                continue
            }

            // Fetch with throttle
            _ = await fetchAndStoreContent(
                for: event,
                target: target,
                authenticatedStudent: authenticatedStudent,
                priority: .opportunistic
            )

            // Throttle: 0.5s between requests
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error) {
        // Ignore cancellation — happens when view redraws during pull-to-refresh or user navigates away
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }

        print("❌ Schedule error: \(error.localizedDescription)")

        if let lectioError = error as? LectioError {
            switch lectioError {
            case .invalidCredentials:
                // Definitive: HTTP client already retried 3×. Lectio sessions don't recover and
                // we can't silently re-MitID. Trigger force-logout — AuthenticationViewModel
                // observes this notification and routes back to LoginView.
                lectioError.notifyIfSessionExpired()
                errorMessage = "Din session er udløbet"
                requiresReauthentication = false
            case .cookieExpired, .robotDetection:
                // Recoverable: keep the banner + Prøv igen affordance.
                errorMessage = "Forbindelsen til Lectio fejlede. Prøv igen."
                requiresReauthentication = true
            case .networkError(let underlyingError):
                errorMessage = "Netværksfejl: \(underlyingError.localizedDescription)"
            case .parsingError(let detail):
                errorMessage = "Kunne ikke læse skema: \(detail)"
            default:
                errorMessage = lectioError.localizedDescription
            }
        } else {
            errorMessage = "Der opstod en fejl: \(error.localizedDescription)"
        }
    }

    // MARK: - Demo Mode

    /// Populates schedule state with in-memory demo data (no HTTP, no stores).
    private func loadDemoSchedule(weekOf date: Date = TimeProvider.now) {
        let demoEvents = DemoDataProvider.scheduleEvents(weekOf: date)
        events = demoEvents
        lastUpdated = TimeProvider.now
        isLoading = false
        isRefreshing = false
        errorMessage = nil
        requiresReauthentication = false
        // Seed a couple of weeks so the UI doesn't try to fetch more.
        fetchedWeekKeys = Set(demoEvents.map { ScheduleIdentity.weekKey(for: $0.date) })
    }

    // MARK: - Clear Cache

    /// Clears cached schedule data
    func clearCache(for target: SchedulableTarget) {
        prefetchTask?.cancel()
        store.deleteSchedule(for: target.storageKey)
        events = []
        lastUpdated = nil
        lessonContent.removeAll()
        fetchedWeekKeys.removeAll()
        fetchingWeekKeys.removeAll()
        contentFetchingIds.removeAll()
        lastSuccessfulRefreshByTarget.removeValue(forKey: target.storageKey)
        print("🗑️ Cleared schedule cache")
    }

    func cancelBackgroundTasks() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }
}
