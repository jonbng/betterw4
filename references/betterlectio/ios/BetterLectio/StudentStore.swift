//
//  StudentStore.swift
//  BetterLectio
//

import Foundation
import SwiftData

@Model
final class StudentRecord {
    @Attribute(.unique) var uniqueKey: String
    var studentId: String
    var name: String
    @Attribute(originalName: "className") var classLabel: String
    var classNumber: String
    var gymId: Int
    var pictureId: String?
    var isTeacher: Bool = false
    var rawEntityType: String = DropdownEntityType.student.rawValue
    var lastFetched: Date

    var entityType: DropdownEntityType {
        DropdownEntityType(rawValue: rawEntityType) ?? (isTeacher ? .teacher : .student)
    }

    init(
        uniqueKey: String,
        studentId: String,
        name: String,
        classLabel: String,
        classNumber: String,
        gymId: Int,
        pictureId: String? = nil,
        isTeacher: Bool = false,
        lastFetched: Date,
        type: DropdownEntityType = .student
    ) {
        self.uniqueKey = uniqueKey
        self.studentId = studentId
        self.name = name
        self.classLabel = classLabel
        self.classNumber = classNumber
        self.gymId = gymId
        self.pictureId = pictureId
        self.isTeacher = isTeacher
        self.lastFetched = lastFetched
        self.rawEntityType = type.rawValue
    }
}

/// Local student storage backed by SwiftData.
@MainActor
class StudentStore {
    static let shared = StudentStore()
    private let container: ModelContainer
    private let context: ModelContext

    private init() {
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = storeDirectory.appendingPathComponent("Students.store")
        let config = ModelConfiguration(url: storeURL)
        
        do {
            container = try ModelContainer(for: StudentRecord.self, configurations: config)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            print("⚠️ Failed to initialize StudentStore with Students.store, attempting recovery: \(error)")
            // Fallback: delete the cache and its SQLite sidecars, then try once more.
            Self.removeSQLiteStore(at: storeURL)
            do {
                container = try ModelContainer(for: StudentRecord.self, configurations: config)
                context = ModelContext(container)
                context.autosaveEnabled = true
            } catch {
                print("⚠️ StudentStore recovery failed; using memory-only cache: \(error)")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    container = try ModelContainer(for: StudentRecord.self, configurations: memoryConfig)
                    context = ModelContext(container)
                    context.autosaveEnabled = true
                } catch {
                    fatalError("Failed to initialize even an in-memory StudentStore: \(error)")
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

    /// Loads all cached students for a school.
    func loadStudents(for gymId: Int) -> [StudentEntry] {
        do {
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId },
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            return try context.fetch(descriptor).map(Self.toStudentEntry)
        } catch {
            print("❌ Failed to load cached students: \(error)")
            return []
        }
    }

    /// Checks if we have any cached students for a school.
    func hasCachedStudents(for gymId: Int) -> Bool {
        do {
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            descriptor.fetchLimit = 1
            return try !context.fetch(descriptor).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Upsert

    /// Upserts a batch of students from a single letter fetch.
    func upsertStudents(_ students: [StudentEntry]) throws {
        let now = TimeProvider.now
        for student in students {
            let key = "\(student.studentId)_\(student.gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1

            if let record = try context.fetch(descriptor).first {
                record.name = student.name
                record.classLabel = student.classLabel
                record.classNumber = student.classNumber
                record.isTeacher = student.isTeacher
                record.rawEntityType = student.type.rawValue
                record.lastFetched = now
            } else {
                let record = StudentRecord(
                    uniqueKey: key,
                    studentId: student.studentId,
                    name: student.name,
                    classLabel: student.classLabel,
                    classNumber: student.classNumber,
                    gymId: student.gymId,
                    isTeacher: student.isTeacher,
                    lastFetched: now,
                    type: student.type
                )
                context.insert(record)
            }
        }
        try context.save()
    }

    // MARK: - Picture ID

    /// Saves a picture ID for a student or teacher.
    /// Creates a minimal record if one doesn't already exist (e.g. for teachers from messages).
    func savePictureId(_ pictureId: String, for studentId: String, gymId: Int) {
        do {
            let key = "\(studentId)_\(gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1

            if let record = try context.fetch(descriptor).first {
                record.pictureId = pictureId
            } else {
                let record = StudentRecord(
                    uniqueKey: key,
                    studentId: studentId,
                    name: "",
                    classLabel: "",
                    classNumber: "",
                    gymId: gymId,
                    pictureId: pictureId,
                    lastFetched: Date()
                )
                context.insert(record)
            }
            try context.save()
        } catch {
            print("❌ Failed to save picture ID: \(error)")
        }
    }

    /// Bulk saves picture IDs for multiple students.
    func savePictureIds(_ mapping: [String: String], gymId: Int) {
        guard !mapping.isEmpty else { return }
        do {
            var updatedCount = 0
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            let recordsByStudentID = Dictionary(
                uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.studentId, $0) }
            )
            for (studentId, pictureId) in mapping {
                if let record = recordsByStudentID[studentId], record.pictureId == nil {
                    record.pictureId = pictureId
                    updatedCount += 1
                }
            }
            try context.save()
            print("🖼️ Bulk saved \(updatedCount) picture IDs (out of \(mapping.count) in mapping)")
        } catch {
            print("❌ Failed to bulk save picture IDs: \(error)")
        }
    }

    /// Loads the picture ID for a student (if cached).
    func loadPictureId(for studentId: String, gymId: Int) -> String? {
        do {
            let key = "\(studentId)_\(gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first?.pictureId
        } catch {
            return nil
        }
    }

    /// Loads the picture ID for a student by matching their name.
    /// Strips trailing parenthetical (class label) before matching.
    func loadPictureIdByName(_ name: String, gymId: Int) -> String? {
        guard let cleanName = cleanNameForLookup(name) else { return nil }
        do {
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId && $0.pictureId != nil }
            )
            let records = try context.fetch(descriptor)
            let lowered = cleanName.lowercased()
            return records.first { $0.name.lowercased() == lowered }?.pictureId
        } catch {
            return nil
        }
    }

    /// Loads person ID and isTeacher by matching their name in cached records.
    /// Used when we only have the name (e.g. message sender without data-lectiocontextcard).
    func loadPersonIdByName(_ name: String, gymId: Int) -> (personId: String, isTeacher: Bool)? {
        guard let cleanName = cleanNameForLookup(name) else { return nil }
        do {
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            let records = try context.fetch(descriptor)
            let lowered = cleanName.lowercased()
            guard let record = records.first(where: { $0.name.lowercased() == lowered }) else {
                return nil
            }
            return (record.studentId, record.isTeacher)
        } catch {
            return nil
        }
    }

    private func cleanNameForLookup(_ name: String) -> String? {
        var cleanName: String
        if let parenRange = name.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleanName = String(name[name.startIndex..<parenRange.lowerBound])
        } else {
            cleanName = name
        }
        if cleanName.hasSuffix("(k)") {
            cleanName = String(cleanName.dropLast(3)).trimmingCharacters(in: .whitespaces)
        }
        let trimmed = cleanName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Logged-in Student Info

    /// Saves picture ID and class label for the logged-in student.
    /// Creates a record if it doesn't exist (for the logged-in student who may not be in the dropdown).
    func saveLoggedInStudentInfo(pictureId: String?, classLabel: String?, for studentId: String, gymId: Int) {
        guard pictureId != nil || classLabel != nil else { return }
        do {
            let key = "\(studentId)_\(gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1

            if let record = try context.fetch(descriptor).first {
                // Update existing record
                if let pictureId = pictureId {
                    record.pictureId = pictureId
                }
                if let classLabel = classLabel {
                    record.classLabel = classLabel
                }
                record.lastFetched = Date()
            } else {
                // Create new record for logged-in student
                let key = "\(studentId)_\(gymId)"
                let newRecord = StudentRecord(
                    uniqueKey: key,
                    studentId: studentId,
                    name: "", // Will be filled in from other sources if needed
                    classLabel: classLabel ?? "",
                    classNumber: "",
                    gymId: gymId,
                    pictureId: pictureId,
                    isTeacher: false,
                    lastFetched: Date()
                )
                context.insert(newRecord)
            }
            try context.save()
            print("💾 Saved logged-in student info - pictureId: \(pictureId ?? "nil"), classLabel: \(classLabel ?? "nil")")
        } catch {
            print("❌ Failed to save logged-in student info: \(error)")
        }
    }

    /// Loads the complete student info for a student (pictureId and classLabel).
    func loadStudentInfo(for studentId: String, gymId: Int) -> (pictureId: String?, classLabel: String?)? {
        do {
            let key = "\(studentId)_\(gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else { return nil }
            return (record.pictureId, record.classLabel)
        } catch {
            return nil
        }
    }

    // MARK: - Clear

    /// Clears all student records from the cache and search-related metadata
    func clearAllStudents() {
        do {
            try context.delete(model: StudentRecord.self)
            try context.save()
            print("🗑️ Cleared all student cache")
        } catch {
            print("❌ Failed to clear all students: \(error)")
        }

        // Clear search-related UserDefaults
        let defaults = UserDefaults.standard
        let pinnedPrefix = "lectio.pinnedFriends."
        let holdPrefix = "lectio.fetchedHoldIds."

        let keysToClear = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(pinnedPrefix) || $0.hasPrefix(holdPrefix)
        }

        for key in keysToClear {
            defaults.removeObject(forKey: key)
        }
        
        if !keysToClear.isEmpty {
            print("🗑️ Cleared \(keysToClear.count) search-related persistent keys")
        }
    }

    func clearAllStudentsAsync() async {
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                try context.delete(model: StudentRecord.self)
                try context.save()
            } catch {
                print("❌ Failed to clear all students: \(error)")
            }
        }.value

        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("lectio.pinnedFriends.") || $0.hasPrefix("lectio.fetchedHoldIds.")
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    func clearStudents(for gymId: Int) {
        do {
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            let records = try context.fetch(descriptor)
            for record in records {
                context.delete(record)
            }
            try context.save()
        } catch {
            print("❌ Failed to clear students: \(error)")
        }
    }

    // MARK: - Fetch Picture ID (Network)

    private var fetchingIds: Set<String> = []

    /// Fetches and caches a picture ID from Lectio if not already stored.
    /// Uses `laererid=` for teachers, `elevid=` for students.
    func fetchPictureIdIfNeeded(
        personId: String,
        gymId: Int,
        isTeacher: Bool,
        authenticatedStudentId: String,
        personName: String? = nil
    ) async {
        // Demo mode: never fetch pictures.
        if authenticatedStudentId == Student.demoStudentId { return }

        // Already cached
        if loadPictureId(for: personId, gymId: gymId) != nil { return }

        // Prevent duplicate fetches
        guard !fetchingIds.contains(personId) else { return }
        fetchingIds.insert(personId)
        defer { fetchingIds.remove(personId) }

        let keychainManager = KeychainManager.shared
        guard let credentials = keychainManager.loadCredentials(for: authenticatedStudentId) else { return }

        do {
            let httpClient = LectioHTTPClient()

            let html = try await httpClient.fetchStudentPage(
                credentials: credentials,
                studentId: authenticatedStudentId,
                schoolId: gymId,
                targetStudentId: personId,
                isTeacher: isTeacher,
                personName: personName ?? personId
            )

            if let pictureId = await Task.detached(priority: .utility, operation: {
                StudentParser.parseStudentPictureId(from: html)
            }).value {
                savePictureId(pictureId, for: personId, gymId: gymId)
            }
        } catch {
            let label = personName ?? personId
            print("⚠️ Failed to fetch picture for \(label): \(error.localizedDescription)")
        }
    }

    // MARK: - Conversion

    private static func toStudentEntry(_ record: StudentRecord) -> StudentEntry {
        StudentEntry(
            studentId: record.studentId,
            name: record.name,
            classLabel: record.classLabel,
            classNumber: record.classNumber,
            gymId: record.gymId,
            type: record.entityType
        )
    }
}
