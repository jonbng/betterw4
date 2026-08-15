//
//  StudentManager.swift
//  BetterLectio
//

import Foundation
import Combine

/// Central manager for student data, handling background syncing and caching.
@MainActor
class StudentManager: ObservableObject {
    static let shared = StudentManager()
    
    // MARK: - Published Properties
    @Published private(set) var isSyncing = false
    @Published var lastSyncDate: Date?
    
    // MARK: - Services
    private let httpClient = LectioHTTPClient()
    private let store = StudentStore.shared
    private let keychainManager = KeychainManager.shared
    
    private init() {}
    
    /// Starts a background sync of all students for the given authenticated student.
    /// Uses `.opportunistic` priority to avoid blocking important fetches.
    func syncStudents(for student: Student) async {
        guard !isSyncing else { return }

        if student.isDemo {
            seedDemoDirectory(gymId: student.gymId)
            lastSyncDate = Date()
            return
        }

        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
            print("⚠️ [StudentManager] No stored credentials for sync")
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        
        print("🔄 [StudentManager] Starting background student sync...")
        
        do {
            // Step 1: Fetch the advanced schedule page to get dropdown URL
            let html = try await httpClient.fetchAdvancedSchedulePage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                priority: .opportunistic
            )
            
            // Step 2: Extract the dropdown URL
            guard let dropdownPath = await Task.detached(priority: .utility, operation: {
                StudentParser.parseDropdownURL(from: html)
            }).value else {
                print("❌ [StudentManager] Could not find student data URL")
                return
            }
            
            // Step 3: Fetch the dropdown JSON
            let data = try await httpClient.fetchDropdownData(
                credentials: credentials,
                studentId: student.studentId,
                relativePath: dropdownPath,
                priority: .opportunistic
            )
            
            // Step 4: Parse entries
            let entries = try await Task.detached(priority: .utility) {
                try StudentParser.parseDropdownEntries(from: data, gymId: student.gymId)
            }.value
            
            // Step 5: Save to store
            try store.upsertStudents(entries)
            lastSyncDate = Date()
            
            print("✅ [StudentManager] Fetched and cached \(entries.count) students/teachers")
            
            // Step 6: Trigger bulk picture ID fetch in background
            Task {
                await fetchBulkPictureIds(for: student)
            }
            
        } catch {
            print("❌ [StudentManager] Sync failed: \(error.localizedDescription)")
        }
    }
    
    /// Bulk-fetches picture IDs using hold list from homepage.
    private func fetchBulkPictureIds(for student: Student) async {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else { return }
        
        do {
            let homepageHtml = try await httpClient.fetchHomepage(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                priority: .opportunistic
            )
            
            let holds = await Task.detached(priority: .utility) {
                StudentParser.parseHoldsFromHomepage(from: homepageHtml)
            }.value
            guard !holds.isEmpty else { return }
            
            let sortedHolds = holds.sorted { a, b in
                let aHasAlle = a.name.localizedCaseInsensitiveContains("alle")
                let bHasAlle = b.name.localizedCaseInsensitiveContains("alle")
                if aHasAlle && !bHasAlle { return true }
                if !aHasAlle && bHasAlle { return false }
                return false
            }
            
            let fetchedHoldIds = loadFetchedHoldIds(for: student.gymId)
            let holdsToFetch = sortedHolds.filter { !fetchedHoldIds.contains($0.holdElementId) }
            
            if holdsToFetch.isEmpty { return }
            
            for hold in holdsToFetch {
                // Periodically check if we've fulfilled the need (optional, keeping simple for now)
                
                let teamHtml = try await httpClient.fetchTeamMembers(
                    credentials: credentials,
                    studentId: student.studentId,
                    schoolId: student.gymId,
                    holdElementId: hold.holdElementId,
                    priority: .opportunistic
                )
                
                let mapping = await Task.detached(priority: .utility) {
                    StudentParser.parseTeamMemberPictureIds(from: teamHtml)
                }.value
                if !mapping.isEmpty {
                    store.savePictureIds(mapping, gymId: student.gymId)
                }
                
                markHoldAsFetched(hold.holdElementId, gymId: student.gymId)
            }
        } catch {
            print("⚠️ [StudentManager] Bulk pictures failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Demo Mode

    private func seedDemoDirectory(gymId: Int) {
        let entries = DemoDataProvider.directoryStudents(gymId: gymId)
        try? store.upsertStudents(entries)
    }

    // MARK: - Persistence Helpers (Moved from ViewModel)
    
    private func fetchedHoldIdsKey(for gymId: Int) -> String {
        "lectio.fetchedHoldIds.\(gymId)"
    }
    
    private func loadFetchedHoldIds(for gymId: Int) -> Set<String> {
        let key = fetchedHoldIdsKey(for: gymId)
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(ids)
    }
    
    private func markHoldAsFetched(_ holdElementId: String, gymId: Int) {
        let key = fetchedHoldIdsKey(for: gymId)
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !ids.contains(holdElementId) {
            ids.append(holdElementId)
            UserDefaults.standard.set(ids, forKey: key)
        }
    }
}
