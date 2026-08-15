//
//  DirectorySyncService.swift
//  BetterLectio
//

import Foundation
import Combine

@MainActor
final class DirectorySyncService: ObservableObject {
    static let shared = DirectorySyncService()

    @Published private(set) var isSyncing = false
    @Published var lastSyncDate: Date?
    private var activeSyncCount = 0

    private let httpClient = LectioHTTPClient()
    private let store = DirectoryStore.shared
    private let keychainManager = KeychainManager.shared

    private init() {}

    func syncDirectory(for student: Student) async {
        if student.isDemo {
            let entities = DemoDataProvider.directoryEntities(gymId: student.gymId)
            try? await store.replaceDirectorySnapshot(gymId: student.gymId, entities: entities)
            lastSyncDate = Date()
            return
        }
        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
            print("⚠️ [DirectorySync] No stored credentials")
            return
        }

        activeSyncCount += 1
        isSyncing = true
        defer {
            activeSyncCount -= 1
            isSyncing = activeSyncCount > 0
        }

        do {
            let html = try await httpClient.fetchAdvancedSchedulePage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                priority: .opportunistic
            )

            guard let dropdownPath = await Task.detached(priority: .utility, operation: {
                StudentParser.parseDropdownURL(from: html)
            }).value else {
                print("❌ [DirectorySync] Could not find dropdown URL")
                return
            }

            let data = try await httpClient.fetchDropdownData(
                credentials: credentials,
                studentId: student.studentId,
                relativePath: dropdownPath,
                priority: .opportunistic
            )

            let entities = try await Task.detached(priority: .utility) {
                let rawItems = try DirectoryParser.parseRawDirectoryItems(from: data, gymId: student.gymId)
                return DirectoryParser.buildDirectoryEntities(from: rawItems, gymId: student.gymId)
            }.value
            try await store.replaceDirectorySnapshot(gymId: student.gymId, entities: entities)
            lastSyncDate = Date()

            let entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
            Task {
                await bootstrapHoldMembers(for: student, entitiesByID: entitiesByID)
            }

            print("✅ [DirectorySync] Cached \(entities.count) directory entities")
        } catch {
            print("❌ [DirectorySync] Failed: \(error.localizedDescription)")
        }
    }

    func ensureHoldMembersLoaded(for hold: DirectoryEntity, authenticatedStudent: Student) async {
        if authenticatedStudent.isDemo { return }
        guard hold.kind == .hold else { return }
        if store.memberCount(for: hold) > 0 {
            return
        }

        await fetchHoldMembers(for: hold, authenticatedStudent: authenticatedStudent)
    }

    private func bootstrapHoldMembers(
        for student: Student,
        entitiesByID: [String: DirectoryEntity]
    ) async {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else { return }

        do {
            let homepageHTML = try await httpClient.fetchHomepage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                priority: .opportunistic
            )

            let homepageHolds = await Task.detached(priority: .utility) {
                StudentParser.parseHoldsFromHomepage(from: homepageHTML)
            }.value
            for holdInfo in homepageHolds.prefix(12) {
                let entityID = DirectoryEntityID(gymId: student.gymId, kind: .hold, rawID: "HE\(holdInfo.holdElementId)")
                guard let hold = entitiesByID[entityID.key] else { continue }
                if store.memberCount(for: hold) > 0 { continue }
                await fetchHoldMembers(for: hold, authenticatedStudent: student)
            }
        } catch {
            print("⚠️ [DirectorySync] Failed to bootstrap hold members: \(error.localizedDescription)")
        }
    }

    private func fetchHoldMembers(for hold: DirectoryEntity, authenticatedStudent: Student) async {
        guard let credentials = keychainManager.loadCredentials(for: authenticatedStudent.studentId) else { return }

        do {
            let html = try await httpClient.fetchTeamMembers(
                credentials: credentials,
                studentId: authenticatedStudent.studentId,
                schoolId: authenticatedStudent.gymId,
                holdElementId: hold.numericID,
                priority: .opportunistic
            )

            let members = await Task.detached(priority: .utility) {
                DirectoryParser.parseHoldMembers(from: html, gymId: authenticatedStudent.gymId)
            }.value
            guard !members.isEmpty else { return }

            await store.replaceMembersAsync(for: hold, members: members)
        } catch {
            print("⚠️ [DirectorySync] Failed to fetch hold members for \(hold.name): \(error.localizedDescription)")
        }
    }
}
