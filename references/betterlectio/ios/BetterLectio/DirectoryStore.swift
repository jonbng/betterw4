//
//  DirectoryStore.swift
//  BetterLectio
//

import Foundation
import SwiftData

@Model
final class DirectoryEntityRecord {
    @Attribute(.unique) var uniqueKey: String
    var gymId: Int
    var kindRaw: String
    var rawPrefixedID: String
    var rawPrefix: String
    var numericID: String
    var name: String
    var subtitle: String?
    var rawLabel: String
    var normalizedName: String
    var searchTokensData: Data
    var isActive: Bool
    var rawTypeMarker: String?
    var metadataData: Data
    var pictureID: String?
    var lastFetched: Date

    init(entity: DirectoryEntity, pictureID: String? = nil, lastFetched: Date) {
        self.uniqueKey = entity.id
        self.gymId = entity.gymId
        self.kindRaw = entity.kind.rawValue
        self.rawPrefixedID = entity.rawPrefixedID
        self.rawPrefix = entity.rawPrefix
        self.numericID = entity.numericID
        self.name = entity.name
        self.subtitle = entity.subtitle
        self.rawLabel = entity.rawLabel
        self.normalizedName = entity.normalizedName
        self.searchTokensData = (try? JSONEncoder().encode(entity.searchTokens)) ?? Data()
        self.isActive = entity.isActive
        self.rawTypeMarker = entity.rawTypeMarker
        self.metadataData = (try? JSONEncoder().encode(entity.metadata)) ?? Data()
        self.pictureID = pictureID
        self.lastFetched = lastFetched
    }
}

@Model
final class DirectoryMembershipRecord {
    @Attribute(.unique) var uniqueKey: String
    var parentKey: String
    var memberKey: String
    var lastFetched: Date

    init(parentKey: String, memberKey: String, lastFetched: Date) {
        self.uniqueKey = "\(parentKey)|\(memberKey)"
        self.parentKey = parentKey
        self.memberKey = memberKey
        self.lastFetched = lastFetched
    }
}

@MainActor
final class DirectoryStore {
    static let shared = DirectoryStore()

    private let container: ModelContainer
    private let context: ModelContext
    private let keychainManager = KeychainManager.shared
    private var fetchingAvatarKeys: Set<String> = []
    private var pictureIDCache: [String: String] = [:]
    private var entityCacheByID: [String: DirectoryEntity] = [:]
    private var peopleByNormalizedNameByGym: [Int: [String: DirectoryEntity]] = [:]
    private var membershipCountsByGym: [Int: [String: Int]] = [:]

    private init() {
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = storeDirectory.appendingPathComponent("Directory.store")
        let config = ModelConfiguration(url: storeURL)

        do {
            container = try ModelContainer(
                for: DirectoryEntityRecord.self,
                DirectoryMembershipRecord.self,
                configurations: config
            )
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            print("⚠️ Failed to initialize DirectoryStore, attempting recovery: \(error)")
            Self.removeSQLiteStore(at: storeURL)
            do {
                container = try ModelContainer(
                    for: DirectoryEntityRecord.self,
                    DirectoryMembershipRecord.self,
                    configurations: config
                )
                context = ModelContext(container)
                context.autosaveEnabled = true
            } catch {
                print("⚠️ DirectoryStore recovery failed; using memory-only cache: \(error)")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    container = try ModelContainer(
                        for: DirectoryEntityRecord.self,
                        DirectoryMembershipRecord.self,
                        configurations: memoryConfig
                    )
                    context = ModelContext(container)
                    context.autosaveEnabled = true
                } catch {
                    fatalError("Failed to initialize even an in-memory DirectoryStore: \(error)")
                }
            }
        }
    }

    private static func removeSQLiteStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: - Snapshot

    func replaceDirectorySnapshot(gymId: Int, entities: [DirectoryEntity]) async throws {
        let container = container
        let membershipCounts = try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let now = TimeProvider.now
            let incomingKeys = Set(entities.map(\.id))

            let descriptor = FetchDescriptor<DirectoryEntityRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            let records = try context.fetch(descriptor)
            var recordsByKey = records.reduce(into: [:]) { result, record in
                result[record.uniqueKey] = record
            }

            for entity in entities {
                if let record = recordsByKey.removeValue(forKey: entity.id) {
                    Self.apply(entity, to: record, lastFetched: now)
                } else {
                    context.insert(DirectoryEntityRecord(entity: entity, lastFetched: now))
                }
            }

            for record in records where !incomingKeys.contains(record.uniqueKey) {
                context.delete(record)
            }

            let memberships = try context.fetch(FetchDescriptor<DirectoryMembershipRecord>())
            let gymPrefix = "\(gymId)|"
            var counts: [String: Int] = [:]
            for membership in memberships
                where membership.parentKey.hasPrefix(gymPrefix)
                    && (!incomingKeys.contains(membership.parentKey) || !incomingKeys.contains(membership.memberKey)) {
                context.delete(membership)
            }
            for membership in memberships
                where membership.parentKey.hasPrefix(gymPrefix)
                    && incomingKeys.contains(membership.parentKey) && incomingKeys.contains(membership.memberKey) {
                counts[membership.parentKey, default: 0] += 1
            }
            try context.save()
            return counts
        }.value
        membershipCountsByGym[gymId] = membershipCounts
    }

    func ensureEntity(_ entity: DirectoryEntity) {
        do {
            try upsertEntity(entity, lastFetched: TimeProvider.now)
            try context.save()
            entityCacheByID[entity.id] = entity
            if entity.isPerson {
                peopleByNormalizedNameByGym[entity.gymId, default: [:]][normalizedLookupName(entity.name)] = entity
            }
        } catch {
            print("❌ Failed to ensure directory entity: \(error)")
        }
    }

    /// Inserts the entity only if no record with that key exists yet.
    /// Existing records are left untouched, preserving richer data from the full directory sync.
    private func insertEntityIfMissing(_ entity: DirectoryEntity, lastFetched: Date) throws {
        var descriptor = FetchDescriptor<DirectoryEntityRecord>(
            predicate: #Predicate { $0.uniqueKey == entity.id }
        )
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(DirectoryEntityRecord(entity: entity, lastFetched: lastFetched))
    }

    private func upsertEntity(_ entity: DirectoryEntity, lastFetched: Date) throws {
        var descriptor = FetchDescriptor<DirectoryEntityRecord>(
            predicate: #Predicate { $0.uniqueKey == entity.id }
        )
        descriptor.fetchLimit = 1

        if let record = try context.fetch(descriptor).first {
            Self.apply(entity, to: record, lastFetched: lastFetched)
        } else {
            context.insert(DirectoryEntityRecord(entity: entity, lastFetched: lastFetched))
        }
    }

    /// Copies directory fields while preserving the separately fetched profile picture ID.
    private nonisolated static func apply(_ entity: DirectoryEntity, to record: DirectoryEntityRecord, lastFetched: Date) {
        record.kindRaw = entity.kind.rawValue
        record.rawPrefixedID = entity.rawPrefixedID
        record.rawPrefix = entity.rawPrefix
        record.numericID = entity.numericID
        record.name = entity.name
        record.subtitle = entity.subtitle
        record.rawLabel = entity.rawLabel
        record.normalizedName = entity.normalizedName
        record.searchTokensData = (try? JSONEncoder().encode(entity.searchTokens)) ?? Data()
        record.isActive = entity.isActive
        record.rawTypeMarker = entity.rawTypeMarker
        record.metadataData = (try? JSONEncoder().encode(entity.metadata)) ?? Data()
        // Preserve pictureID, which is populated independently from directory snapshots.
        record.lastFetched = lastFetched
    }

    // MARK: - Load

    func loadEntities(for gymId: Int, includeInactive: Bool = false) -> [DirectoryEntity] {
        do {
            // Use a fresh context so a just-finished background snapshot save is visible
            // immediately, without relying on merge timing in the long-lived UI context.
            let readContext = ModelContext(container)
            let descriptor = FetchDescriptor<DirectoryEntityRecord>(
                predicate: #Predicate { $0.gymId == gymId },
                sortBy: [
                    SortDescriptor(\.kindRaw, order: .forward),
                    SortDescriptor(\.name, order: .forward)
                ]
            )

            let records = try readContext.fetch(descriptor)
            for record in records {
                if let pictureID = record.pictureID {
                    pictureIDCache[record.uniqueKey] = pictureID
                }
            }
            let entities = records.compactMap(Self.toEntity).filter { includeInactive || $0.isActive }
            cacheEntities(entities, gymId: gymId)
            return entities
        } catch {
            print("❌ Failed to load directory entities: \(error)")
            return []
        }
    }

    /// Fetches and decodes the potentially large directory snapshot away from the UI actor.
    func loadEntitiesAsync(for gymId: Int, includeInactive: Bool = false) async -> [DirectoryEntity] {
        let container = container
        let result: (
            entities: [DirectoryEntity],
            pictures: [String: String],
            membershipCounts: [String: Int]
        ) = await Task.detached(priority: .userInitiated) { () -> (
            entities: [DirectoryEntity],
            pictures: [String: String],
            membershipCounts: [String: Int]
        ) in
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.gymId == gymId },
                    sortBy: [
                        SortDescriptor(\DirectoryEntityRecord.kindRaw, order: .forward),
                        SortDescriptor(\DirectoryEntityRecord.name, order: .forward)
                    ]
                )
                let records = try context.fetch(descriptor)
                var pictures: [String: String] = [:]
                let entities = records.compactMap { record -> DirectoryEntity? in
                    if let pictureID = record.pictureID {
                        pictures[record.uniqueKey] = pictureID
                    }
                    guard includeInactive || record.isActive else { return nil }
                    return Self.toEntity(record)
                }
                let membershipRecords = try context.fetch(FetchDescriptor<DirectoryMembershipRecord>())
                let prefix = "\(gymId)|"
                let membershipCounts: [String: Int] = membershipRecords.reduce(into: [:]) { counts, membership in
                    guard membership.parentKey.hasPrefix(prefix) else { return }
                    counts[membership.parentKey, default: 0] += 1
                }
                return (
                    entities: entities,
                    pictures: pictures,
                    membershipCounts: membershipCounts
                )
            } catch {
                print("❌ Failed to load directory entities: \(error)")
                return (entities: [], pictures: [:], membershipCounts: [:])
            }
        }.value
        pictureIDCache.merge(result.pictures) { _, newest in newest }
        membershipCountsByGym[gymId] = result.membershipCounts
        cacheEntities(result.entities, gymId: gymId)
        return result.entities
    }

    func loadEntity(id: DirectoryEntityID) -> DirectoryEntity? {
        loadEntity(uniqueKey: id.key)
    }

    func loadEntity(uniqueKey: String) -> DirectoryEntity? {
        if let cached = entityCacheByID[uniqueKey] { return cached }
        do {
            var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                predicate: #Predicate { $0.uniqueKey == uniqueKey }
            )
            descriptor.fetchLimit = 1
            guard let entity = try context.fetch(descriptor).compactMap(Self.toEntity).first else { return nil }
            entityCacheByID[uniqueKey] = entity
            return entity
        } catch {
            return nil
        }
    }

    func activeStudents(inClassCode classCode: String, gymId: Int) -> [DirectoryEntity] {
        loadEntities(for: gymId)
            .filter { $0.kind == .student && $0.isActive && $0.classCode?.caseInsensitiveCompare(classCode) == .orderedSame }
            .sorted { $0.name < $1.name }
    }

    func memberEntitiesAsync(for parent: DirectoryEntity) async -> [DirectoryEntity] {
        let container = container
        return await Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                let parentID = parent.id
                let gymID = parent.gymId
                let descriptor = FetchDescriptor<DirectoryMembershipRecord>(
                    predicate: #Predicate { $0.parentKey == parentID }
                )
                let memberships = try context.fetch(descriptor)
                try Task.checkCancellation()
                let memberKeys = Set(memberships.map(\.memberKey))
                guard !memberKeys.isEmpty else { return [] }

                let entityDescriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.gymId == gymID }
                )
                return try context.fetch(entityDescriptor)
                    .filter { memberKeys.contains($0.uniqueKey) }
                    .compactMap(Self.toEntity)
                    .sorted { lhs, rhs in
                        if lhs.kind == rhs.kind {
                            return lhs.name < rhs.name
                        }
                        return lhs.kind.rawValue < rhs.kind.rawValue
                    }
            } catch is CancellationError {
                return []
            } catch {
                print("❌ Failed to load directory memberships: \(error)")
                return []
            }
        }.value
    }

    func memberCount(for parent: DirectoryEntity) -> Int {
        if let cached = membershipCountsByGym[parent.gymId] { return cached[parent.id] ?? 0 }
        do {
            let descriptor = FetchDescriptor<DirectoryMembershipRecord>(
                predicate: #Predicate { $0.parentKey == parent.id }
            )
            return try context.fetchCount(descriptor)
        } catch {
            return 0
        }
    }

    /// Loads all membership counts in one fetch so directory grids do not issue one
    /// SwiftData query per visible class/hold during SwiftUI body evaluation.
    func memberCounts(gymId: Int) -> [String: Int] {
        if let cached = membershipCountsByGym[gymId] { return cached }
        do {
            let memberships = try context.fetch(FetchDescriptor<DirectoryMembershipRecord>())
            let prefix = "\(gymId)|"
            let counts: [String: Int] = memberships.reduce(into: [:]) { counts, membership in
                guard membership.parentKey.hasPrefix(prefix) else { return }
                counts[membership.parentKey, default: 0] += 1
            }
            membershipCountsByGym[gymId] = counts
            return counts
        } catch {
            print("❌ Failed to load directory membership counts: \(error)")
            return [:]
        }
    }

    func cachedMemberCounts(gymId: Int) -> [String: Int] {
        membershipCountsByGym[gymId] ?? [:]
    }

    func replaceMembers(for parent: DirectoryEntity, members: [ParsedHoldMember]) {
        let now = TimeProvider.now

        do {
            let memberEntities = members.map(\.entity)
            for parsed in members {
                try insertEntityIfMissing(parsed.entity, lastFetched: now)
                if let pictureID = parsed.pictureID {
                    savePictureID(pictureID, for: parsed.entity.entityID)
                }
            }

            let existingDescriptor = FetchDescriptor<DirectoryMembershipRecord>(
                predicate: #Predicate { $0.parentKey == parent.id }
            )
            let existing = try context.fetch(existingDescriptor)
            let incomingKeys = Set(memberEntities.map(\.id))

            for membership in existing where !incomingKeys.contains(membership.memberKey) {
                context.delete(membership)
            }

            let existingKeys = Set(existing.map(\.uniqueKey))
            for member in memberEntities where !existingKeys.contains("\(parent.id)|\(member.id)") {
                context.insert(DirectoryMembershipRecord(parentKey: parent.id, memberKey: member.id, lastFetched: now))
            }

            try context.save()
            membershipCountsByGym[parent.gymId, default: [:]][parent.id] = incomingKeys.count
        } catch {
            print("❌ Failed to replace directory members: \(error)")
        }
    }

    func replaceMembersAsync(for parent: DirectoryEntity, members: [ParsedHoldMember]) async {
        let container = container
        let result: (count: Int, pictures: [String: String])? = await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                let now = TimeProvider.now
                let gymID = parent.gymId
                let entityDescriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.gymId == gymID }
                )
                var recordsByKey = Dictionary(
                    uniqueKeysWithValues: try context.fetch(entityDescriptor).map { ($0.uniqueKey, $0) }
                )
                var pictures: [String: String] = [:]

                for parsed in members {
                    try Task.checkCancellation()
                    let entity = parsed.entity
                    let record: DirectoryEntityRecord
                    if let existing = recordsByKey[entity.id] {
                        record = existing
                    } else {
                        let inserted = DirectoryEntityRecord(entity: entity, lastFetched: now)
                        context.insert(inserted)
                        recordsByKey[entity.id] = inserted
                        record = inserted
                    }
                    if let pictureID = parsed.pictureID {
                        record.pictureID = pictureID
                        record.lastFetched = now
                        pictures[entity.id] = pictureID
                    }
                }

                let parentID = parent.id
                let membershipDescriptor = FetchDescriptor<DirectoryMembershipRecord>(
                    predicate: #Predicate { $0.parentKey == parentID }
                )
                let existingMemberships = try context.fetch(membershipDescriptor)
                let incomingKeys = Set(members.map(\.entity.id))
                let existingKeys = Set(existingMemberships.map(\.memberKey))

                for membership in existingMemberships where !incomingKeys.contains(membership.memberKey) {
                    context.delete(membership)
                }
                for memberKey in incomingKeys where !existingKeys.contains(memberKey) {
                    context.insert(DirectoryMembershipRecord(
                        parentKey: parentID,
                        memberKey: memberKey,
                        lastFetched: now
                    ))
                }
                try context.save()
                return (incomingKeys.count, pictures)
            } catch is CancellationError {
                return nil
            } catch {
                print("❌ Failed to replace directory members: \(error)")
                return nil
            }
        }.value

        guard let result, !Task.isCancelled else { return }
        pictureIDCache.merge(result.pictures) { _, newest in newest }
        membershipCountsByGym[parent.gymId, default: [:]][parent.id] = result.count
    }

    // MARK: - Avatar / Name Resolution

    func savePictureID(_ pictureID: String, for entityID: DirectoryEntityID) {
        pictureIDCache[entityID.key] = pictureID
        do {
            var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                predicate: #Predicate { $0.uniqueKey == entityID.key }
            )
            descriptor.fetchLimit = 1

            if let record = try context.fetch(descriptor).first {
                record.pictureID = pictureID
                record.lastFetched = TimeProvider.now
            } else {
                let fallback = DirectoryEntity(
                    entityID: entityID,
                    gymId: entityID.gymId,
                    kind: entityID.kind,
                    rawPrefixedID: entityID.rawID,
                    rawPrefix: String(entityID.rawID.prefix { !$0.isNumber }),
                    numericID: String(entityID.rawID.drop { !$0.isNumber }),
                    name: "",
                    subtitle: nil,
                    rawLabel: "",
                    normalizedName: "",
                    searchTokens: [],
                    isActive: true,
                    rawTypeMarker: nil,
                    metadata: DirectoryMetadata()
                )
                context.insert(DirectoryEntityRecord(entity: fallback, pictureID: pictureID, lastFetched: TimeProvider.now))
            }

            try context.save()
        } catch {
            print("❌ Failed to save picture ID: \(error)")
        }
    }

    func loadPictureID(for entityID: DirectoryEntityID) -> String? {
        if let cached = pictureIDCache[entityID.key] {
            return cached
        }
        do {
            var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                predicate: #Predicate { $0.uniqueKey == entityID.key }
            )
            descriptor.fetchLimit = 1
            let pictureID = try context.fetch(descriptor).first?.pictureID
            if let pictureID {
                pictureIDCache[entityID.key] = pictureID
            }
            return pictureID
        } catch {
            return nil
        }
    }

    func loadPictureIDAsync(for entityID: DirectoryEntityID) async -> String? {
        if let cached = pictureIDCache[entityID.key] { return cached }
        let container = container
        let key = entityID.key
        let pictureID = await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.uniqueKey == key }
                )
                descriptor.fetchLimit = 1
                return try context.fetch(descriptor).first?.pictureID
            } catch {
                return nil
            }
        }.value
        guard !Task.isCancelled else { return nil }
        if let pictureID { pictureIDCache[key] = pictureID }
        return pictureID
    }

    func savePictureIDAsync(_ pictureID: String, for entityID: DirectoryEntityID) async {
        pictureIDCache[entityID.key] = pictureID
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let key = entityID.key
                var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.uniqueKey == key }
                )
                descriptor.fetchLimit = 1
                if let record = try context.fetch(descriptor).first {
                    record.pictureID = pictureID
                    record.lastFetched = TimeProvider.now
                } else {
                    let fallback = DirectoryEntity(
                        entityID: entityID,
                        gymId: entityID.gymId,
                        kind: entityID.kind,
                        rawPrefixedID: entityID.rawID,
                        rawPrefix: String(entityID.rawID.prefix { !$0.isNumber }),
                        numericID: String(entityID.rawID.drop { !$0.isNumber }),
                        name: "",
                        subtitle: nil,
                        rawLabel: "",
                        normalizedName: "",
                        searchTokens: [],
                        isActive: true,
                        rawTypeMarker: nil,
                        metadata: DirectoryMetadata()
                    )
                    context.insert(DirectoryEntityRecord(
                        entity: fallback,
                        pictureID: pictureID,
                        lastFetched: TimeProvider.now
                    ))
                }
                try context.save()
            } catch {
                print("❌ Failed to save picture ID: \(error)")
            }
        }.value
    }

    func pictureURL(for entity: DirectoryEntity) -> URL? {
        // Rendering paths call this frequently. Directory snapshot loading and avatar
        // fetches populate this cache; never fall through to a synchronous SwiftData read.
        guard let pictureID = pictureIDCache[entity.id] else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(entity.gymId)/GetImage.aspx?pictureid=\(pictureID)&fullsize=1")
    }

    func resolvePersonByName(_ name: String, gymId: Int) -> DirectoryEntity? {
        let normalized = normalizedLookupName(name)
        guard !normalized.isEmpty else { return nil }

        if peopleByNormalizedNameByGym[gymId] == nil {
            _ = loadEntities(for: gymId, includeInactive: true)
        }
        return peopleByNormalizedNameByGym[gymId]?[normalized]
    }

    func pictureURL(forName name: String, gymId: Int) -> URL? {
        guard let person = resolvePersonByName(name, gymId: gymId) else { return nil }
        return pictureURL(for: person)
    }

    struct AvatarLookupResult {
        let resolved: [String: URL]
        let needsFetch: [(name: String, entity: DirectoryEntity)]
    }

    /// Single-pass batch resolution for avatar URLs by name. Loads gym records once,
    /// builds a normalized-name index, and returns ready URLs plus entities that still
    /// need a remote pictureID fetch. Avoids the N×M cost of per-name `loadEntities` calls.
    func batchAvatarLookup(forNames names: [String], gymId: Int) async -> AvatarLookupResult {
        if peopleByNormalizedNameByGym[gymId] == nil {
            _ = await loadEntitiesAsync(for: gymId, includeInactive: true)
        }
        let nameMap = peopleByNormalizedNameByGym[gymId] ?? [:]

        var resolved: [String: URL] = [:]
        var needsFetch: [(name: String, entity: DirectoryEntity)] = []

        for name in Set(names) {
            let normalized = normalizedLookupName(name)
            guard !normalized.isEmpty, let entity = nameMap[normalized] else { continue }
            if let pictureID = pictureIDCache[entity.id] {
                if let url = URL(string: "https://www.lectio.dk/lectio/\(gymId)/GetImage.aspx?pictureid=\(pictureID)&fullsize=1") {
                    resolved[name] = url
                }
            } else if entity.hasAvatar {
                needsFetch.append((name, entity))
            }
        }

        return AvatarLookupResult(resolved: resolved, needsFetch: needsFetch)
    }

    func fetchPictureIDIfNeeded(for entity: DirectoryEntity, authenticatedStudentID: String) async {
        if authenticatedStudentID == Student.demoStudentId { return }
        guard entity.hasAvatar else { return }
        guard await loadPictureIDAsync(for: entity.entityID) == nil else { return }
        guard !fetchingAvatarKeys.contains(entity.id) else { return }
        fetchingAvatarKeys.insert(entity.id)
        defer { fetchingAvatarKeys.remove(entity.id) }

        guard let credentials = keychainManager.loadCredentials(for: authenticatedStudentID) else {
            return
        }

        let httpClient = LectioHTTPClient()
        do {
            let html = try await httpClient.fetchStudentPage(
                credentials: credentials,
                studentId: authenticatedStudentID,
                schoolId: entity.gymId,
                targetStudentId: entity.numericID,
                isTeacher: entity.kind == .teacher,
                personName: entity.name,
                priority: .opportunistic
            )

            if let pictureID = await Task.detached(priority: .utility, operation: {
                StudentParser.parseStudentPictureId(from: html)
            }).value {
                await savePictureIDAsync(pictureID, for: entity.entityID)
            }
        } catch {
            print("⚠️ Failed to fetch picture for \(entity.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Logged-in Student Profile

    func saveLoggedInStudentInfo(pictureID: String?, classLabel: String?, for studentID: String, gymId: Int) {
        let entityID = DirectoryEntityID(gymId: gymId, kind: .student, rawID: "S\(studentID)")
        let current = loadEntity(id: entityID)
        let currentName = current?.name ?? ""
        let classCode = classLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let entity = DirectoryEntity(
            entityID: entityID,
            gymId: gymId,
            kind: .student,
            rawPrefixedID: "S\(studentID)",
            rawPrefix: "S",
            numericID: studentID,
            name: currentName,
            subtitle: classCode,
            rawLabel: current?.rawLabel ?? currentName,
            normalizedName: DirectoryParser.normalize(currentName),
            searchTokens: Array(Set([currentName, classCode].compactMap { $0 }.map(DirectoryParser.normalize))),
            isActive: true,
            rawTypeMarker: current?.rawTypeMarker,
            metadata: DirectoryMetadata(
                classCode: classCode,
                seatNumber: current?.seatNumber,
                abbreviation: current?.abbreviation,
                shortCode: current?.shortCode,
                subjectCode: current?.subjectCode,
                yearCode: current?.metadata.yearCode,
                groupSubtype: current?.groupSubtype,
                linkedBuiltinGroupID: current?.metadata.linkedBuiltinGroupID,
                linkedLectioClassID: current?.metadata.linkedLectioClassID,
                rawInfo: current?.metadata.rawInfo
            )
        )

        do {
            try upsertEntity(entity, lastFetched: TimeProvider.now)
            if let pictureID {
                savePictureID(pictureID, for: entityID)
            } else {
                try context.save()
            }
            entityCacheByID[entity.id] = entity
            peopleByNormalizedNameByGym[gymId, default: [:]][normalizedLookupName(entity.name)] = entity
        } catch {
            print("❌ Failed to save logged-in student info: \(error)")
        }
    }

    func saveLoggedInStudentInfoAsync(
        pictureID: String?,
        classLabel: String?,
        for studentID: String,
        gymId: Int
    ) async {
        let container = container
        let entityID = DirectoryEntityID(gymId: gymId, kind: .student, rawID: "S\(studentID)")
        let result: DirectoryEntity? = await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                let key = entityID.key
                var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.uniqueKey == key }
                )
                descriptor.fetchLimit = 1
                let record = try context.fetch(descriptor).first
                let current = record.flatMap(Self.toEntity)
                let currentName = current?.name ?? ""
                let classCode = classLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let entity = DirectoryEntity(
                    entityID: entityID,
                    gymId: gymId,
                    kind: .student,
                    rawPrefixedID: "S\(studentID)",
                    rawPrefix: "S",
                    numericID: studentID,
                    name: currentName,
                    subtitle: classCode,
                    rawLabel: current?.rawLabel ?? currentName,
                    normalizedName: DirectoryParser.normalize(currentName),
                    searchTokens: Array(Set([currentName, classCode].compactMap { $0 }.map(DirectoryParser.normalize))),
                    isActive: true,
                    rawTypeMarker: current?.rawTypeMarker,
                    metadata: DirectoryMetadata(
                        classCode: classCode,
                        seatNumber: current?.seatNumber,
                        abbreviation: current?.abbreviation,
                        shortCode: current?.shortCode,
                        subjectCode: current?.subjectCode,
                        yearCode: current?.metadata.yearCode,
                        groupSubtype: current?.groupSubtype,
                        linkedBuiltinGroupID: current?.metadata.linkedBuiltinGroupID,
                        linkedLectioClassID: current?.metadata.linkedLectioClassID,
                        rawInfo: current?.metadata.rawInfo
                    )
                )
                if let record {
                    Self.apply(entity, to: record, lastFetched: TimeProvider.now)
                    if let pictureID { record.pictureID = pictureID }
                } else {
                    context.insert(DirectoryEntityRecord(
                        entity: entity,
                        pictureID: pictureID,
                        lastFetched: TimeProvider.now
                    ))
                }
                try context.save()
                return entity
            } catch {
                print("❌ Failed to save logged-in student info: \(error)")
                return nil
            }
        }.value
        guard let result, !Task.isCancelled else { return }
        entityCacheByID[result.id] = result
        peopleByNormalizedNameByGym[gymId, default: [:]][normalizedLookupName(result.name)] = result
        if let pictureID { pictureIDCache[result.id] = pictureID }
    }

    func loadStudentInfo(for studentID: String, gymId: Int) -> (pictureId: String?, classLabel: String?)? {
        let entityID = DirectoryEntityID(gymId: gymId, kind: .student, rawID: "S\(studentID)")
        guard let entity = loadEntity(id: entityID) else { return nil }
        return (loadPictureID(for: entityID), entity.classCode)
    }

    func loadStudentInfoAsync(
        for studentID: String,
        gymId: Int
    ) async -> (pictureId: String?, classLabel: String?, name: String)? {
        let container = container
        let key = DirectoryEntityID(gymId: gymId, kind: .student, rawID: "S\(studentID)").key
        return await Task.detached(priority: .userInitiated) {
            do {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<DirectoryEntityRecord>(
                    predicate: #Predicate { $0.uniqueKey == key }
                )
                descriptor.fetchLimit = 1
                guard let record = try context.fetch(descriptor).first,
                      let entity = Self.toEntity(record) else { return nil }
                return (record.pictureID, entity.classCode, entity.name)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Clear

    func clearAllDirectoryData() {
        pictureIDCache.removeAll()
        entityCacheByID.removeAll()
        peopleByNormalizedNameByGym.removeAll()
        membershipCountsByGym.removeAll()
        do {
            try context.delete(model: DirectoryEntityRecord.self)
            try context.delete(model: DirectoryMembershipRecord.self)
            try context.save()
        } catch {
            print("❌ Failed to clear directory data: \(error)")
        }

        let defaults = UserDefaults.standard
        let prefixes = [
            "lectio.directory.pinned.",
            "lectio.directory.holdmembers.",
            "lectio.pinnedFriends.",
            "lectio.fetchedHoldIds."
        ]

        for key in defaults.dictionaryRepresentation().keys where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
    }

    func clearAllDirectoryDataAsync() async {
        pictureIDCache.removeAll()
        entityCacheByID.removeAll()
        peopleByNormalizedNameByGym.removeAll()
        membershipCountsByGym.removeAll()
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                try context.delete(model: DirectoryEntityRecord.self)
                try context.delete(model: DirectoryMembershipRecord.self)
                try context.save()
            } catch {
                print("❌ Failed to clear directory data: \(error)")
            }
        }.value

        let defaults = UserDefaults.standard
        let prefixes = [
            "lectio.directory.pinned.",
            "lectio.directory.holdmembers.",
            "lectio.pinnedFriends.",
            "lectio.fetchedHoldIds."
        ]
        for key in defaults.dictionaryRepresentation().keys
            where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Conversion

    private nonisolated static func toEntity(_ record: DirectoryEntityRecord) -> DirectoryEntity? {
        guard let kind = DirectoryEntityKind(rawValue: record.kindRaw) else { return nil }

        let metadata = (try? JSONDecoder().decode(DirectoryMetadata.self, from: record.metadataData)) ?? DirectoryMetadata()
        let tokens = (try? JSONDecoder().decode([String].self, from: record.searchTokensData)) ?? []

        return DirectoryEntity(
            entityID: DirectoryEntityID(gymId: record.gymId, kind: kind, rawID: record.rawPrefixedID),
            gymId: record.gymId,
            kind: kind,
            rawPrefixedID: record.rawPrefixedID,
            rawPrefix: record.rawPrefix,
            numericID: record.numericID,
            name: record.name,
            subtitle: record.subtitle,
            rawLabel: record.rawLabel,
            normalizedName: record.normalizedName,
            searchTokens: tokens,
            isActive: record.isActive,
            rawTypeMarker: record.rawTypeMarker,
            metadata: metadata
        )
    }

    private func cacheEntities(_ entities: [DirectoryEntity], gymId: Int) {
        entityCacheByID = entityCacheByID.filter { $0.value.gymId != gymId }
        var people: [String: DirectoryEntity] = [:]
        for entity in entities {
            entityCacheByID[entity.id] = entity
            if entity.isPerson {
                people[normalizedLookupName(entity.name)] = entity
            }
        }
        peopleByNormalizedNameByGym[gymId] = people
    }

    private func normalizedLookupName(_ name: String) -> String {
        var cleanName = name
        if let parenRange = cleanName.range(of: #"\s*\([^)]*\)\s*$"#, options: .regularExpression) {
            cleanName.removeSubrange(parenRange)
        }
        if cleanName.hasSuffix("(k)") {
            cleanName.removeLast(3)
        }
        return DirectoryParser.normalize(cleanName)
    }
}
