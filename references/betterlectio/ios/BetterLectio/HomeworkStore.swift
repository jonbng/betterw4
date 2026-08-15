//
//  HomeworkStore.swift
//  BetterLectio
//

import Foundation
import SwiftData

struct LocalHomeworkDoneState: Sendable {
    let isDone: Bool
    let updatedAt: Date
}

@Model
final class HomeworkRecord {
    @Attribute(.unique) var uniqueKey: String // studentId + entryId
    var studentId: String
    var entryId: String
    var lessonDate: Date
    var displayDate: String
    var hold: String
    var title: String?
    var teacher: String?
    var room: String?
    var status: String
    var note: String?
    var itemsJSON: Data? // Encoded [HomeworkItem]
    
    var isDone: Bool
    var doneUpdatedAt: Date
    var sourceUpdatedAt: Date
    var updatedAt: Date

    init(
        uniqueKey: String,
        studentId: String,
        entryId: String,
        lessonDate: Date,
        displayDate: String,
        hold: String,
        title: String?,
        teacher: String?,
        room: String?,
        status: String,
        note: String?,
        itemsJSON: Data?,
        isDone: Bool = false,
        doneUpdatedAt: Date = .distantPast,
        sourceUpdatedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.uniqueKey = uniqueKey
        self.studentId = studentId
        self.entryId = entryId
        self.lessonDate = lessonDate
        self.displayDate = displayDate
        self.hold = hold
        self.title = title
        self.teacher = teacher
        self.room = room
        self.status = status
        self.note = note
        self.itemsJSON = itemsJSON
        self.isDone = isDone
        self.doneUpdatedAt = doneUpdatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.updatedAt = updatedAt
    }
}

/// Local homework storage backed by SwiftData.
@MainActor
class HomeworkStore {
    static let shared = HomeworkStore()
    private let container: ModelContainer
    private let context: ModelContext

    private init() {
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = storeDirectory.appendingPathComponent("Homework.store")
        let config = ModelConfiguration(url: storeURL)
        do {
            container = try ModelContainer(for: HomeworkRecord.self, configurations: config)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            print("⚠️ Failed to initialize HomeworkStore, rebuilding cache: \(error)")
            Self.removeSQLiteStore(at: storeURL)
            do {
                container = try ModelContainer(for: HomeworkRecord.self, configurations: config)
                context = ModelContext(container)
                context.autosaveEnabled = true
            } catch {
                print("⚠️ HomeworkStore recovery failed; using memory-only cache: \(error)")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    container = try ModelContainer(for: HomeworkRecord.self, configurations: memoryConfig)
                    context = ModelContext(container)
                    context.autosaveEnabled = true
                } catch {
                    fatalError("Failed to initialize even an in-memory HomeworkStore: \(error)")
                }
            }
        }
    }

    private static func removeSQLiteStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: - Upsert

    func upsertEntries(studentId: String, entries: [HomeworkEntry]) throws {
        let now = Date()
        let existingDescriptor = FetchDescriptor<HomeworkRecord>(
            predicate: #Predicate { $0.studentId == studentId }
        )
        var existingByKey = Dictionary(
            uniqueKeysWithValues: try context.fetch(existingDescriptor).map { ($0.uniqueKey, $0) }
        )

        for entry in entries {
            let uniqueKey = "\(studentId)|\(entry.id)"
            let itemsData = try? JSONEncoder().encode(entry.items)

            if let record = existingByKey.removeValue(forKey: uniqueKey) {
                record.lessonDate = entry.date
                record.displayDate = entry.displayDate
                record.hold = entry.hold
                record.title = entry.title
                record.teacher = entry.teacher
                record.room = entry.room
                record.status = entry.status.rawValue
                record.note = entry.note
                record.itemsJSON = itemsData
                record.sourceUpdatedAt = now
                record.updatedAt = now
            } else {
                let record = HomeworkRecord(
                    uniqueKey: uniqueKey,
                    studentId: studentId,
                    entryId: entry.id,
                    lessonDate: entry.date,
                    displayDate: entry.displayDate,
                    hold: entry.hold,
                    title: entry.title,
                    teacher: entry.teacher,
                    room: entry.room,
                    status: entry.status.rawValue,
                    note: entry.note,
                    itemsJSON: itemsData,
                    isDone: false,
                    doneUpdatedAt: .distantPast,
                    sourceUpdatedAt: now,
                    updatedAt: now
                )
                context.insert(record)
            }
        }
        // The overview is a server snapshot. Keeping rows that disappeared causes stale
        // homework to reappear whenever the next launch falls back to the local cache.
        for staleRecord in existingByKey.values {
            context.delete(staleRecord)
        }
        try context.save()
    }

    func replaceEntriesAsync(studentId: String, entries: [HomeworkEntry]) async throws {
        let container = container
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let now = TimeProvider.now
            let existingDescriptor = FetchDescriptor<HomeworkRecord>(
                predicate: #Predicate { $0.studentId == studentId }
            )
            var existingByKey = Dictionary(
                uniqueKeysWithValues: try context.fetch(existingDescriptor).map { ($0.uniqueKey, $0) }
            )

            for entry in entries {
                try Task.checkCancellation()
                let key = "\(studentId)|\(entry.id)"
                let itemsData = try? JSONEncoder().encode(entry.items)
                if let record = existingByKey.removeValue(forKey: key) {
                    record.lessonDate = entry.date
                    record.displayDate = entry.displayDate
                    record.hold = entry.hold
                    record.title = entry.title
                    record.teacher = entry.teacher
                    record.room = entry.room
                    record.status = entry.status.rawValue
                    record.note = entry.note
                    record.itemsJSON = itemsData
                    record.sourceUpdatedAt = now
                    record.updatedAt = now
                } else {
                    context.insert(HomeworkRecord(
                        uniqueKey: key,
                        studentId: studentId,
                        entryId: entry.id,
                        lessonDate: entry.date,
                        displayDate: entry.displayDate,
                        hold: entry.hold,
                        title: entry.title,
                        teacher: entry.teacher,
                        room: entry.room,
                        status: entry.status.rawValue,
                        note: entry.note,
                        itemsJSON: itemsData,
                        sourceUpdatedAt: now,
                        updatedAt: now
                    ))
                }
            }
            for record in existingByKey.values {
                context.delete(record)
            }
            try context.save()
        }.value
    }

    // MARK: - Done State

    func setDone(studentId: String, entryId: String, isDone: Bool, updatedAt: Date) throws {
        let uniqueKey = "\(studentId)|\(entryId)"
        var descriptor = FetchDescriptor<HomeworkRecord>(
            predicate: #Predicate { $0.uniqueKey == uniqueKey }
        )
        descriptor.fetchLimit = 1
        
        if let record = try context.fetch(descriptor).first {
            record.isDone = isDone
            record.doneUpdatedAt = updatedAt
            record.updatedAt = Date()
            try context.save()
        }
    }

    func setDoneAsync(studentId: String, entryId: String, isDone: Bool, updatedAt: Date) async {
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let key = "\(studentId)|\(entryId)"
                var descriptor = FetchDescriptor<HomeworkRecord>(
                    predicate: #Predicate { $0.uniqueKey == key }
                )
                descriptor.fetchLimit = 1
                guard let record = try context.fetch(descriptor).first else { return }
                record.isDone = isDone
                record.doneUpdatedAt = updatedAt
                record.updatedAt = TimeProvider.now
                try context.save()
            } catch {
                print("❌ Failed to save homework status: \(error)")
            }
        }.value
    }

    func isDone(studentId: String, entryId: String) -> Bool {
        let uniqueKey = "\(studentId)|\(entryId)"
        var descriptor = FetchDescriptor<HomeworkRecord>(
            predicate: #Predicate { $0.uniqueKey == uniqueKey }
        )
        descriptor.fetchLimit = 1
        
        return (try? context.fetch(descriptor).first?.isDone) ?? false
    }

    func getDoneStates(studentId: String, entryIds: [String]) -> [String: LocalHomeworkDoneState] {
        do {
            let descriptor = FetchDescriptor<HomeworkRecord>(
                predicate: #Predicate { $0.studentId == studentId }
            )
            let records = try context.fetch(descriptor)
            
            var map: [String: LocalHomeworkDoneState] = [:]
            let idSet = Set(entryIds)
            for record in records where idSet.contains(record.entryId) {
                map[record.entryId] = LocalHomeworkDoneState(
                    isDone: record.isDone,
                    updatedAt: record.doneUpdatedAt
                )
            }
            return map
        } catch {
            return [:]
        }
    }

    func getDoneStatesAsync(studentId: String, entryIds: [String]) async -> [String: LocalHomeworkDoneState] {
        let container = container
        return await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<HomeworkRecord>(
                    predicate: #Predicate { $0.studentId == studentId }
                )
                let idSet = Set(entryIds)
                return try context.fetch(descriptor).reduce(into: [:]) { result, record in
                    guard idSet.contains(record.entryId) else { return }
                    result[record.entryId] = LocalHomeworkDoneState(
                        isDone: record.isDone,
                        updatedAt: record.doneUpdatedAt
                    )
                }
            } catch {
                return [:]
            }
        }.value
    }
    
    /// Merges remote done states into local store.
    /// Newer `clientUpdatedAt` wins.
    func mergeRemoteDoneStates(studentId: String, remoteStates: [String: HomeworkSyncStatus]) throws {
        for (entryId, remote) in remoteStates {
            let uniqueKey = "\(studentId)|\(entryId)"
            var descriptor = FetchDescriptor<HomeworkRecord>(
                predicate: #Predicate { $0.uniqueKey == uniqueKey }
            )
            descriptor.fetchLimit = 1
            
            if let record = try context.fetch(descriptor).first {
                if remote.clientUpdatedAt > record.doneUpdatedAt {
                    record.isDone = remote.isDone
                    record.doneUpdatedAt = remote.clientUpdatedAt
                    record.updatedAt = Date()
                }
            }
        }
        try context.save()
    }

    func mergeRemoteDoneStatesAsync(studentId: String, remoteStates: [String: HomeworkSyncStatus]) async {
        guard !remoteStates.isEmpty else { return }
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<HomeworkRecord>(
                    predicate: #Predicate { $0.studentId == studentId }
                )
                let records = try context.fetch(descriptor)
                for record in records {
                    guard let remote = remoteStates[record.entryId],
                          remote.clientUpdatedAt > record.doneUpdatedAt else { continue }
                    record.isDone = remote.isDone
                    record.doneUpdatedAt = remote.clientUpdatedAt
                    record.updatedAt = TimeProvider.now
                }
                try context.save()
            } catch {
                print("❌ Failed to merge homework status: \(error)")
            }
        }.value
    }

    // MARK: - Load

    // MARK: - Clear

    /// Removes all locally cached homework rows (used by "Ryd cache").
    func clearAllHomework() {
        do {
            try context.delete(model: HomeworkRecord.self)
            try context.save()
            print("🗑️ Cleared all homework cache")
        } catch {
            print("❌ Failed to clear homework cache: \(error)")
        }
    }


    func clearAllHomeworkAsync() async {
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                try context.delete(model: HomeworkRecord.self)
                try context.save()
            } catch {
                print("❌ Failed to clear homework cache: \(error)")
            }
        }.value
    }

    // MARK: - Load

    func loadEntries(for studentId: String) -> [HomeworkEntry] {
        do {
            let descriptor = FetchDescriptor<HomeworkRecord>(
                predicate: #Predicate { $0.studentId == studentId },
                sortBy: [SortDescriptor(\.lessonDate)]
            )
            let records = try context.fetch(descriptor)
            return records.map { record in
                let items: [HomeworkItem] = {
                    if let data = record.itemsJSON {
                        return (try? JSONDecoder().decode([HomeworkItem].self, from: data)) ?? []
                    }
                    return []
                }()
                
                return HomeworkEntry(
                    id: record.entryId,
                    date: record.lessonDate,
                    displayDate: record.displayDate,
                    hold: record.hold,
                    title: record.title,
                    teacher: record.teacher,
                    room: record.room,
                    status: EventStatus(rawValue: record.status) ?? .normal,
                    note: record.note,
                    items: items
                )
            }
        } catch {
            return []
        }
    }


    func loadEntriesAsync(for studentId: String) async -> [HomeworkEntry] {
        let container = container
        return await Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<HomeworkRecord>(
                    predicate: #Predicate { $0.studentId == studentId },
                    sortBy: [SortDescriptor(\HomeworkRecord.lessonDate)]
                )
                return try context.fetch(descriptor).map(Self.toHomeworkEntry)
            } catch {
                return []
            }
        }.value
    }

    private nonisolated static func toHomeworkEntry(_ record: HomeworkRecord) -> HomeworkEntry {
        let items = record.itemsJSON.flatMap {
            try? JSONDecoder().decode([HomeworkItem].self, from: $0)
        } ?? []
        return HomeworkEntry(
            id: record.entryId,
            date: record.lessonDate,
            displayDate: record.displayDate,
            hold: record.hold,
            title: record.title,
            teacher: record.teacher,
            room: record.room,
            status: EventStatus(rawValue: record.status) ?? .normal,
            note: record.note,
            items: items
        )
    }
}
