//
//  ScheduleStore.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import SwiftData

@Model
final class LessonRecord {
    @Attribute(.unique) var uniqueKey: String
    var studentId: String
    var lessonKey: String
    var eventId: String
    var weekKey: String
    var lessonDate: Date
    var startTime: String
    var endTime: String
    var title: String
    var subtitle: String
    var teacher: String?
    /// Lectio teacher id from `data-lectiocontextcard` (digits only, no "T" prefix).
    var teacherId: String?
    var room: String?
    var status: String
    var notes: String?
    var homework: String?
    var contentJSON: Data?
    var sourceUpdatedAt: Date
    var updatedAt: Date
    /// Default value enables SwiftData lightweight migration for existing stores.
    var isAllDay: Bool = false

    init(
        uniqueKey: String,
        studentId: String,
        lessonKey: String,
        eventId: String,
        weekKey: String,
        lessonDate: Date,
        startTime: String,
        endTime: String,
        title: String,
        subtitle: String,
        teacher: String?,
        teacherId: String? = nil,
        room: String?,
        status: String,
        notes: String?,
        homework: String?,
        contentJSON: Data? = nil,
        sourceUpdatedAt: Date,
        updatedAt: Date,
        isAllDay: Bool = false
    ) {
        self.uniqueKey = uniqueKey
        self.studentId = studentId
        self.lessonKey = lessonKey
        self.eventId = eventId
        self.weekKey = weekKey
        self.lessonDate = lessonDate
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.subtitle = subtitle
        self.teacher = teacher
        self.teacherId = teacherId
        self.room = room
        self.status = status
        self.notes = notes
        self.homework = homework
        self.contentJSON = contentJSON
        self.sourceUpdatedAt = sourceUpdatedAt
        self.updatedAt = updatedAt
        self.isAllDay = isAllDay
    }
}

/// Local schedule storage backed by SwiftData.
@MainActor
class ScheduleStore {
    static let shared = ScheduleStore()
    private let container: ModelContainer
    private let context: ModelContext
    private let userDefaults = UserDefaults.standard
    private let legacyKeyPrefix = "lectio.schedule."
    private let migrationKeyPrefix = "lectio.schedule.migrated.v2."

    private init() {
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = storeDirectory.appendingPathComponent("Schedule.store")
        let config = ModelConfiguration(url: storeURL)
        do {
            // Use a dedicated store file so we don't conflict with StudentStore's default.store.
            // Both stores would otherwise share default.store but with different schemas,
            // causing "no such table: ZLESSONRECORD" when the wrong schema was created first.
            container = try ModelContainer(for: LessonRecord.self, configurations: config)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            print("⚠️ Failed to initialize ScheduleStore, rebuilding cache: \(error)")
            Self.removeSQLiteStore(at: storeURL)
            do {
                container = try ModelContainer(for: LessonRecord.self, configurations: config)
                context = ModelContext(container)
                context.autosaveEnabled = true
            } catch {
                print("⚠️ ScheduleStore recovery failed; using memory-only cache: \(error)")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    container = try ModelContainer(for: LessonRecord.self, configurations: memoryConfig)
                    context = ModelContext(container)
                    context.autosaveEnabled = true
                } catch {
                    fatalError("Failed to initialize even an in-memory ScheduleStore: \(error)")
                }
            }
        }
    }

    private static func removeSQLiteStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: - Load

    /// Loads all cached schedule events for a student.
    func loadSchedule(for studentId: String) -> ScheduleData? {
        let loadedEvents = loadEvents(for: studentId)
        guard !loadedEvents.isEmpty else {
            print("📭 No cached schedule found for student \(studentId)")
            return nil
        }

        return ScheduleData(
            studentId: studentId,
            events: loadedEvents,
            lastUpdated: lastUpdated(for: studentId) ?? TimeProvider.now
        )
    }

    /// Loads all events for a student, sorted by date and start time.
    func loadEvents(for studentId: String) -> [ScheduleEvent] {
        do {
            let descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId },
                sortBy: [
                    SortDescriptor(\.lessonDate, order: .forward),
                    SortDescriptor(\.startTime, order: .forward)
                ]
            )
            return try context.fetch(descriptor).map(Self.toScheduleEvent(_:))
        } catch {
            print("❌ Failed to load cached events: \(error)")
            return []
        }
    }

    /// Loads events for a specific week key.
    func loadWeek(studentId: String, weekKey: String) -> [ScheduleEvent] {
        do {
            let descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId && $0.weekKey == weekKey },
                sortBy: [
                    SortDescriptor(\.lessonDate, order: .forward),
                    SortDescriptor(\.startTime, order: .forward)
                ]
            )
            return try context.fetch(descriptor).map(Self.toScheduleEvent(_:))
        } catch {
            print("❌ Failed to load week \(weekKey): \(error)")
            return []
        }
    }

    func loadScheduleAsync(for studentId: String) async -> ScheduleData? {
        let container = container
        return await Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.studentId == studentId },
                    sortBy: [
                        SortDescriptor(\LessonRecord.lessonDate, order: .forward),
                        SortDescriptor(\LessonRecord.startTime, order: .forward)
                    ]
                )
                let records = try context.fetch(descriptor)
                guard !records.isEmpty else { return nil }
                return ScheduleData(
                    studentId: studentId,
                    events: records.map(Self.toScheduleEvent),
                    lastUpdated: records.map(\.updatedAt).max() ?? TimeProvider.now
                )
            } catch {
                print("❌ Failed to load cached schedule: \(error)")
                return nil
            }
        }.value
    }

    func hasEventsAsync(studentId: String, weekKey: String) async -> Bool {
        let container = container
        return await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.studentId == studentId && $0.weekKey == weekKey }
                )
                descriptor.fetchLimit = 1
                return try !context.fetch(descriptor).isEmpty
            } catch {
                return false
            }
        }.value
    }

    // MARK: - Upsert

    func upsertWeek(studentId: String, weekKey: String, events: [ScheduleEvent]) throws {
        let syncedAt = TimeProvider.now
        let existingDescriptor = FetchDescriptor<LessonRecord>(
            predicate: #Predicate { $0.studentId == studentId }
        )
        var existingByKey = Dictionary(
            uniqueKeysWithValues: try context.fetch(existingDescriptor).map { ($0.uniqueKey, $0) }
        )

        for event in events {
            let lessonKey = ScheduleIdentity.lessonKey(for: event, studentId: studentId)
            let uniqueKey = Self.uniqueKey(studentId: studentId, lessonKey: lessonKey)

            if let record = existingByKey.removeValue(forKey: uniqueKey) {
                Self.apply(event: event, to: record, studentId: studentId, lessonKey: lessonKey, syncedAt: syncedAt)
                record.weekKey = weekKey
            } else {
                let record = LessonRecord(
                    uniqueKey: uniqueKey,
                    studentId: studentId,
                    lessonKey: lessonKey,
                    eventId: event.id,
                    weekKey: weekKey,
                    lessonDate: event.date,
                    startTime: event.startTime,
                    endTime: event.endTime,
                    title: event.title,
                    subtitle: event.subtitle,
                    teacher: event.teacher,
                    teacherId: event.teacherId,
                    room: event.room,
                    status: event.status.rawValue,
                    notes: event.notes,
                    homework: event.homework,
                    sourceUpdatedAt: syncedAt,
                    updatedAt: syncedAt,
                    isAllDay: event.isAllDay
                )
                context.insert(record)
            }
        }

        try context.save()
    }

    func markMissingAsCancelled(studentId: String, weekKey: String, fetchedLessonKeys: Set<String>) throws {
        let now = TimeProvider.now
        let descriptor = FetchDescriptor<LessonRecord>(
            predicate: #Predicate { $0.studentId == studentId && $0.weekKey == weekKey }
        )
        let weekRecords = try context.fetch(descriptor)
        for record in weekRecords where !fetchedLessonKeys.contains(record.lessonKey) {
            record.status = EventStatus.cancelled.rawValue
            record.updatedAt = now
        }
        try context.save()
    }

    /// Persists a fetched week and returns a fresh full-schedule snapshot without
    /// blocking the UI actor on SQLite work or model conversion.
    func persistWeekAsync(
        studentId: String,
        weekKey: String,
        events: [ScheduleEvent]
    ) async throws -> ScheduleData {
        let container = container
        return try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let syncedAt = TimeProvider.now
            let existingDescriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId }
            )
            var existingByKey = Dictionary(
                uniqueKeysWithValues: try context.fetch(existingDescriptor).map { ($0.uniqueKey, $0) }
            )

            for event in events {
                try Task.checkCancellation()
                let lessonKey = ScheduleIdentity.lessonKey(for: event, studentId: studentId)
                let key = Self.uniqueKey(studentId: studentId, lessonKey: lessonKey)
                if let record = existingByKey[key] {
                    Self.apply(event: event, to: record, studentId: studentId, lessonKey: lessonKey, syncedAt: syncedAt)
                    record.weekKey = weekKey
                } else {
                    context.insert(LessonRecord(
                        uniqueKey: key,
                        studentId: studentId,
                        lessonKey: lessonKey,
                        eventId: event.id,
                        weekKey: weekKey,
                        lessonDate: event.date,
                        startTime: event.startTime,
                        endTime: event.endTime,
                        title: event.title,
                        subtitle: event.subtitle,
                        teacher: event.teacher,
                        teacherId: event.teacherId,
                        room: event.room,
                        status: event.status.rawValue,
                        notes: event.notes,
                        homework: event.homework,
                        sourceUpdatedAt: syncedAt,
                        updatedAt: syncedAt,
                        isAllDay: event.isAllDay
                    ))
                }
            }

            let fetchedLessonKeys = Set(events.map {
                ScheduleIdentity.lessonKey(for: $0, studentId: studentId)
            })
            for record in existingByKey.values
                where record.weekKey == weekKey && !fetchedLessonKeys.contains(record.lessonKey) {
                record.status = EventStatus.cancelled.rawValue
                record.updatedAt = syncedAt
            }

            try Task.checkCancellation()
            try context.save()

            let refreshedRecords = try context.fetch(FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId },
                sortBy: [
                    SortDescriptor(\LessonRecord.lessonDate, order: .forward),
                    SortDescriptor(\LessonRecord.startTime, order: .forward)
                ]
            ))
            return ScheduleData(
                studentId: studentId,
                events: refreshedRecords.map(Self.toScheduleEvent),
                lastUpdated: refreshedRecords.map(\.updatedAt).max() ?? syncedAt
            )
        }.value
    }

    func lessonKeys(for events: [ScheduleEvent], studentId: String) -> Set<String> {
        Set(events.map { ScheduleIdentity.lessonKey(for: $0, studentId: studentId) })
    }

    // MARK: - Lesson Content

    /// Saves parsed lesson content for a specific event.
    func saveContent(for eventId: String, studentId: String, content: LessonContent) {
        do {
            let descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId && $0.eventId == eventId }
            )
            guard let record = try context.fetch(descriptor).first else {
                print("⚠️ No LessonRecord found for eventId \(eventId)")
                return
            }
            record.contentJSON = try JSONEncoder().encode(content)
            record.updatedAt = TimeProvider.now
            try context.save()
        } catch {
            print("❌ Failed to save lesson content: \(error)")
        }
    }

    /// Loads parsed lesson content for a specific event.
    func loadContent(for eventId: String, studentId: String) -> LessonContent? {
        do {
            let descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId && $0.eventId == eventId }
            )
            guard let record = try context.fetch(descriptor).first,
                  let data = record.contentJSON else {
                return nil
            }
            return try JSONDecoder().decode(LessonContent.self, from: data)
        } catch {
            print("❌ Failed to load lesson content: \(error)")
            return nil
        }
    }

    func loadContentAsync(for eventId: String, studentId: String) async -> LessonContent? {
        let contents = await loadContentsAsync(for: [eventId], studentId: studentId)
        return contents[eventId]
    }

    func loadContentsAsync(for eventIds: Set<String>, studentId: String) async -> [String: LessonContent] {
        guard !eventIds.isEmpty else { return [:] }
        let container = container
        return await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.studentId == studentId && $0.contentJSON != nil }
                )
                return try context.fetch(descriptor).reduce(into: [:]) { result, record in
                    guard eventIds.contains(record.eventId),
                          let data = record.contentJSON,
                          let content = try? JSONDecoder().decode(LessonContent.self, from: data) else {
                        return
                    }
                    result[record.eventId] = content
                }
            } catch {
                return [:]
            }
        }.value
    }

    func saveContentAsync(for eventId: String, studentId: String, content: LessonContent) async {
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.studentId == studentId && $0.eventId == eventId }
                )
                guard let record = try context.fetch(descriptor).first else { return }
                record.contentJSON = try JSONEncoder().encode(content)
                record.updatedAt = TimeProvider.now
                try context.save()
            } catch {
                print("❌ Failed to save lesson content: \(error)")
            }
        }.value
    }

    // MARK: - Legacy Migration

    /// Migrates legacy UserDefaults schedule cache into Core Data once per student.
    func migrateLegacyCacheIfNeeded(for studentId: String) {
        let migrationKey = migrationMarkerKey(for: studentId)
        guard userDefaults.bool(forKey: migrationKey) == false else {
            return
        }

        defer { userDefaults.set(true, forKey: migrationKey) }

        let legacyKey = legacyScheduleKey(for: studentId)
        guard let data = userDefaults.data(forKey: legacyKey) else {
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let legacySchedule = try decoder.decode(ScheduleData.self, from: data)

            let groupedByWeek = Dictionary(grouping: legacySchedule.events) { event in
                ScheduleIdentity.weekKey(for: event.date)
            }

            for (weekKey, weekEvents) in groupedByWeek {
                try upsertWeek(studentId: studentId, weekKey: weekKey, events: weekEvents)
            }

            userDefaults.removeObject(forKey: legacyKey)
            print("✅ Migrated \(legacySchedule.events.count) legacy events to Core Data")
        } catch {
            print("❌ Failed to migrate legacy schedule cache: \(error)")
        }
    }

    func migrateLegacyCacheIfNeededAsync(for studentId: String) async {
        let migrationKey = migrationMarkerKey(for: studentId)
        guard userDefaults.bool(forKey: migrationKey) == false else { return }
        defer { userDefaults.set(true, forKey: migrationKey) }

        let legacyKey = legacyScheduleKey(for: studentId)
        guard let data = userDefaults.data(forKey: legacyKey) else { return }
        do {
            let legacySchedule = try await Task.detached(priority: .utility) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(ScheduleData.self, from: data)
            }.value
            let grouped = Dictionary(grouping: legacySchedule.events) {
                ScheduleIdentity.weekKey(for: $0.date)
            }
            for (weekKey, events) in grouped {
                _ = try await persistWeekAsync(studentId: studentId, weekKey: weekKey, events: events)
            }
            userDefaults.removeObject(forKey: legacyKey)
        } catch {
            print("❌ Failed to migrate legacy schedule cache: \(error)")
        }
    }

    // MARK: - Delete

    func deleteSchedule(for studentId: String) {
        do {
            let descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId }
            )
            let records = try context.fetch(descriptor)
            for record in records {
                context.delete(record)
            }
            try context.save()
        } catch {
            print("❌ Failed deleting schedule for student \(studentId): \(error)")
        }

        userDefaults.removeObject(forKey: legacyScheduleKey(for: studentId))
        print("🗑️ Deleted schedule for student \(studentId)")
    }

    // MARK: - Check Last Updated

    func lastUpdated(for studentId: String) -> Date? {
        do {
            var descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.studentId == studentId },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first?.updatedAt
        } catch {
            print("❌ Failed to load last updated date: \(error)")
            return nil
        }
    }

    // MARK: - Staleness

    func isScheduleStale(for studentId: String, minutes: Int = 30) -> Bool {
        guard let lastUpdate = lastUpdated(for: studentId) else {
            return true
        }

        let staleDate = TimeProvider.now.addingTimeInterval(-Double(minutes * 60))
        return lastUpdate < staleDate
    }

    // MARK: - Clear

    func clearAllSchedules() {
        do {
            try context.delete(model: LessonRecord.self)
            try context.save()
        } catch {
            print("❌ Failed clearing schedules: \(error)")
        }

        let legacyKeys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(legacyKeyPrefix) }
        legacyKeys.forEach { userDefaults.removeObject(forKey: $0) }

        let migrationKeys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(migrationKeyPrefix) }
        migrationKeys.forEach { userDefaults.removeObject(forKey: $0) }

        print("🗑️ Cleared all cached schedules")
    }

    func clearAllSchedulesAsync() async {
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                try context.delete(model: LessonRecord.self)
                try context.save()
            } catch {
                print("❌ Failed clearing schedules: \(error)")
            }
        }.value
        let legacyKeys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(legacyKeyPrefix) }
        legacyKeys.forEach { userDefaults.removeObject(forKey: $0) }
        let migrationKeys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(migrationKeyPrefix) }
        migrationKeys.forEach { userDefaults.removeObject(forKey: $0) }
    }

    private func legacyScheduleKey(for studentId: String) -> String {
        "\(legacyKeyPrefix)\(studentId)"
    }

    private func migrationMarkerKey(for studentId: String) -> String {
        "\(migrationKeyPrefix)\(studentId)"
    }

    private nonisolated static func uniqueKey(studentId: String, lessonKey: String) -> String {
        "\(studentId)|\(lessonKey)"
    }

    private nonisolated static func apply(
        event: ScheduleEvent,
        to record: LessonRecord,
        studentId: String,
        lessonKey: String,
        syncedAt: Date
    ) {
        record.uniqueKey = Self.uniqueKey(studentId: studentId, lessonKey: lessonKey)
        record.studentId = studentId
        record.lessonKey = lessonKey
        record.eventId = event.id
        record.weekKey = ScheduleIdentity.weekKey(for: event.date)
        record.lessonDate = event.date
        record.startTime = event.startTime
        record.endTime = event.endTime
        record.title = event.title
        record.subtitle = event.subtitle
        record.teacher = event.teacher
        record.teacherId = event.teacherId
        record.room = event.room
        record.status = event.status.rawValue
        record.notes = event.notes
        record.homework = event.homework
        record.sourceUpdatedAt = syncedAt
        record.updatedAt = syncedAt
        record.isAllDay = event.isAllDay
    }

    private nonisolated static func toScheduleEvent(_ record: LessonRecord) -> ScheduleEvent {
        ScheduleEvent(
            id: record.eventId,
            title: record.title,
            subtitle: record.subtitle,
            startTime: record.startTime,
            endTime: record.endTime,
            teacher: record.teacher,
            teacherId: record.teacherId,
            room: record.room,
            status: EventStatus(rawValue: record.status) ?? .normal,
            date: record.lessonDate,
            notes: record.notes,
            homework: record.homework,
            // Defensive: pre-migration records have isAllDay=false but empty start/end.
            isAllDay: record.isAllDay || record.startTime.isEmpty
        )
    }
}
