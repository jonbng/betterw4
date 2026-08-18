//
//  DirectoryStore.swift
//  BetterW4
//
//  `Directory.store` — the people table (plan Wave 5 item 5.5, `features.md` §2.1).
//
//  What this file used to be: a Lectio dropdown cache, keyed on `"\(gymId)|\(kind)|S123"`, with a
//  nine-case entity taxonomy, a `pictureID` column fetched one person at a time, a stored search
//  token blob and a membership join table. None of that describes W4:
//
//    * W4 is one school on one host, so there is no `gymId` to scope by;
//    * `uwc_id` (`nc26abcd`) is globally unique, so it *is* the primary key;
//    * W4 has people and rooms, not nine kinds of dropdown row;
//    * photos are `{uwc_id}_thumb.jpg` — derived, so a `pictureID` column has nothing to hold, and
//      the third-party image-URL builder that read it is deleted rather than ported;
//    * with ~200 people the whole table fits in memory, so search is one computed normalized
//      string rather than a persisted token table;
//    * no page listing the members of a class has ever been captured, so
//      `DirectoryMembershipRecord` recorded a relationship this app cannot observe.
//
//  The `// MARK: - Legacy bridge` section exists only until Wave 6 rewires the view models. It
//  hands the old `DirectoryEntity` shape to code that still asks for it, built from W4 rows — it
//  never fetches, never stores and never builds a Lectio URL.
//
//  PII: names and UWC ids are never logged.
//

import Foundation
import SwiftData

// MARK: - Record

/// One person, keyed on their UWC id.
///
/// Not stored, on purpose: `photoURL` (derived from `uwcId`), `status` / `isOnline` (presence is
/// a this-second fact and a week-old "Online" is a lie), and any search token blob.
@Model
final class PersonRecord {
    @Attribute(.unique) var uwcId: String
    var name: String
    var preferredName: String?
    /// `DirectoryPersonKind.rawValue` — `student` or `staff`. Two cases, not nine.
    var kindRaw: String
    var year: String?
    var house: String?
    var country: String?
    var pronouns: String?
    var email: String?
    var subtitle: String?
    var isActive: Bool
    var lastFetched: Date

    init(
        uwcId: String,
        name: String,
        kindRaw: String,
        preferredName: String? = nil,
        year: String? = nil,
        house: String? = nil,
        country: String? = nil,
        pronouns: String? = nil,
        email: String? = nil,
        subtitle: String? = nil,
        isActive: Bool = true,
        lastFetched: Date
    ) {
        self.uwcId = uwcId
        self.name = name
        self.kindRaw = kindRaw
        self.preferredName = preferredName
        self.year = year
        self.house = house
        self.country = country
        self.pronouns = pronouns
        self.email = email
        self.subtitle = subtitle
        self.isActive = isActive
        self.lastFetched = lastFetched
    }
}

// MARK: - Store

@MainActor
final class DirectoryStore {

    static let shared = DirectoryStore()

    private let container: ModelContainer
    private let context: ModelContext

    /// The whole directory, in memory. ~200 rows: cheaper to keep than to query.
    private var peopleByUwcId: [String: DirectoryPerson] = [:]
    /// One index, keyed by normalized name (`features.md` §2.1 — the per-gym dictionary of
    /// dictionaries is gone with `gymId`).
    private var peopleByNormalizedName: [String: DirectoryPerson] = [:]
    private var hasLoadedFromDisk = false

    /// `inMemory` exists for tests; the app always uses the on-disk `Directory.store`.
    init(inMemory: Bool = false) {
        let storeDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = storeDirectory.appendingPathComponent("Directory.store")
        let config = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: storeURL)

        // The three-step recovery ladder is verbatim from `ScheduleStore` and exists because a
        // schema change on a shared store file produced "no such table" crashes at launch. The
        // W4 schema *is* such a change: `DirectoryEntityRecord` is gone.
        do {
            container = try ModelContainer(for: PersonRecord.self, configurations: config)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            print("⚠️ Failed to initialize DirectoryStore, attempting recovery: \(error)")
            Self.removeSQLiteStore(at: storeURL)
            do {
                container = try ModelContainer(for: PersonRecord.self, configurations: config)
                context = ModelContext(container)
                context.autosaveEnabled = true
            } catch {
                print("⚠️ DirectoryStore recovery failed; using memory-only cache: \(error)")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    container = try ModelContainer(for: PersonRecord.self, configurations: memoryConfig)
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

    // MARK: - Writing

    /// Replaces the whole people table with one sweep's result.
    ///
    /// An empty list is refused: a failed sweep must never be able to erase a directory the app
    /// already has. `DirectoryRepository` already declines to call this with nothing, and this is
    /// the second lock on the same door.
    func replacePeople(_ people: [DirectoryPerson]) async {
        guard !people.isEmpty else { return }
        let container = container
        let incoming = people
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let now = TimeProvider.now
            do {
                let existing = try context.fetch(FetchDescriptor<PersonRecord>())
                var byKey = Dictionary(existing.map { ($0.uwcId, $0) }, uniquingKeysWith: { first, _ in first })
                let incomingKeys = Set(incoming.map(\.uwcId))

                for person in incoming {
                    if let record = byKey.removeValue(forKey: person.uwcId) {
                        Self.apply(person, to: record, lastFetched: now)
                    } else {
                        context.insert(Self.makeRecord(person, lastFetched: now))
                    }
                }
                for record in existing where !incomingKeys.contains(record.uwcId) {
                    context.delete(record)
                }
                try context.save()
            } catch {
                print("❌ Failed to replace the directory: \(error)")
            }
        }.value

        rebuildIndex(with: people)
        hasLoadedFromDisk = true
    }

    /// Merges rows in without deleting anybody — a single list page or a resolved profile.
    func upsertPeople(_ people: [DirectoryPerson]) async {
        guard !people.isEmpty else { return }
        let container = container
        let incoming = people
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let now = TimeProvider.now
            do {
                let existing = try context.fetch(FetchDescriptor<PersonRecord>())
                var byKey = Dictionary(existing.map { ($0.uwcId, $0) }, uniquingKeysWith: { first, _ in first })
                for person in incoming {
                    if let record = byKey[person.uwcId] {
                        Self.apply(person, to: record, lastFetched: now)
                    } else {
                        let record = Self.makeRecord(person, lastFetched: now)
                        context.insert(record)
                        byKey[person.uwcId] = record
                    }
                }
                try context.save()
            } catch {
                print("❌ Failed to upsert directory people: \(error)")
            }
        }.value

        for person in people {
            merge(person)
        }
    }

    // MARK: - Reading

    /// Everybody on disk, name-ordered, decoded off the main actor.
    func allPeopleAsync() async -> [DirectoryPerson] {
        let container = container
        let people = await Task.detached(priority: .userInitiated) { () -> [DirectoryPerson] in
            do {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<PersonRecord>(
                    sortBy: [SortDescriptor(\PersonRecord.name, order: .forward)]
                )
                return try context.fetch(descriptor).map(Self.toPerson)
            } catch {
                print("❌ Failed to load the directory: \(error)")
                return []
            }
        }.value

        rebuildIndex(with: people)
        hasLoadedFromDisk = true
        return people
    }

    /// Everybody the store has already loaded, with no disk access. Empty before the first load.
    var cachedPeople: [DirectoryPerson] {
        peopleByUwcId.values.sorted { $0.displayName < $1.displayName }
    }

    /// The one name index, exposed to the legacy bridge below.
    var normalizedNameIndex: [String: DirectoryPerson] { peopleByNormalizedName }

    func personAsync(uwcId: String) async -> DirectoryPerson? {
        let id = uwcId.lowercased()
        if let cached = peopleByUwcId[id] { return cached }
        if !hasLoadedFromDisk { _ = await allPeopleAsync() }
        return peopleByUwcId[id]
    }

    func person(uwcId: String) -> DirectoryPerson? {
        peopleByUwcId[uwcId.lowercased()]
    }

    /// Loads the table into memory once, so the synchronous accessors have something to answer
    /// with. Cheap and idempotent.
    func warmUpAsync() async {
        guard !hasLoadedFromDisk else { return }
        _ = await allPeopleAsync()
    }

    // MARK: - Photos

    /// W4's photo convention: `/files/user_photos/{uwc_id}_thumb.jpg`.
    ///
    /// Derived, so there is nothing to fetch and nothing to store. The Lectio picture-id image
    /// URL builder this replaces is deleted, not ported.
    nonisolated func photoURL(forUwcId uwcId: String) -> URL? {
        W4PeopleParser.photoURL(forUWCId: uwcId)
    }

    // MARK: - Clearing

    func clearAllDirectoryData() {
        peopleByUwcId.removeAll()
        peopleByNormalizedName.removeAll()
        hasLoadedFromDisk = false
        do {
            try context.delete(model: PersonRecord.self)
            try context.save()
        } catch {
            print("❌ Failed to clear directory data: \(error)")
        }
        Self.clearDirectoryDefaults()
    }

    func clearAllDirectoryDataAsync() async {
        peopleByUwcId.removeAll()
        peopleByNormalizedName.removeAll()
        hasLoadedFromDisk = false
        let container = container
        await Task.detached(priority: .utility) {
            do {
                let context = ModelContext(container)
                try context.delete(model: PersonRecord.self)
                try context.save()
            } catch {
                print("❌ Failed to clear directory data: \(error)")
            }
        }.value
        Self.clearDirectoryDefaults()
    }

    /// Pins and the Lectio-era sync bookkeeping. Pins are scoped per uwc id
    /// (`w4.directory.pinned.<uwcId>`), so "clear cache" drops every account's.
    private nonisolated static func clearDirectoryDefaults() {
        let defaults = UserDefaults.standard
        let prefixes = [
            "w4.directory.pinned.",
            "w4.directory.holdmembers.",
            "w4.pinnedFriends.",
            "w4.fetchedHoldIds."
        ]
        for key in defaults.dictionaryRepresentation().keys
            where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Index

    private func rebuildIndex(with people: [DirectoryPerson]) {
        peopleByUwcId = Dictionary(people.map { ($0.uwcId, $0) }, uniquingKeysWith: { _, latest in latest })
        peopleByNormalizedName = [:]
        for person in people {
            let key = DirectorySearchText.normalize(person.displayName)
            guard !key.isEmpty else { continue }
            if peopleByNormalizedName[key] == nil { peopleByNormalizedName[key] = person }
        }
    }

    private func merge(_ person: DirectoryPerson) {
        peopleByUwcId[person.uwcId] = person
        let key = DirectorySearchText.normalize(person.displayName)
        if !key.isEmpty { peopleByNormalizedName[key] = person }
    }

    // MARK: - Conversion

    private nonisolated static func makeRecord(_ person: DirectoryPerson, lastFetched: Date) -> PersonRecord {
        PersonRecord(
            uwcId: person.uwcId,
            name: person.name,
            kindRaw: person.kind.rawValue,
            preferredName: person.preferredName,
            year: person.year,
            house: person.house,
            country: person.country,
            pronouns: person.pronouns,
            email: person.email,
            subtitle: person.subtitle,
            isActive: true,
            lastFetched: lastFetched
        )
    }

    /// Fills gaps rather than overwriting with nothing: a list row that carries only a name must
    /// not wipe the country a profile fetch already resolved.
    private nonisolated static func apply(_ person: DirectoryPerson, to record: PersonRecord, lastFetched: Date) {
        record.name = person.name
        record.kindRaw = person.kind.rawValue
        record.preferredName = person.preferredName ?? record.preferredName
        record.year = person.year ?? record.year
        record.house = person.house ?? record.house
        record.country = person.country ?? record.country
        record.pronouns = person.pronouns ?? record.pronouns
        record.email = person.email
        record.subtitle = person.subtitle ?? record.subtitle
        record.isActive = true
        record.lastFetched = lastFetched
    }

    private nonisolated static func toPerson(_ record: PersonRecord) -> DirectoryPerson {
        let kind = DirectoryPersonKind(rawValue: record.kindRaw) ?? .student
        return DirectoryPerson(
            uwcId: record.uwcId,
            name: record.name,
            kind: kind,
            preferredName: record.preferredName,
            year: record.year,
            house: record.house,
            country: record.country,
            pronouns: record.pronouns,
            subtitle: record.subtitle,
            // Presence is never persisted: a stored "Online" would be a lie the moment the app
            // relaunches.
            status: nil,
            isOnline: nil,
            photoURL: W4PeopleParser.photoURL(forUWCId: record.uwcId)
        )
    }
}

// MARK: - Legacy bridge

/// Everything below exists so the Wave-4 view models and views keep compiling and keep working
/// while Wave 6 rewires them onto `DirectoryRepository`. It is a *view* of the W4 people table in
/// the old `DirectoryEntity` shape — no network, no Lectio URL, no `pictureID`, no `gymId`
/// meaning. Delete it with the last caller.
extension DirectoryStore {

    /// Nothing to fetch: on W4 a person's portrait URL is derived from their UWC id, so the old
    /// "fetch this person's pictureId" round trip has no W4 equivalent. Kept as a no-op so the
    /// avatar views compile until Wave 6 drops the call.
    func fetchPictureIDIfNeeded(for entity: DirectoryEntity, authenticatedStudentID: String) async {}

    func pictureURL(for entity: DirectoryEntity) -> URL? {
        guard entity.isPerson else { return nil }
        return W4PeopleParser.photoURL(forUWCId: entity.numericID)
    }

    /// W4 exposes no page listing the members of a class, so there is no membership table and
    /// nothing to answer with (`features.md` §1.12).
    func memberEntitiesAsync(for parent: DirectoryEntity) async -> [DirectoryEntity] { [] }

    func memberCount(for parent: DirectoryEntity) -> Int { 0 }

    // MARK: Bridge internals

    /// A W4 person in the old entity shape. `numericID` carries the UWC id, which is what the
    /// remaining call sites actually use it for (`StudentSearchView` already falls back to
    /// `StudentProfile.photoURL(forUWCID: entity.numericID)`).
    nonisolated static func legacyEntity(_ person: DirectoryPerson) -> DirectoryEntity {
        let kind: DirectoryEntityKind = person.kind == .staff ? .teacher : .student
        let entityID = DirectoryEntityID(kind: kind, rawID: person.uwcId)
        let displayName = person.displayName
        let normalized = DirectorySearchText.normalize(displayName)
        var tokens = Set(normalized.split(separator: " ").map(String.init))
        tokens.insert(normalized)
        tokens.insert(person.uwcId)
        if let country = person.country { tokens.insert(DirectorySearchText.normalize(country)) }
        if let house = person.house { tokens.insert(DirectorySearchText.normalize(house)) }
        tokens = tokens.filter { !$0.isEmpty }

        return DirectoryEntity(
            entityID: entityID,
            kind: kind,
            rawPrefixedID: person.uwcId,
            rawPrefix: "",
            numericID: person.uwcId,
            name: displayName,
            subtitle: person.subtitle,
            rawLabel: displayName,
            normalizedName: normalized,
            searchTokens: Array(tokens),
            isActive: true,
            rawTypeMarker: nil,
            metadata: DirectoryMetadata(
                classCode: person.year.map { "Year \($0)" },
                rawInfo: person.subtitle
            )
        )
    }
}
