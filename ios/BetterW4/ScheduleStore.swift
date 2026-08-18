//
//  ScheduleStore.swift
//  BetterW4
//
//  `Timetable.store` — the SwiftData home of parsed W4 lessons (features.md §2.1, plan Wave 5.1).
//
//  The page cache (`W4PageCache`) keeps the raw HTML so a screen can re-render the exact week it
//  last saw. This store exists for the questions HTML cannot answer cheaply: "what is my next
//  lesson", "which lessons changed since the last fetch", "show me every lesson this term". It is
//  written only by `TimetableRepository`.
//
//  Two rules govern writes:
//
//    * Rows are keyed on the **source-prefixed event id** (D-9). An Academics class 42 and an
//      Extra Academics group 42 are different lessons, and the merge in `W4TimetableParser` puts
//      both in the same week.
//    * Deleting is allowed only after a **successful parse of a real grid** (D-22), and only for
//      the sources that fetch actually covered. A half-rendered page, or a week where the EA
//      request failed, must never wipe lessons we still have good data for. `markMissingAsCancelled`
//      is gone with it: synthesising a "cancelled" lesson for every holiday is worse than useless.
//

import Foundation
import SwiftData

// MARK: - Record

/// One lesson occurrence. Columns follow `features.md` §2.1 verbatim.
///
/// Deliberately **not** stored: `attendance`, `href` and `rawTooltip`. They live in
/// `TimetableEvent` and survive in the cached HTML; this table is the queryable index, not the
/// lossless copy. Revisit when a term-time capture proves what a `.period` block actually carries.
@Model
final class LessonRecord {
    /// `"<uwcId>|<lessonKey>"` (`ScheduleIdentity.uniqueKey`).
    @Attribute(.unique) var uniqueKey: String
    /// The signed-in student's UWC id. Scope key for everything; there is no `gymId` in W4.
    var uwcId: String
    /// Equal to `eventId`: W4 event ids are stable and source-prefixed, so nothing is hashed.
    var lessonKey: String
    /// Source-prefixed W4 event id, e.g. `"ac-w4-42"` (D-9).
    var eventId: String
    /// `"2026-W33"` (`ScheduleIdentity.weekKey`).
    var weekKey: String
    /// Start of the Oslo day the lesson renders on.
    var lessonDate: Date
    /// Oslo instants. `nil` ⇒ all-day or unplaceable — no more magic empty strings.
    var startAt: Date?
    var endAt: Date?
    var title: String
    /// Canonical-ish label used for colour and rename lookups (was `subtitle`).
    var subject: String
    var teacher: String?
    /// `nc\d{2}[a-z]+` (was `teacherId`, which held a Lectio numeric id).
    var teacherUwcId: String?
    var room: String?
    /// `EventStatus` raw value.
    var status: String
    /// `EventSource` raw value — `academics`, `extraAcademics`, `schoolCalendar`, `local`.
    var source: String = EventSource.academics.rawValue
    /// `"Day 1"` … `"Day 5"` / `"Weekend"`, copied from the day column this lesson sat in.
    var rotationDay: String?
    var notes: String?
    var isAllDay: Bool = false
    /// When W4 produced this row, and when we last touched it. They drive staleness.
    var sourceUpdatedAt: Date
    var updatedAt: Date

    init(
        uniqueKey: String,
        uwcId: String,
        lessonKey: String,
        eventId: String,
        weekKey: String,
        lessonDate: Date,
        startAt: Date? = nil,
        endAt: Date? = nil,
        title: String,
        subject: String,
        teacher: String? = nil,
        teacherUwcId: String? = nil,
        room: String? = nil,
        status: String,
        source: String,
        rotationDay: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false,
        sourceUpdatedAt: Date,
        updatedAt: Date
    ) {
        self.uniqueKey = uniqueKey
        self.uwcId = uwcId
        self.lessonKey = lessonKey
        self.eventId = eventId
        self.weekKey = weekKey
        self.lessonDate = lessonDate
        self.startAt = startAt
        self.endAt = endAt
        self.title = title
        self.subject = subject
        self.teacher = teacher
        self.teacherUwcId = teacherUwcId
        self.room = room
        self.status = status
        self.source = source
        self.rotationDay = rotationDay
        self.notes = notes
        self.isAllDay = isAllDay
        self.sourceUpdatedAt = sourceUpdatedAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Snapshot

/// What the store can give back about one week without the HTML: the lessons, the rotation-day
/// label per Oslo day, and when the rows were last written.
///
/// `TimetableRepository` turns this into a `ScheduleWeek` when both the network and the page
/// cache are gone. It is lossy by design — `eaNote`, `attendance`, `href` and `rawTooltip` are
/// not columns — so it is the *last* fallback, never the first.
struct TimetableWeekSnapshot: Sendable {
    let weekKey: String
    let events: [TimetableEvent]
    /// Oslo start-of-day → `"Day 1"` … `"Weekend"`.
    let rotationDays: [Date: String]
    let updatedAt: Date

    var isEmpty: Bool { events.isEmpty }
}

// MARK: - Store

/// Local timetable storage backed by SwiftData.
///
/// `@MainActor` because the synchronous `deleteSchedule` shares the store's own `ModelContext`.
/// Every method that touches SQLite in bulk hops to a detached task with its **own**
/// `ModelContext` built from the (Sendable) `ModelContainer` — a `ModelContext` must never cross
/// an actor boundary (D-30).
@MainActor
class ScheduleStore {
    static let shared = ScheduleStore()

    private let container: ModelContainer
    private let context: ModelContext
    private let userDefaults = UserDefaults.standard

    /// Legacy Lectio-era UserDefaults cache. features.md §2.3 deletes the migration outright —
    /// there is no previous BetterW4 install to migrate from — so these prefixes exist only to be
    /// swept off disk once.
    private let legacyKeyPrefix = "w4.schedule."
    private let migrationKeyPrefix = "w4.schedule.migrated.v2."

    private init() {
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // features.md §2.1 names this file `Timetable.store`. The old `Schedule.store` held the
        // Lectio column set (studentId / startTime:String / homework); renaming rather than
        // migrating means a stale file can never be opened against the new schema, and there is
        // no shipped install whose data would be lost.
        let storeURL = storeDirectory.appendingPathComponent("Timetable.store")
        let config = ModelConfiguration(url: storeURL)
        do {
            // A dedicated store file, never `default.store`: two stores sharing one file with
            // different schemas produced "no such table: ZLESSONRECORD".
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

        Self.removeSQLiteStore(at: storeDirectory.appendingPathComponent("Schedule.store"))
        purgeLegacyDefaults()
    }

    private static func removeSQLiteStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: - W4 timetable (Wave 5.1)

    /// Every stored lesson of one ISO week, or `nil` when the week was never stored.
    func timetableWeek(uwcId: String, weekKey: String) async -> TimetableWeekSnapshot? {
        let container = container
        return await Task.detached(priority: .userInitiated) { () -> TimetableWeekSnapshot? in
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.uwcId == uwcId && $0.weekKey == weekKey },
                    sortBy: [SortDescriptor(\LessonRecord.lessonDate, order: .forward)]
                )
                let records = try context.fetch(descriptor)
                guard !records.isEmpty else { return nil }

                var rotationDays: [Date: String] = [:]
                for record in records {
                    guard let rotationDay = record.rotationDay, !rotationDay.isEmpty else { continue }
                    rotationDays[W4Dates.startOfDay(record.lessonDate)] = rotationDay
                }

                let events = records
                    .map(Self.toTimetableEvent)
                    .sorted(by: Self.eventIsOrderedBefore)

                return TimetableWeekSnapshot(
                    weekKey: weekKey,
                    events: events,
                    rotationDays: rotationDays,
                    updatedAt: records.map(\.updatedAt).max() ?? TimeProvider.now
                )
            } catch {
                print("❌ Failed to load stored week \(weekKey): \(error)")
                return nil
            }
        }.value
    }

    /// Upserts every lesson of `week`, then deletes the rows this fetch proved are gone.
    ///
    /// - Parameter replacingSources: the sources the fetch actually covered. Empty means
    ///   "upsert only, delete nothing" — which is what a half-rendered grid gets (D-22), and what
    ///   Extra Academics gets when its request failed while Academics succeeded.
    func persistTimetableWeek(
        _ week: ScheduleWeek,
        uwcId: String,
        weekKey: String,
        replacingSources: Set<EventSource>
    ) async {
        let container = container
        let events = week.allEvents
        let rotationByDay: [Date: String] = week.days.reduce(into: [:]) { result, day in
            guard let rotationDay = day.rotationDay, !rotationDay.isEmpty else { return }
            result[W4Dates.startOfDay(day.date)] = rotationDay
        }
        let replaceable = Set(replacingSources.map(\.rawValue))

        await Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let syncedAt = TimeProvider.now

                // Scoped to the student, not the week: a lesson that moved between weeks keeps
                // its id, and inserting a second row for it would collide on `uniqueKey`.
                let descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.uwcId == uwcId }
                )
                let existing = Dictionary(
                    try context.fetch(descriptor).map { ($0.uniqueKey, $0) },
                    uniquingKeysWith: { _, last in last }
                )

                var written: Set<String> = []
                for event in events {
                    let lessonKey = ScheduleIdentity.lessonKey(for: event)
                    let key = ScheduleIdentity.uniqueKey(uwcId: uwcId, lessonKey: lessonKey)
                    written.insert(key)
                    let rotationDay = rotationByDay[W4Dates.startOfDay(event.date)]

                    if let record = existing[key] {
                        Self.apply(
                            event: event,
                            to: record,
                            uwcId: uwcId,
                            weekKey: weekKey,
                            rotationDay: rotationDay,
                            syncedAt: syncedAt
                        )
                    } else {
                        context.insert(Self.makeRecord(
                            event: event,
                            uwcId: uwcId,
                            weekKey: weekKey,
                            rotationDay: rotationDay,
                            syncedAt: syncedAt
                        ))
                    }
                }

                // D-22: delete-on-successful-parse, never mark-as-cancelled, and only for the
                // sources this fetch actually saw.
                if !replaceable.isEmpty {
                    for (key, record) in existing
                    where record.weekKey == weekKey
                        && replaceable.contains(record.source)
                        && !written.contains(key) {
                        context.delete(record)
                    }
                }

                try context.save()
            } catch {
                print("❌ Failed to persist week \(weekKey): \(error)")
            }
        }.value
    }

    /// Drops every stored lesson for one student.
    func deleteTimetable(uwcId: String) async {
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.uwcId == uwcId }
                )
                for record in try context.fetch(descriptor) {
                    context.delete(record)
                }
                try context.save()
            } catch {
                print("❌ Failed deleting timetable for \(uwcId): \(error)")
            }
        }.value
    }

    // MARK: - Delete

    func deleteSchedule(for studentId: String) {
        do {
            let descriptor = FetchDescriptor<LessonRecord>(
                predicate: #Predicate { $0.uwcId == studentId }
            )
            for record in try context.fetch(descriptor) {
                context.delete(record)
            }
            try context.save()
        } catch {
            print("❌ Failed deleting schedule for student \(studentId): \(error)")
        }
        print("🗑️ Deleted schedule for student \(studentId)")
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
        purgeLegacyDefaults()
    }

    // MARK: - Staleness

    /// When the store last wrote a row for this student, or `nil` when it holds nothing.
    func lastUpdatedAsync(for uwcId: String) async -> Date? {
        let container = container
        return await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<LessonRecord>(
                    predicate: #Predicate { $0.uwcId == uwcId },
                    sortBy: [SortDescriptor(\LessonRecord.updatedAt, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                return try context.fetch(descriptor).first?.updatedAt
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Private

    private func purgeLegacyDefaults() {
        let keys = userDefaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(legacyKeyPrefix) || key.hasPrefix(migrationKeyPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    // MARK: - Mapping

    private nonisolated static func makeRecord(
        event: TimetableEvent,
        uwcId: String,
        weekKey: String,
        rotationDay: String?,
        syncedAt: Date
    ) -> LessonRecord {
        let lessonKey = ScheduleIdentity.lessonKey(for: event)
        return LessonRecord(
            uniqueKey: ScheduleIdentity.uniqueKey(uwcId: uwcId, lessonKey: lessonKey),
            uwcId: uwcId,
            lessonKey: lessonKey,
            eventId: event.id,
            weekKey: weekKey,
            lessonDate: W4Dates.startOfDay(event.date),
            startAt: event.start,
            endAt: event.end,
            title: event.title,
            subject: event.subject,
            teacher: event.teacher,
            teacherUwcId: event.teacherUwcId,
            room: event.room,
            status: event.status.rawValue,
            source: event.source.rawValue,
            rotationDay: rotationDay,
            notes: event.notes,
            isAllDay: event.isAllDay,
            sourceUpdatedAt: syncedAt,
            updatedAt: syncedAt
        )
    }

    private nonisolated static func apply(
        event: TimetableEvent,
        to record: LessonRecord,
        uwcId: String,
        weekKey: String,
        rotationDay: String?,
        syncedAt: Date
    ) {
        let lessonKey = ScheduleIdentity.lessonKey(for: event)
        record.uniqueKey = ScheduleIdentity.uniqueKey(uwcId: uwcId, lessonKey: lessonKey)
        record.uwcId = uwcId
        record.lessonKey = lessonKey
        record.eventId = event.id
        record.weekKey = weekKey
        record.lessonDate = W4Dates.startOfDay(event.date)
        record.startAt = event.start
        record.endAt = event.end
        record.title = event.title
        record.subject = event.subject
        record.teacher = event.teacher
        record.teacherUwcId = event.teacherUwcId
        record.room = event.room
        record.status = event.status.rawValue
        record.source = event.source.rawValue
        record.rotationDay = rotationDay
        record.notes = event.notes
        record.isAllDay = event.isAllDay
        record.sourceUpdatedAt = syncedAt
        record.updatedAt = syncedAt
    }

    private nonisolated static func toTimetableEvent(_ record: LessonRecord) -> TimetableEvent {
        TimetableEvent(
            id: record.eventId,
            title: record.title,
            subject: record.subject,
            source: EventSource(rawValue: record.source) ?? .academics,
            start: record.startAt,
            end: record.endAt,
            date: record.lessonDate,
            room: record.room,
            teacher: record.teacher,
            teacherUwcId: record.teacherUwcId,
            status: EventStatus(rawValue: record.status) ?? .normal,
            attendance: nil,
            isAllDay: record.isAllDay || record.startAt == nil,
            href: nil,
            notes: record.notes,
            rawTooltip: nil
        )
    }

    /// Chronological, all-day first, ties broken by title — the same order the parser produces.
    private nonisolated static func eventIsOrderedBefore(_ lhs: TimetableEvent, _ rhs: TimetableEvent) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        switch (lhs.start, rhs.start) {
        case let (left?, right?):
            return left == right ? lhs.title < rhs.title : left < right
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            return lhs.title < rhs.title
        }
    }
}
