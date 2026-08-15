//
//  DirectoryViewModel.swift
//  BetterLectio
//
import Combine
import Foundation
import SwiftUI

struct DirectorySearchSection: Identifiable, Sendable {
    let title: String
    let entities: [DirectoryEntity]

    var id: String { title }
}

private struct DirectoryDerivedData: Sendable {
    let entitiesByID: [String: DirectoryEntity]
    let studentsByClass: [String: [DirectoryEntity]]
    let teachers: [DirectoryEntity]
    let classes: [DirectoryEntity]
    let holds: [DirectoryEntity]
    let rooms: [DirectoryEntity]
    let resources: [DirectoryEntity]
    let groups: [DirectoryEntity]
    let messageRecipients: [DirectoryEntity]
    let memberCounts: [String: Int]
}

@MainActor
final class DirectoryViewModel: ObservableObject {
    @Published private(set) var entities: [DirectoryEntity] = []
    @Published var searchQuery = "" {
        didSet { scheduleSearch() }
    }
    @Published var isLoading = false
    @Published var pinnedEntityIDs: Set<String> = [] {
        didSet { rebuildPinnedPeople() }
    }

    private let store = DirectoryStore.shared
    private let syncService = DirectorySyncService.shared
    private var teacherCache: [String: [DirectoryEntity]] = [:]
    private var scheduleEventsByStudent: [String: [ScheduleEvent]] = [:]
    private var cachedTeachers: [DirectoryEntity] = []
    private var cachedClasses: [DirectoryEntity] = []
    private var cachedHolds: [DirectoryEntity] = []
    private var cachedRooms: [DirectoryEntity] = []
    private var cachedResources: [DirectoryEntity] = []
    private var cachedGroups: [DirectoryEntity] = []
    private var cachedMessageRecipients: [DirectoryEntity] = []
    @Published private(set) var cachedSearchSections: [DirectorySearchSection] = []
    private var cachedMemberCounts: [String: Int] = [:]
    private var cachedPinnedPeople: [DirectoryEntity] = []
    private var entitiesByID: [String: DirectoryEntity] = [:]
    private var studentsByClass: [String: [DirectoryEntity]] = [:]
    private var memberEntitiesCache: [String: [DirectoryEntity]] = [:]
    private var searchTask: Task<Void, Never>?
    private var activeLoadID: UUID?
    private var activeGymID: Int?

    func loadDirectory(for student: Student) async {
        let loadID = UUID()
        activeLoadID = loadID
        if activeGymID != student.gymId {
            activeGymID = student.gymId
            await applyEntities([], gymId: student.gymId, loadID: loadID)
            isLoading = true
        }
        let cachedEntities = await store.loadEntitiesAsync(for: student.gymId)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        await applyEntities(cachedEntities, gymId: student.gymId, loadID: loadID)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        if !cachedEntities.isEmpty { isLoading = false }
        teacherCache.removeAll(keepingCapacity: true)
        await loadScheduleEvents(for: student)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        loadPinnedEntities(for: student.studentId)

        if entities.isEmpty {
            isLoading = true
            await syncService.syncDirectory(for: student)
            let syncedEntities = await store.loadEntitiesAsync(for: student.gymId)
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            await applyEntities(syncedEntities, gymId: student.gymId, loadID: loadID)
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            teacherCache.removeAll(keepingCapacity: true)
            await loadScheduleEvents(for: student)
            if activeLoadID == loadID { isLoading = false }
        }
    }

    func refreshDirectory(for student: Student) async {
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        await syncService.syncDirectory(for: student)
        let syncedEntities = await store.loadEntitiesAsync(for: student.gymId)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        await applyEntities(syncedEntities, gymId: student.gymId, loadID: loadID)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        teacherCache.removeAll(keepingCapacity: true)
        await loadScheduleEvents(for: student)
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        loadPinnedEntities(for: student.studentId)
        isLoading = false
    }

    func reload(for gymId: Int) async {
        let loaded = await store.loadEntitiesAsync(for: gymId)
        guard !Task.isCancelled else { return }
        await applyEntities(loaded, gymId: gymId)
        teacherCache.removeAll(keepingCapacity: true)
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pinnedPeople: [DirectoryEntity] {
        cachedPinnedPeople
    }

    func classmates(for student: Student) -> [DirectoryEntity] {
        let classCode: String
        if let me = entities.first(where: { $0.kind == .student && $0.numericID == student.studentId }),
           let code = me.classCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            classCode = code
        } else if let label = student.classLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty {
            classCode = label
        } else {
            return []
        }

        return (studentsByClass[normalizedClassKey(classCode)] ?? [])
            .filter { $0.numericID != student.studentId }
    }

    /// Teachers inferred from cached schedule (ids and tooltip names). Empty if there is no schedule cache or nothing matches.
    func myTeachers(for student: Student) -> [DirectoryEntity] {
        if let cached = teacherCache[student.studentId] { return cached }
        let allTeachers = entities.filter { $0.kind == .teacher && $0.isActive }
        let events = scheduleEventsByStudent[student.studentId] ?? []
        guard !events.isEmpty else {
            teacherCache[student.studentId] = []
            return []
        }

        let ids = Set(events.compactMap(\.teacherId))
        if !ids.isEmpty {
            let matched = allTeachers.filter { ids.contains($0.numericID) }
            if !matched.isEmpty {
                let result = matched.sorted { $0.name < $1.name }
                teacherCache[student.studentId] = result
                return result
            }
        }

        var scheduleStrings: [String] = []
        for event in events {
            guard let raw = event.teacher?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            scheduleStrings.append(raw)
            scheduleStrings.append(contentsOf: raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }

        let normalizedSchedule = Set(scheduleStrings.map(DirectoryParser.normalize).filter { !$0.isEmpty })
        guard !normalizedSchedule.isEmpty else {
            teacherCache[student.studentId] = []
            return []
        }

        func words(_ normalized: String) -> Set<String> {
            Set(normalized.split(separator: " ").map(String.init).filter { $0.count >= 3 })
        }

        let result = allTeachers.filter { teacher in
            let tn = teacher.normalizedName
            if normalizedSchedule.contains(tn) { return true }
            let tw = words(tn)
            for s in normalizedSchedule {
                if s == tn { return true }
                if tn.contains(s) || s.contains(tn) { return true }
                if !tw.intersection(words(s)).isEmpty { return true }
            }
            return false
        }
        .sorted { $0.name < $1.name }
        teacherCache[student.studentId] = result
        return result
    }

    var teachers: [DirectoryEntity] {
        cachedTeachers
    }

    var classes: [DirectoryEntity] {
        cachedClasses
    }

    var holds: [DirectoryEntity] {
        cachedHolds
    }

    var rooms: [DirectoryEntity] {
        cachedRooms
    }

    var resources: [DirectoryEntity] {
        cachedResources
    }

    var groups: [DirectoryEntity] {
        cachedGroups
    }

    var messageRecipients: [DirectoryEntity] {
        cachedMessageRecipients
    }

    func searchSections() -> [DirectorySearchSection] {
        cachedSearchSections
    }

    private nonisolated static func buildSearchSections(
        query rawQuery: String,
        entities: [DirectoryEntity]
    ) -> [DirectorySearchSection] {
        let query = DirectoryParser.normalize(rawQuery)
        guard !query.isEmpty else { return [] }

        let scored: [(DirectoryEntity, Double)] = entities.compactMap { entity in
            guard entity.isActive else { return nil }
            let s = score(for: entity, query: query)
            return s > 0 ? (entity, s) : nil
        }

        let matches = scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.name < rhs.0.name
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)

        let maxPeopleScore = scored
            .filter { $0.0.kind == .student || $0.0.kind == .teacher }
            .map(\.1)
            .max() ?? 0
        let maxClassScore = scored
            .filter { $0.0.kind == .classSynthetic }
            .map(\.1)
            .max() ?? 0

        /// Strong class match (e.g. query is prefix of class code) should surface above people who only match via class token.
        let classesSectionFirst = maxClassScore >= 0.95 && maxClassScore > maxPeopleScore

        let people = matches.filter { $0.kind == .student || $0.kind == .teacher }
        let classes = matches.filter { $0.kind == .classSynthetic }
        let hold = matches.filter { $0.kind == .hold }
        let places = matches.filter { $0.kind == .room || $0.kind == .resource }
        let groups = matches.filter { $0.kind == .group || $0.kind == .classLectio || $0.kind == .other }

        let grouped: [(String, [DirectoryEntity])]
        if classesSectionFirst {
            grouped = [
                ("Klasser", classes),
                ("Personer", people),
                ("Hold", hold),
                ("Steder", places),
                ("Grupper", groups)
            ]
        } else {
            grouped = [
                ("Personer", people),
                ("Klasser", classes),
                ("Hold", hold),
                ("Steder", places),
                ("Grupper", groups)
            ]
        }

        return grouped.compactMap { title, entities in
            let trimmed = Array(entities.prefix(12))
            guard !trimmed.isEmpty else { return nil }
            return DirectorySearchSection(title: title, entities: trimmed)
        }
    }

    func entity(id: String) -> DirectoryEntity? {
        entitiesByID[id]
    }

    func students(in classEntity: DirectoryEntity) -> [DirectoryEntity] {
        guard classEntity.kind == .classSynthetic,
              let classCode = classEntity.classCode else {
            return []
        }
        return studentsByClass[normalizedClassKey(classCode)] ?? []
    }

    func members(of hold: DirectoryEntity) -> [DirectoryEntity] {
        memberEntitiesCache[hold.id] ?? []
    }

    func loadMembers(of hold: DirectoryEntity) async -> [DirectoryEntity] {
        if let cached = memberEntitiesCache[hold.id] { return cached }
        let members = await store.memberEntitiesAsync(for: hold)
        guard !Task.isCancelled else { return [] }
        memberEntitiesCache[hold.id] = members
        return members
    }

    func memberCount(of entity: DirectoryEntity) -> Int {
        switch entity.kind {
        case .classSynthetic:
            return cachedMemberCounts[entity.id] ?? 0
        case .hold:
            return cachedMemberCounts[entity.id] ?? 0
        case .student, .teacher, .classLectio, .room, .resource, .group, .other:
            return 0
        }
    }

    func relatedSyntheticClass(for group: DirectoryEntity) -> DirectoryEntity? {
        guard let linkedID = group.metadata.linkedBuiltinGroupID ?? group.metadata.linkedLectioClassID else {
            return nil
        }
        return classes.first(where: { $0.metadata.linkedBuiltinGroupID == linkedID || $0.metadata.linkedLectioClassID == linkedID })
    }

    func togglePin(for entity: DirectoryEntity, currentStudentID: String) {
        guard entity.isPerson else { return }
        if pinnedEntityIDs.contains(entity.id) {
            pinnedEntityIDs.remove(entity.id)
        } else {
            pinnedEntityIDs.insert(entity.id)
        }

        UserDefaults.standard.set(Array(pinnedEntityIDs), forKey: pinnedKey(for: currentStudentID))
    }

    func isPinned(_ entity: DirectoryEntity) -> Bool {
        pinnedEntityIDs.contains(entity.id)
    }

    func pictureURL(for entity: DirectoryEntity) -> URL? {
        store.pictureURL(for: entity)
    }

    func pictureURL(forName name: String, gymId: Int) -> URL? {
        store.pictureURL(forName: name, gymId: gymId)
    }

    func resolvePersonByName(_ name: String, gymId: Int) -> DirectoryEntity? {
        store.resolvePersonByName(name, gymId: gymId)
    }

    func ensureHoldMembers(for hold: DirectoryEntity, authenticatedStudent: Student) async {
        await syncService.ensureHoldMembersLoaded(for: hold, authenticatedStudent: authenticatedStudent)
        await reload(for: hold.gymId)
        objectWillChange.send()
    }

    private func loadPinnedEntities(for studentID: String) {
        let ids = UserDefaults.standard.stringArray(forKey: pinnedKey(for: studentID)) ?? []
        pinnedEntityIDs = Set(ids)
    }

    private func loadScheduleEvents(for student: Student) async {
        let schedule = await ScheduleStore.shared.loadScheduleAsync(for: student.studentId)
        guard !Task.isCancelled else { return }
        scheduleEventsByStudent[student.studentId] = schedule?.events ?? []
        teacherCache.removeValue(forKey: student.studentId)
    }

    private func applyEntities(
        _ newEntities: [DirectoryEntity],
        gymId: Int,
        loadID: UUID? = nil
    ) async {
        let storedMembershipCounts = store.cachedMemberCounts(gymId: gymId)
        let derived = await Task.detached(priority: .userInitiated) {
            Self.buildDerivedData(entities: newEntities, membershipCounts: storedMembershipCounts)
        }.value
        guard !Task.isCancelled,
              loadID == nil || activeLoadID == loadID else { return }
        entitiesByID = derived.entitiesByID
        studentsByClass = derived.studentsByClass
        memberEntitiesCache.removeAll(keepingCapacity: true)
        cachedTeachers = derived.teachers
        cachedClasses = derived.classes
        cachedHolds = derived.holds
        cachedRooms = derived.rooms
        cachedResources = derived.resources
        cachedGroups = derived.groups
        cachedMessageRecipients = derived.messageRecipients
        cachedMemberCounts = derived.memberCounts
        teacherCache.removeAll(keepingCapacity: true)
        entities = newEntities
        rebuildPinnedPeople()
        scheduleSearch()
    }

    private nonisolated static func buildDerivedData(
        entities: [DirectoryEntity],
        membershipCounts: [String: Int]
    ) -> DirectoryDerivedData {
        let entitiesByID = entities.reduce(into: [String: DirectoryEntity]()) { index, entity in
            index[entity.id] = entity
        }
        let studentsByClass = Dictionary(
            grouping: entities.filter { $0.kind == .student && $0.isActive }
        ) { normalizedClassLookupKey($0.classCode ?? "") }
            .mapValues { $0.sorted { $0.name < $1.name } }
        let teachers = entities.filter { $0.kind == .teacher && $0.isActive }.sorted { $0.name < $1.name }
        let classes = entities.filter { $0.kind == .classSynthetic }.sorted { $0.name < $1.name }
        let holds = entities.filter { $0.kind == .hold && $0.isActive }.sorted { $0.name < $1.name }
        let rooms = entities.filter { $0.kind == .room && $0.isActive }.sorted { $0.name < $1.name }
        let resources = entities.filter { $0.kind == .resource && $0.isActive }.sorted { $0.name < $1.name }
        let groups = entities.filter { $0.kind == .group && $0.isActive }.sorted { $0.name < $1.name }
        let messageRecipients = entities
            .filter { $0.isActive && $0.canMessage }
            .sorted { lhs, rhs in
                if lhs.kind == rhs.kind { return lhs.name < rhs.name }
                return lhs.kind.displayName < rhs.kind.displayName
            }
        var counts = membershipCounts
        for entity in classes {
            let key = normalizedClassLookupKey(entity.classCode ?? "")
            counts[entity.id] = studentsByClass[key]?.count ?? 0
        }
        return DirectoryDerivedData(
            entitiesByID: entitiesByID,
            studentsByClass: studentsByClass,
            teachers: teachers,
            classes: classes,
            holds: holds,
            rooms: rooms,
            resources: resources,
            groups: groups,
            messageRecipients: messageRecipients,
            memberCounts: counts
        )
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let snapshot = entities
        guard !DirectoryParser.normalize(query).isEmpty else {
            cachedSearchSections = []
            return
        }

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let sections = await Task.detached(priority: .userInitiated) {
                Self.buildSearchSections(query: query, entities: snapshot)
            }.value
            guard !Task.isCancelled, self?.searchQuery == query else { return }
            self?.cachedSearchSections = sections
        }
    }

    private func rebuildPinnedPeople() {
        cachedPinnedPeople = pinnedEntityIDs
            .compactMap { entitiesByID[$0] }
            .filter(\.isPerson)
            .sorted { $0.name < $1.name }
    }

    private nonisolated static func normalizedClassLookupKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedClassKey(_ value: String) -> String {
        Self.normalizedClassLookupKey(value)
    }

    private func pinnedKey(for studentID: String) -> String {
        "lectio.directory.pinned.\(studentID)"
    }

    private nonisolated static func score(for entity: DirectoryEntity, query: String) -> Double {
        if entity.normalizedName.hasPrefix(query) {
            return 1.0
        }

        if let token = entity.searchTokens.first(where: { $0.hasPrefix(query) }) {
            return token == entity.normalizedName ? 0.95 : 0.9
        }

        if entity.searchTokens.contains(where: { $0.contains(query) }) {
            return 0.7
        }

        if isSubsequence(query: query, target: entity.normalizedName) {
            let ratio = Double(query.count) / Double(max(entity.normalizedName.count, 1))
            return 0.45 + ratio * 0.2
        }

        return 0
    }

    private nonisolated static func isSubsequence(query: String, target: String) -> Bool {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return queryIndex == query.endIndex
    }
}
